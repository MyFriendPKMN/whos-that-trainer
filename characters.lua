-- characters.lua
-- Canonical list of built-in characters for the Who's That Trainer? mod.
-- Each entry maps to two sprite registry ids:
--   walk id  : MOD_WTT_SPRITE_<NAME>
--   back id  : MOD_WTT_BACK_<NAME>   (simple image path, not a walk sheet)
--
-- Sprites are generated at runtime by transforms.lua via the Asset_Transform pipeline.
-- No images are shipped in this mod directory (Requirement 5.3).
--
-- RED uses walkImage = nil because it reuses the engine's vanilla sprite via FieldDefaults.
-- GIOVANNI, BROCK, and BLUE have backPath and frontPath; characters without a dedicated
-- sprite use their own walkImage as fallback for both back and front in battle.
-- Some ROM caches do not provide every gym/elite overworld walk sprite.
-- For those cases, walkFallback keeps the character selectable by using RED
-- in overworld while still keeping that character's battle front/back assets.
--
-- mirrorBack: when true, the back sprite is horizontally flipped in battle.
-- Trainer opponent sprites face left (toward the player), but when used as the
-- player's back sprite they need to face right (toward the opponent).
--
-- starterSpecies: when set (non-nil), overrides the Pokémon Oak gives the player
-- on Pokémon Yellow. Has no effect on Red/Blue (player still picks from 3 balls).
-- Use the engine's species key string: "GEODUDE", "STARYU", etc.
--
-- Note: Paths are relative to the asset cache created by RomExtractor
-- during the player's ROM import. The mod does not distribute assets.
return {
  {
    id            = "RED", -- internal id persisted in mod.save/options (logical character key)
    label         = "RED", -- text shown in the mod options/selection menu
    walkId        = "MOD_PSS_SPRITE_RED", -- sprite registry id used for overworld walking
    walkImage     = nil, -- RED uses the engine's vanilla sprite (no custom mod image registration)
    backPath      = "assets/generated/battle/redb.png", -- back sprite used in battle (side=back)
    frontPath     = "assets/generated/trainer_card/red.png", -- front sprite used in intro/card/HoF (side=front)
    trueColor     = false, -- false = participates in the game's GB/GBC palette pipeline
    paletteSource = "SPRITE_RED", -- palette reference for overworld sprite registration
    starterSpecies = nil,
  },
  {
    id            = "GIOVANNI",
    label         = "GIOVANNI",
    walkId        = "MOD_PSS_SPRITE_GIOVANNI",
    walkImage     = "assets/generated/sprites/giovanni.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/giovanni_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/giovanni.png",  -- Sprite used when battling against him
    trueColor     = false,
    paletteSource = "SPRITE_GIOVANNI",
    mirrorBack    = true, -- Trainer sprites face left; flip to face right as player back
    starterSpecies = "RHYHORN",
  },
  {
    id            = "BROCK",
    label         = "BROCK",
    walkId        = "MOD_PSS_SPRITE_BROCK",
    walkImage     = "assets/generated/sprites/brock.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/brock_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/brock.png",
    trueColor     = false,
    paletteSource = "SPRITE_BROCK",
    mirrorBack    = true,
    starterSpecies = "GEODUDE",
  },
  {
    id            = "MISTY",
    label         = "MISTY",
    walkId        = "MOD_PSS_SPRITE_MISTY",
    walkImage     = "assets/generated/sprites/misty.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/misty_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/misty.png",
    trueColor     = false,
    paletteSource = "SPRITE_MISTY",
    mirrorBack    = true,
    starterSpecies = "STARYU",
  },
  {
    id            = "LT_SURGE",
    label         = "LT. SURGE",
    walkId        = "MOD_PSS_SPRITE_LT_SURGE",
    walkImage     = "assets/generated/sprites/rocker.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/lt_surge_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/lt.surge.png",
    trueColor     = false,
    paletteSource = "SPRITE_LT_SURGE",
    mirrorBack    = true,
    starterSpecies = "VOLTORB",
  },
  {
    id            = "ERIKA",
    label         = "ERIKA",
    walkId        = "MOD_PSS_SPRITE_ERIKA",
    walkImage     = "assets/generated/sprites/erika.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/erika_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/erika.png",
    trueColor     = false,
    paletteSource = "SPRITE_ERIKA",
    mirrorBack    = true,
    starterSpecies = "ODDISH",
  },
  {
    id            = "KOGA",
    label         = "KOGA",
    walkId        = "MOD_PSS_SPRITE_KOGA",
    walkImage     = "assets/generated/sprites/koga.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/koga_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/koga.png",
    trueColor     = false,
    paletteSource = "SPRITE_KOGA",
    mirrorBack    = true,
    starterSpecies = "KOFFING",
  },
  {
    id            = "SABRINA",
    label         = "SABRINA",
    walkId        = "MOD_PSS_SPRITE_SABRINA",
    walkImage     = "assets/generated/sprites/sabrina.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/sabrina_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/sabrina.png",
    trueColor     = false,
    paletteSource = "SPRITE_SABRINA",
    mirrorBack    = true,
    starterSpecies = "ABRA",
  },
  {
    id            = "BLAINE",
    label         = "BLAINE",
    walkId        = "MOD_PSS_SPRITE_BLAINE",
    walkImage     = "assets/generated/sprites/blaine.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/blaine_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/blaine.png",
    trueColor     = false,
    paletteSource = "SPRITE_BLAINE",
    mirrorBack    = true,
    starterSpecies = "GROWLITHE",
  },
  {
    id            = "LORELEI",
    label         = "LORELEI",
    walkId        = "MOD_PSS_SPRITE_LORELEI",
    walkImage     = "assets/generated/sprites/lorelei.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/lorelei_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/lorelei.png",
    trueColor     = false,
    paletteSource = "SPRITE_LORELEI",
    mirrorBack    = true,
    starterSpecies = "SEEL",
  },
  {
    id            = "BRUNO",
    label         = "BRUNO",
    walkId        = "MOD_PSS_SPRITE_BRUNO",
    walkImage     = "assets/generated/sprites/bruno.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/bruno_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/bruno.png",
    trueColor     = false,
    paletteSource = "SPRITE_BRUNO",
    mirrorBack    = true,
    starterSpecies = "MACHOP",
  },
  {
    id            = "AGATHA",
    label         = "AGATHA",
    walkId        = "MOD_PSS_SPRITE_AGATHA",
    walkImage     = "assets/generated/sprites/agatha.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/agatha_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/agatha.png",
    trueColor     = false,
    paletteSource = "SPRITE_AGATHA",
    mirrorBack    = true,
    starterSpecies = "GASTLY",
  },
  {
    id            = "LANCE",
    label         = "LANCE",
    walkId        = "MOD_PSS_SPRITE_LANCE",
    walkImage     = "assets/generated/sprites/lance.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/lance_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/lance.png",
    trueColor     = false,
    paletteSource = "SPRITE_LANCE",
    mirrorBack    = true,
    starterSpecies = "DRATINI",
  },
  {
    id            = "BLUE",
    label         = "BLUE",
    walkId        = "MOD_PSS_SPRITE_BLUE",
    walkImage     = "assets/generated/sprites/blue.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/blue_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/rival3.png",  -- Late-rival trainer sprite (Champion)
    -- rival-specific portraits per encounter; each maps to the correct rival sprite:
    --   OPP_RIVAL1 = early game (Oak's Lab, Cerulean, Route 22 pre-League) -> rival1.png
    --   OPP_RIVAL2 = mid game (SS Anne, Lavender, Silph Co., Route 22) -> rival2.png
    --   OPP_RIVAL3 = Champion battle -> rival3.png (same as frontPath)
    rivalFrontPaths = {
      [1] = "assets/generated/battle/trainers/rival1.png",
      [2] = "assets/generated/battle/trainers/rival2.png",
      [3] = "assets/generated/battle/trainers/rival3.png",
    },
    trueColor     = false,
    paletteSource = "SPRITE_BLUE",
    mirrorBack    = true,
    starterSpecies = "EEVEE",
  },
  {
    id            = "JESSIE",
    label         = "JESSIE",
    walkId        = "MOD_PSS_SPRITE_JESSIE",
    walkImage     = "assets/generated/sprites/jessie.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/jessie_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/jessie_james.png",   -- Duo pic for battle intro
    trueColor     = false,
    paletteSource = "SPRITE_JESSIE",
    mirrorBack    = true,
    starterSpecies = "EKANS",
  },
  {
    id            = "JAMES",
    label         = "JAMES",
    walkId        = "MOD_PSS_SPRITE_JAMES",
    walkImage     = "assets/generated/sprites/james.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/player_back/james_back.png", -- Derived in transforms.lua
    frontPath     = "assets/generated/battle/trainers/jessie_james.png",  -- Duo pic for battle intro
    trueColor     = false,
    paletteSource = "SPRITE_JAMES",
    mirrorBack    = true,
    starterSpecies = "KOFFING",
  },
  {
    id            = "OAK",
    label         = "OAK",
    walkId        = "MOD_PSS_SPRITE_OAK",
    walkImage     = "assets/generated/sprites/oak.png",
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/profoakb.png",
    frontPath     = "assets/generated/battle/trainers/prof.oak.png",  -- Duo pic for battle intro
    trueColor     = false,
    paletteSource = "SPRITE_OAK",
    mirrorBack    = true,
    starterSpecies = "MEW",
  },
  {
    -- Pikachu: Yellow-only follower character. SPRITE_PIKACHU lives in the Yellow ROM
    -- cache (game.data.sprites.SPRITE_PIKACHU); shouldSpawn in PikachuFollower.lua
    -- guards against non-Yellow ROMs, so this entry is silently ignored on Red/Blue.
    -- No walkImage: the engine's vanilla SPRITE_PIKACHU sheet is used directly.
    -- backPath/frontPath use the Pokémon battle pic paths (battle/back/ and
    -- battle/front/), not trainer paths — RomExtractor writes them from the
    -- compressed Pokémon pic data (extractPokemon spriteFront/spriteBack fields).
    -- mirrorBack: false — the Pokémon back pic already faces the correct direction.
    id            = "PIKACHU",
    label         = "PIKACHU",
    walkId        = "MOD_PSS_SPRITE_PIKACHU",
    walkImage     = nil,           -- uses SPRITE_PIKACHU from the engine cache directly
    walkFallback  = "assets/generated/sprites/red.png",
    backPath      = "assets/generated/battle/back/pikachub.png",   -- Pokémon back pic used in battle
    frontPath     = "assets/generated/battle/front/pikachu.png",  -- Pokémon front pic for intro/card/HoF
    trueColor     = false,
    paletteSource = "SPRITE_PIKACHU",
    mirrorBack    = false,
    starterSpecies = nil,
  },
}
