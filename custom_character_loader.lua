-- custom_character_loader.lua
-- Scans the custom_characters/ subdirectory inside the mod folder, validates
-- each subfolder, reads its config.json, and injects valid character records
-- into the Characters table before CharacterSwap.init is called.
--
-- No global state. All logic flows through the mod system APIs.
-- Never calls bare error() or assert() inside event callbacks.

local CustomCharacterLoader = {}

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
  -- Attempt to acquire a JSON decoder from the environment.
  local json
  local ok, result = pcall(require, "json")
  if ok and result then
    json = result
  elseif type(_G.json) == "table" then
    -- Some environments expose json as a global (dkjson, etc.).
    json = _G.json
  end

  if not json or not json.decode then
    -- No parser available; treat as if config.json were absent (use defaults).
    -- Caller receives nil + error so it can apply the "absent config" path
    -- (defaults) instead of the "parse error" path (skip subfolder).
    return nil, "json_unavailable"
  end

  -- Decode the raw JSON source inside a pcall to catch malformed input.
  local decodeOk, decoded = pcall(json.decode, src)
  if not decodeOk or type(decoded) ~= "table" then
    return nil, "json_parse_error: " .. tostring(decoded)
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

  -- starterSpecies: integer >= 1, optional; nil if absent or invalid.
  if decoded.starterSpecies ~= nil then
    local ss = decoded.starterSpecies
    -- math.type is LuaJIT/5.3+; guard with a floor comparison for 5.1.
    local isInt = (type(ss) == "number") and (math.floor(ss) == ss)
    if isInt and ss >= 1 then
      config.starterSpecies = ss
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
            "custom_characters/%s: config.json 'starterSpecies' is not a valid integer >= 1 — set to nil",
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

    -- Custom characters always use their PNG directly (no GBC palette pipeline).
    -- paletteSource is always nil for custom chars, so trueColor is forced true
    -- regardless of the config.json value — the user's PNG colors are used as-is.
    local trueColor = true

    -- Build the character record (mirrors the structure used in characters.lua).
    local record = {
      id             = characterId,
      label          = config.label,
      walkId         = walkId,
      walkImage      = customDir .. "/" .. item .. "/walk.png",
      backPath       = customDir .. "/" .. item .. "/back.png",
      frontPath      = customDir .. "/" .. item .. "/front.png",
      mirrorBack     = config.mirrorBack,
      trueColor      = trueColor,
      starterSpecies = config.starterSpecies,
      paletteSource  = nil,
    }

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
