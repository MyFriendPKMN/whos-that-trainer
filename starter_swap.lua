-- starter_swap.lua
-- Intercepts pokemon.before_give on Pokémon Yellow to replace the starter
-- Pikachu Oak gives the player with the active character's starterSpecies.
--
-- Behaviour by version:
--   Yellow  — Oak gives one fixed Pokémon (PIKACHU). If the active character
--             has a non-nil starterSpecies and that species exists in the game
--             data, the gift species is replaced. Level stays 5 (vanilla).
--   Red/Blue — no-op. The player still picks from three Poké Balls; the
--             rival counter-pick logic and EVENT_CHOSE_* flags are untouched.
--
-- The hook fires only when all three conditions are true:
--   1. The ROM is Yellow (GameVersion.isYellow()).
--   2. The gift originates from Oak's Lab (overworld map id == "OAKS_LAB").
--   3. The active character has a non-nil starterSpecies in the catalog.

local StarterSwap = {}

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

  -- Register the before_give hook. Runs on every give_pokemon call, but
  -- the guards inside keep it a no-op in all non-Yellow / non-Oak scenarios.
  mod.events:on("pokemon.before_give", function(gift)
    -- Guard 1: Yellow only.
    local ok, GameVersion = pcall(require, "src.core.GameVersion")
    if not ok or not GameVersion.isYellow() then return end

    -- Guard 2: gift must originate from Oak's Lab.
    local ctx = gift.ctx
    local ow  = ctx and ctx.overworld
    if not (ow and ow.map and ow.map.id == "OAKS_LAB") then return end

    -- Guard 3: active character must have a starterSpecies configured.
    local charId  = CharacterSwap._resolveSelectedId(mod)
    local species = STARTER_BY_CHAR_ID[charId]
    if not species then return end

    -- Guard 4: species must exist in the game data to avoid a silent crash.
    local data = ctx.game and ctx.game.data
    if not (data and data.pokemon and data.pokemon[species]) then
      mod.log:warn(
        "starter_swap: starterSpecies %q for character %q not found in game data — keeping default starter",
        species, charId
      )
      return
    end

    -- All guards passed: replace the species. Level stays at gift.level (5).
    mod.log:info(
      "starter_swap: replacing Oak's starter %q with %q for character %q",
      tostring(gift.species), species, charId
    )
    gift.species = species
  end)
end

return StarterSwap
