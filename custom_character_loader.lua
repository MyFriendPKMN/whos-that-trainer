-- custom_character_loader.lua
-- Scans the custom_characters/ subdirectory inside the mod folder, validates
-- each subfolder, reads its config.json, and injects valid character records
-- into the Characters table before CharacterSwap.init is called.
--
-- No global state. All logic flows through the mod system APIs.
-- Never calls bare error() or assert() inside event callbacks.

local CustomCharacterLoader = {}
local Json = require("src.link.Json")

-- Custom characters directory name, relative to the mod folder.
local CUSTOM_DIR = "custom_characters"

-- Required sprite filenames that must be present in every character subfolder.
local REQUIRED_SPRITES = { "walk.png", "front.png", "back.png" }

-- ---------------------------------------------------------------------------
-- Private helpers
-- ---------------------------------------------------------------------------

-- Builds a set {[id] = true} from the current Characters table.
-- Used for collision detection before inserting a new character.
--
-- @param Characters  The mutable character array from characters.lua
-- @return            A plain table usable as a set of known IDs
local function _buildExistingIds(Characters)
  local ids = {}
  for _, char in ipairs(Characters) do
    if type(char.id) == "string" then
      ids[char.id] = true
    end
  end
  return ids
end

-- Parses and normalizes a config.json source string.
-- Attempts json.decode inside a pcall; applies field-level defaults and
-- validation rules.
--
-- Returns: config, nil   on success
--          nil, errMsg   on JSON parse failure (callers should skip the subfolder)
--
-- @param src       Raw string contents of config.json
-- @param subfolder Subfolder name used as label fallback (e.g. "ash")
local function _parseConfig(src, subfolder)
  -- Use the project's JSON decoder so parsing works in all runtime targets.
  local decoded, decodeErr = Json.decode(src)
  if type(decoded) ~= "table" then
    return nil, "json_parse_error: " .. tostring(decodeErr or decoded)
  end

  local config = {}

  -- label: string, required; falls back to string.upper(subfolder) if absent/empty.
  local labelWarn = false
  if type(decoded.label) == "string" and decoded.label ~= "" then
    config.label = decoded.label
  else
    config.label = string.upper(subfolder)
    if decoded.label ~= nil then
      -- Present but invalid (empty string or wrong type).
      labelWarn = true
    end
    -- When decoded.label is nil the caller decides whether to log a warn
    -- (label absent vs config absent are distinct log levels per requirements).
    -- We signal this via a secondary flag in the config table.
  end
  config._labelWasDefaulted = (decoded.label == nil) or labelWarn
  config._labelWasInvalid   = labelWarn

  -- starterSpecies: non-empty string (Pokémon species name), optional.
  -- Normalized to uppercase to match the engine's species key convention.
  -- Examples: "GEODUDE", "STARYU", "ARBOK". Numbers are rejected.
  if decoded.starterSpecies ~= nil then
    local ss = decoded.starterSpecies
    if type(ss) == "string" and ss ~= "" then
      config.starterSpecies = string.upper(ss)
    else
      config.starterSpecies = nil
      config._starterSpeciesInvalid = true
    end
  else
    config.starterSpecies = nil
  end

  -- mirrorBack: boolean, default false.
  if type(decoded.mirrorBack) == "boolean" then
    config.mirrorBack = decoded.mirrorBack
  else
    config.mirrorBack = false
  end

  -- trueColor: boolean, default false.
  if type(decoded.trueColor) == "boolean" then
    config.trueColor = decoded.trueColor
  else
    config.trueColor = false
  end

  -- palette: optional string referencing a character id (e.g. "BROCK") or
  -- a sprite id (e.g. "SPRITE_BROCK"). When present, the character participates
  -- in the SGB/GBC palette pipeline (trueColor is overridden to false).
  -- The loader resolves this to paletteSource at record-build time.
  if decoded.palette ~= nil then
    local p = decoded.palette
    if type(p) == "string" and p ~= "" then
      config.palette = string.upper(p)
    else
      config.palette = nil
      config._paletteInvalid = true
    end
  else
    config.palette = nil
  end

    -- battleScale: number, default nil
  if type(decoded.battleScale) == "number" then
    config.battleScale = decoded.battleScale
  else
    config.battleScale = nil
  end

  return config, nil
end

-- Checks that all three required sprites exist inside the given subfolder.
-- Uses love.filesystem.getInfo; gracefully handles environments where LÖVE
-- is not available (always returns true in that case, e.g. headless tests).
--
-- Returns: true               if all sprites are present
--          false, missingList if one or more sprites are absent
--
-- @param subfolder  Subfolder name (e.g. "ash")
-- @param basePath   Absolute base path (e.g. the mod's custom_characters/ dir)
local function _validateSprites(subfolder, basePath)
  local fs = love and love.filesystem
  if not (fs and fs.getInfo) then
    -- Cannot verify; assume valid to avoid blocking headless environments.
    return true
  end

  local missing = {}
  for _, filename in ipairs(REQUIRED_SPRITES) do
    local path = basePath .. "/" .. subfolder .. "/" .. filename
    -- Wrap getInfo in pcall to handle unexpected filesystem errors gracefully.
    local ok, info = pcall(fs.getInfo, path)
    if not ok or not info then
      missing[#missing + 1] = filename
    end
  end

  if #missing == 0 then
    return true
  end
  return false, missing
end

-- ---------------------------------------------------------------------------
-- Stale save check
-- ---------------------------------------------------------------------------

-- After the boot scan, verify that any CUSTOM_ IDs persisted in mod.save
-- still correspond to registered characters. Resets stale entries to "RED".
--
-- @param mod         The mod context
-- @param existingIds Set of all currently registered Character_IDs
local function _checkStaleSaves(mod, existingIds)
  local saveKeys = {
    "selected_character",
    "selected_rival",
    "selected_follower",
  }
  for _, key in ipairs(saveKeys) do
    local id = mod.save:get(key)
    if type(id) == "string" and id:sub(1, 7) == "CUSTOM_" then
      if not existingIds[id] then
        mod.log:warn(
          "stale save: %s=%q is no longer in the character catalog — resetting to RED",
          key, id
        )
        mod.save:set(key, "RED")
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Core scan / inject logic
-- ---------------------------------------------------------------------------

-- Called inside the game.ready handler. Scans custom_characters/, validates
-- each subfolder, and injects valid character records into Characters.
--
-- @param mod         The mod context
-- @param Characters  The mutable character array from characters.lua
local function _scanAndInject(mod, Characters)
  local fs = love and love.filesystem

  -- Prefix with mod.path so love.filesystem resolves relative to the mod folder.
  -- On Windows this expands to e.g. "mods/whos_that_trainer/custom_characters".
  -- On Android/iOS/Linux the save dir differs, but mod.path is always correct.
  local customDir = mod.path .. "/" .. CUSTOM_DIR

  -- Check whether the directory exists at all.
  if fs and fs.getInfo then
    local ok, info = pcall(fs.getInfo, customDir, "directory")
    if not ok or not info then
      mod.log:info("custom_characters/ directory not found — no custom characters loaded")
      return
    end
  end

  -- Retrieve all items inside the directory.
  local items = {}
  if fs and fs.getDirectoryItems then
    local ok, result = pcall(fs.getDirectoryItems, customDir)
    if ok and type(result) == "table" then
      items = result
    else
      mod.log:warn("custom_characters/: could not list directory contents (%s)", tostring(result))
      return
    end
  end

  -- Snapshot existing IDs for collision detection.
  local existingIds = _buildExistingIds(Characters)

  for _, item in ipairs(items) do
    -- Only process direct subdirectories; skip loose files.
    local itemPath = customDir .. "/" .. item
    local isDir = false
    if fs and fs.getInfo then
      local ok, info = pcall(fs.getInfo, itemPath, "directory")
      isDir = ok and info ~= nil
    end
    if not isDir then
      -- Not a directory; skip silently.
      goto continue
    end

    -- Validate required sprites.
    local spritesOk, missingList = _validateSprites(item, customDir)
    if not spritesOk then
      mod.log:warn(
        "custom_characters/%s: missing required sprite(s): %s — skipped",
        item,
        table.concat(missingList, ", ")
      )
      goto continue
    end

    -- Derive the Character_ID.
    local characterId = "CUSTOM_" .. string.upper(item)

    -- Collision check.
    if existingIds[characterId] then
      mod.log:warn(
        "custom_characters/%s: Character_ID %q already exists in the catalog — skipped",
        item, characterId
      )
      goto continue
    end

    -- Attempt to read config.json.
    local configPath = CUSTOM_DIR .. "/" .. item .. "/config.json"
    local configSrc
    do
      local readOk, readResult = pcall(function() return mod:read(configPath) end)
      if readOk then
        configSrc = readResult  -- may be nil if file is absent
      else
        -- mod:read raised an error; treat as absent config (use defaults).
        mod.log:warn(
          "custom_characters/%s: error reading config.json (%s) — using defaults",
          item, tostring(readResult)
        )
        configSrc = nil
      end
    end

    local config
    if configSrc then
      -- config.json is present; try to parse it.
      local parsedConfig, parseErr = _parseConfig(configSrc, item)

      if parseErr == "json_unavailable" then
        -- No JSON parser: fall back to defaults and log info.
        mod.log:info(
          "custom_characters/%s: JSON parser unavailable — using defaults",
          item
        )
        config = {
          label         = string.upper(item),
          starterSpecies = nil,
          mirrorBack    = false,
          trueColor     = false,
        }
      elseif parsedConfig == nil then
        -- Genuine parse error: skip the subfolder.
        mod.log:warn(
          "custom_characters/%s: config.json parse error (%s) — skipped",
          item, tostring(parseErr)
        )
        goto continue
      else
        config = parsedConfig

        -- Emit per-field warnings for defaulted/invalid values.
        if config._labelWasInvalid then
          mod.log:warn(
            "custom_characters/%s: config.json 'label' field is invalid — using %q as default",
            item, config.label
          )
        end
        if config._starterSpeciesInvalid then
          mod.log:warn(
            "custom_characters/%s: config.json 'starterSpecies' must be a non-empty string (e.g. \"GEODUDE\") — set to nil",
            item
          )
        end
        if config._paletteInvalid then
          mod.log:warn(
            "custom_characters/%s: config.json 'palette' must be a non-empty string (e.g. \"BROCK\") — set to nil",
            item
          )
        end
      end
    else
      -- config.json is absent; use defaults.
      mod.log:info(
        "custom_characters/%s: config.json not found — using defaults (label=%q)",
        item, string.upper(item)
      )
      config = {
        label         = string.upper(item),
        starterSpecies = nil,
        mirrorBack    = false,
        trueColor     = false,
      }
    end

    -- Derive walkId: "MOD_PSS_SPRITE_CUSTOM_" .. string.upper(subfolder).
    -- Example: subfolder "ash" -> Character_ID "CUSTOM_ASH" -> walkId "MOD_PSS_SPRITE_CUSTOM_ASH".
    -- The design document data model example uses this shorter form (Req 3.2).
    local walkId = "MOD_PSS_SPRITE_CUSTOM_" .. string.upper(item)

    -- Resolve the palette reference to a paletteSource string.
    -- Accepts a character id ("BROCK") or a sprite id ("SPRITE_BROCK").
    -- When absent, trueColor stays true (raw PNG colors, no palette pipeline).
    local paletteSource = nil
    local trueColor = true
    if config.palette then
      -- Normalize: if the value doesn't already start with "SPRITE_", prepend it.
      -- "BROCK" -> "SPRITE_BROCK"; "SPRITE_BROCK" -> "SPRITE_BROCK" (unchanged).
      if config.palette:sub(1, 7) == "SPRITE_" then
        paletteSource = config.palette
      else
        paletteSource = "SPRITE_" .. config.palette
      end
      trueColor = false
      mod.log:info(
        "custom_characters/%s: using palette source %q (trueColor = false)",
        item, paletteSource
      )
    end

    -- Check for optional bike.png; nil means fall back to vanilla RED bike sprite.
    local bikePngPath = customDir .. "/" .. item .. "/bike.png"
    local bikePathValue = nil
    do
      local fs = love and love.filesystem
      if fs and fs.getInfo then
        local bikeOk, bikeInfo = pcall(fs.getInfo, bikePngPath)
        if bikeOk and bikeInfo then
          bikePathValue = bikePngPath
        end
      end
    end

    -- Check for optional fishing pose tiles; nil means fall back to RED's tiles.
    local fishPathsValue = nil
    do
      local fs = love and love.filesystem
      if fs and fs.getInfo then
        local function optPath(filename)
          local p = customDir .. "/" .. item .. "/" .. filename
          local ok, info = pcall(fs.getInfo, p)
          return (ok and info) and p or nil
        end
        local fd = optPath("fish_front.png")
        local fb = optPath("fish_back.png")
        local fs2 = optPath("fish_side.png")
        if fd or fb or fs2 then
          fishPathsValue = { down = fd, up = fb, left = fs2, right = fs2 }
        end
      end
    end

    -- Build the character record (mirrors the structure used in characters.lua).
    local record = {
      id             = characterId,
      label          = config.label,
      walkId         = walkId,
      walkImage      = customDir .. "/" .. item .. "/walk.png",
      backPath       = customDir .. "/" .. item .. "/back.png",
      frontPath      = customDir .. "/" .. item .. "/front.png",
      bikePath       = bikePathValue,
      fishPaths      = fishPathsValue,
      mirrorBack     = config.mirrorBack,
      trueColor      = trueColor,
      starterSpecies = config.starterSpecies,
      paletteSource  = paletteSource,
    }

    -- apply the battleScale configured if exists on JSON
    -- record.backPath is already the full relative path (e.g.
    -- "mods/whos-that-trainer/custom_characters/big_red/back.png");
    -- do NOT wrap it in mod.assets:path() which would prepend mod.path
    -- a second time and produce a path that never matches imageMeta.
    -- Use characterId as the registry key so multiple custom characters
    -- with battleScale don't collide on the same "hero_back" entry.
    if config.battleScale then
      mod.content.battle_sprite_scales:register(
        "hero_back_" .. characterId:lower(),
        {
          path  = record.backPath,
          scale = config.battleScale
        }
      )
    end

    -- Inject into the Characters table.
    Characters[#Characters + 1] = record

    -- Update the collision guard for subsequent iterations.
    existingIds[characterId] = true

    mod.log:info(
      "custom_characters/%s: registered as %q (label=%q)",
      item, characterId, config.label
    )

    ::continue::
  end

  -- Return the final id set so the caller can schedule the stale-save check
  -- once mod.save is actually populated (on save.loaded, not here).
  return existingIds
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- Scans custom_characters/ synchronously, validates each subfolder, and
-- injects valid character records into Characters immediately.
-- Must be called before CharacterSwap.init so the expanded list is visible
-- when CharacterSwap captures its WALK_ID_BY_ID / AVAILABLE_ID snapshots.
-- Schedules a stale-save check on save.loaded for deferred mod.save access.
--
-- @param mod        The mod context (mod.events, mod.log, mod:read, mod.save)
-- @param Characters The mutable character array from characters.lua
function CustomCharacterLoader.load(mod, Characters)
  -- Run the filesystem scan synchronously so Characters is fully populated
  -- before CharacterSwap.init() captures its WALK_ID_BY_ID / AVAILABLE_ID
  -- snapshots. love.filesystem is available at mod load time.
  local ok, result = pcall(_scanAndInject, mod, Characters)
  if not ok then
    mod.log:error(
      "custom_character_loader: unexpected error during boot scan: %s",
      tostring(result)
    )
    return
  end

  -- _scanAndInject returns the final existingIds set.
  -- Schedule the stale-save check for save.loaded, when mod.save is actually
  -- populated. Using save.loaded (not game.ready) handles both first boot and
  -- continue/load flows.
  local existingIds = result
  mod.events:on("save.loaded", function()
    local saveOk, saveErr = pcall(_checkStaleSaves, mod, existingIds)
    if not saveOk then
      mod.log:warn(
        "custom_character_loader: stale-save check failed: %s",
        tostring(saveErr)
      )
    end
  end)
end

return CustomCharacterLoader
