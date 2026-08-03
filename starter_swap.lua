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
-- The before_give hook marks the intent during Oak's Pikachu gift.
-- The extra grant is applied immediately during that same gift flow.
-- This keeps the implementation fully inside mod files (no engine edits)
-- and avoids relying on a later map transition.
--
-- The hook marks only when all three conditions are true:
--   1. The ROM is Yellow (GameVersion.isYellow()).
--   2. The gift originates from Oak's Lab (overworld map id == "OAKS_LAB").
--   3. The active character has a non-nil starterSpecies in the catalog.

local StarterSwap = {}
local EXTRA_STARTER_GIVEN_FLAG = "EVENT_WTT_EXTRA_STARTER_GRANTED"
local GRANT_IN_PROGRESS = false

-- Lookup table built at init time: character id -> starterSpecies string.
-- Populated from the Characters array; custom characters are included
-- because CustomCharacterLoader injects them before CharacterSwap.init.
local STARTER_BY_CHAR_ID = {}

function StarterSwap.init(mod, Characters, CharacterSwap)
  -- Build the lookup from the full character list (built-ins + customs).
  for _, char in ipairs(Characters) do
    if type(char.starterSpecies) == "string" and char.starterSpecies ~= "" then
      STARTER_BY_CHAR_ID[char.id] = char.starterSpecies
    end
  end

  -- Mark pending extra starter when Oak gives Pikachu in Yellow.
  mod.events:on("pokemon.before_give", function(gift)
    -- Guard 1: Yellow only.
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if not ok or not GameVersion.isYellow() then return end

    -- Guard 2: gift must originate from Oak's Lab and be the vanilla Pikachu gift.
    local ctx = gift.ctx
    local ow  = ctx and ctx.overworld
    if not (ow and ow.map and ow.map.id == "OAKS_LAB") then return end
    if gift.species ~= "PIKACHU" then return end

    -- Guard 4: run once per save file.
    local flags = ctx.save and ctx.save.flags
    if flags and flags[EXTRA_STARTER_GIVEN_FLAG] then return end

    -- Guard 5: active character must have a starterSpecies configured.
    local charId  = CharacterSwap._resolveSelectedId(mod)
    local species = STARTER_BY_CHAR_ID[charId]
    if not species then return end
    if species == "PIKACHU" then return end

    -- Guard 6: species must exist in the game data to avoid a silent crash.
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
    GRANT_IN_PROGRESS = true
    Commands.give_pokemon(ctx, species, level, true)
    GRANT_IN_PROGRESS = false

    if ctx.lastCheck == false then
      mod.log:warn(
        "starter_swap: failed to grant extra starter %q (party/boxes full?)",
        species
      )
      return
    end

    if flags then
      flags[EXTRA_STARTER_GIVEN_FLAG] = true
    end

    local boxNum = tonumber(ctx.boxNum)
    if boxNum and boxNum > 0 then
      mod.log:info(
        "starter_swap: granted extra starter %q to BOX %d (kept original Pikachu) for character %q",
        species, boxNum, CharacterSwap._resolveSelectedId(mod)
      )
    else
      mod.log:info(
        "starter_swap: granted extra starter %q to party (kept original Pikachu) for character %q",
        species, CharacterSwap._resolveSelectedId(mod)
      )
    end
  end)
end

return StarterSwap
