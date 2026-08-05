-- starter_swap.lua
-- On Pokémon Yellow, keeps Oak's original Pikachu and grants the active
-- character's configured starterSpecies as an extra starter.
--
-- Behaviour by version:
--   Yellow  — Oak gives one fixed Pokémon (PIKACHU). If the active character
--             has a non-nil starterSpecies and that species exists in the game
--             data, the mod grants it as an extra starter right after Pikachu.
--   Red/Blue — no-op. The player still picks from three Poké Balls; the
--             rival counter-pick logic and EVENT_CHOSE_* flags are untouched.
--
-- The before_give hook intercepts Oak's Pikachu gift and immediately grants
-- the extra starter using an isolated ctx (no runner, shadowed pokedex.owned).
--
-- Two isolation concerns:
--   1. Runner isolation: Commands.give_pokemon with the original ctx and an
--      active runner can call Commands.show_text (for box deposits), advancing
--      the runner's coroutine and skipping set_flag("EVENT_GOT_STARTER").
--   2. Pokedex.owned isolation: Oak's lab script checks check_dex_owned(2)
--      before the parcel branch. With Pikachu + extra starter both marked as
--      owned, that check fires true and Oak jumps to the dex-rating speech,
--      bypassing the parcel delivery entirely. The extra starter's owned entry
--      is deferred until EVENT_GOT_POKEDEX is set.

local StarterSwap = {}
local EXTRA_STARTER_GIVEN_FLAG = "EVENT_WTT_EXTRA_STARTER_GRANTED"
local GRANT_IN_PROGRESS = false

-- Lookup table built at init time: character id -> starterSpecies string.
-- Populated from the Characters array; custom characters are included
-- because CustomCharacterLoader injects them before CharacterSwap.init.
local STARTER_BY_CHAR_ID = {}

-- ---------------------------------------------------------------------------
-- Save migration: repair saves broken by the runner-corruption bug.
--
-- Affected saves have all of the following true on Yellow:
--   EVENT_WTT_EXTRA_STARTER_GRANTED  (extra starter was given via the old code)
--   EVENT_GOT_STARTER                (flag was set by the Eevee ball script)
--   EVENT_BATTLED_RIVAL_IN_OAKS_LAB  (rival was defeated)
--   EVENT_GOT_OAKS_PARCEL            (player fetched the parcel)
-- And all of the following absent/false (the Pokedex scene never completed):
--   EVENT_GOT_POKEDEX
--   EVENT_OAK_GOT_PARCEL
--
-- The fix applies all flags the Pokedex scene would have set, plus the
-- Viridian old-man object toggles that unblock the catching tutorial.
-- ---------------------------------------------------------------------------
local function _repairBrokenPokedexScene(mod, save)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok or not GameVersion.isYellow() then return end

  local f = save and save.flags
  if not f then return end

  -- Must have reached Oak with the parcel but NOT completed the scene.
  if not (f.EVENT_WTT_EXTRA_STARTER_GRANTED
      and f.EVENT_GOT_STARTER
      and f.EVENT_BATTLED_RIVAL_IN_OAKS_LAB
      and f.EVENT_GOT_OAKS_PARCEL) then
    return
  end
  if f.EVENT_GOT_POKEDEX or f.EVENT_OAK_GOT_PARCEL then
    return  -- scene already completed normally
  end

  mod.log:warn(
    "starter_swap: detected save broken by runner-corruption bug — "
    .. "applying Pokedex scene flags as migration"
  )

  -- Remove the parcel from inventory (the scene's take_item was never executed).
  if type(save.inventory) == "table" then
    save.inventory["OAKS_PARCEL"] = nil
  end

  -- Flags set by the Pokedex scene in oaks_lab_yellow.lua
  f.EVENT_GOT_POKEDEX                = true
  f.EVENT_OAK_GOT_PARCEL             = true
  f.EVENT_1ST_ROUTE22_RIVAL_BATTLE   = true
  f.EVENT_ROUTE22_RIVAL_WANTS_BATTLE = true
  f.EVENT_2ND_ROUTE22_RIVAL_BATTLE   = nil  -- clear_flag in the script

  -- Object toggles: Viridian old man (catching tutorial unblock)
  local toggles = save.objectToggles
  if type(toggles) == "table" then
    local vc = toggles["VIRIDIAN_CITY"]
    if type(vc) == "table" then
      vc["VIRIDIANCITY_OLD_MAN_SLEEPY"] = false
      vc["VIRIDIANCITY_OLD_MAN2"]       = true
    end
    -- Hide the Pokedex sprites on the lab table
    local ol = toggles["OAKS_LAB"]
    if type(ol) == "table" then
      ol["OAKSLAB_POKEDEX1"] = false
      ol["OAKSLAB_POKEDEX2"] = false
    end
    -- Show the Route 22 rival
    local r22 = toggles["ROUTE_22"]
    if type(r22) == "table" then
      r22["ROUTE22_RIVAL1"] = true
    end
  end

  mod.log:info("starter_swap: migration complete — EVENT_GOT_POKEDEX is now set")
end

function StarterSwap.init(mod, Characters, CharacterSwap)
  -- Build the lookup from the full character list (built-ins + customs).
  for _, char in ipairs(Characters) do
    if type(char.starterSpecies) == "string" and char.starterSpecies ~= "" then
      STARTER_BY_CHAR_ID[char.id] = char.starterSpecies
    end
  end

  -- Run the save migration on every load to repair saves broken by the old bug.
  mod.events:on("save.loaded", function(ev)
    local save = ev and ev.save
    local repairOk, repairErr = pcall(_repairBrokenPokedexScene, mod, save)
    if not repairOk then
      mod.log:warn("starter_swap: migration check failed: %s", tostring(repairErr))
    end
  end)

  -- Grant the extra starter when Oak gives Pikachu in Yellow.
  mod.events:on("pokemon.before_give", function(gift)
    -- Guard 1: Yellow only.
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if not ok or not GameVersion.isYellow() then return end

    -- Guard 2: gift must originate from Oak's Lab and be the vanilla Pikachu gift.
    local ctx = gift.ctx
    local ow  = ctx and ctx.overworld
    if not (ow and ow.map and ow.map.id == "OAKS_LAB") then return end
    if gift.species ~= "PIKACHU" then return end

    -- Guard 3: run once per save file.
    local flags = ctx.save and ctx.save.flags
    if flags and flags[EXTRA_STARTER_GIVEN_FLAG] then return end

    -- Guard 4: active character must have a starterSpecies configured.
    local charId  = CharacterSwap._resolveSelectedId(mod)
    local species = STARTER_BY_CHAR_ID[charId]
    if not species then return end
    if species == "PIKACHU" then return end

    -- Guard 5: species must exist in the game data to avoid a silent crash.
    local data = ctx.game and ctx.game.data
    if not (data and data.pokemon and data.pokemon[species]) then
      mod.log:warn(
        "starter_swap: starterSpecies %q for character %q not found in game data — keeping Pikachu-only starter",
        species, charId
      )
      return
    end

    -- Re-entrancy guard: Commands.give_pokemon emits pokemon.before_give too.
    if GRANT_IN_PROGRESS then return end

    -- All guards passed: keep Pikachu and add configured starter immediately.
    local Commands = require("src.script.Commands")
    local level = 5

    -- Build an isolated save that shadows pokedex.owned with a deferred proxy.
    -- This prevents the extra starter from being counted as "owned" before
    -- EVENT_GOT_POKEDEX is set, which would cause check_dex_owned(2) to fire
    -- true at the top of TEXT_OAKSLAB_OAK1 and skip the parcel delivery branch.
    local realPokedex = ctx.save and ctx.save.pokedex
    local deferredOwned = {}
    local ownedProxy = setmetatable({}, {
      __newindex = function(_, k, v)
        -- If the player already has the Pokedex (e.g. on a second playthrough
        -- or if the scene completed before this hook fires), apply immediately.
        if ctx.save.flags and ctx.save.flags.EVENT_GOT_POKEDEX then
          if realPokedex then rawset(realPokedex.owned, k, v) end
        else
          deferredOwned[k] = v
        end
      end,
      __index = function(_, k)
        return realPokedex and rawget(realPokedex.owned, k)
      end,
    })
    local shadowPokedex = {
      seen  = realPokedex and realPokedex.seen  or {},
      owned = ownedProxy,
    }
    local shadowSave = {}
    for k, v in pairs(ctx.save) do shadowSave[k] = v end
    shadowSave.pokedex = shadowPokedex

    -- Isolated ctx: no runner (prevents show_text side-effects from advancing
    -- the original runner's coroutine and skipping downstream script steps).
    local isolatedCtx = {
      game   = ctx.game,
      save   = shadowSave,
      runner = nil,
    }

    GRANT_IN_PROGRESS = true
    Commands.give_pokemon(isolatedCtx, species, level, true)
    GRANT_IN_PROGRESS = false

    if isolatedCtx.lastCheck == false then
      mod.log:warn(
        "starter_swap: failed to grant extra starter %q (party/boxes full?)",
        species
      )
      return
    end

    -- Register a one-shot listener to flush the deferred owned entries once
    -- Oak gives the Pokedex. This ensures the species appear as owned in the
    -- Pokedex immediately after the scene without affecting the parcel check.
    if next(deferredOwned) then
      mod.events:on("flag.changed", function(ev)
        if ev and ev.flag == "EVENT_GOT_POKEDEX" and ev.value == true then
          if realPokedex then
            for k, v in pairs(deferredOwned) do
              realPokedex.owned[k] = v
            end
          end
          deferredOwned = {}
        end
      end)
    end

    if flags then
      flags[EXTRA_STARTER_GIVEN_FLAG] = true
    end

    local boxNum = tonumber(isolatedCtx.boxNum)
    if boxNum and boxNum > 0 then
      mod.log:info(
        "starter_swap: granted extra starter %q to BOX %d (kept original Pikachu) for character %q",
        species, boxNum, charId
      )
    else
      mod.log:info(
        "starter_swap: granted extra starter %q to party (kept original Pikachu) for character %q",
        species, charId
      )
    end
  end)
end

return StarterSwap
