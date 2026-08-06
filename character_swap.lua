-- character_swap.lua
-- Main Who's That Trainer? module: registers playable character sprites,
-- manages persisted selection, applies the overworld sprite, and exposes
-- back/front hooks for battle and trainer card.
-- All state is module-local - no global leakage.
--
-- "DEFAULT" is the no-op sentinel: when selected, all sprite overrides
-- (overworld, battle back/front, Oak intro) are skipped and the engine
-- renders the vanilla RED sprite, exactly like follower_swap's DEFAULT.

local CharacterSwap = {}

-- indexed by character id ("RED", "GIOVANNI", "BROCK", ...)
local BACK_PATH_BY_ID      = {}
local FRONT_PATH_BY_ID     = {}  -- trainer card / battle intro / HoF front pic
local WALK_IMAGE_BY_ID     = {}  -- walk sheet; nil = rely on vanilla engine sprite
local WALK_ID_BY_ID        = {}
local ID_BY_WALK_ID        = {}  -- reverse: walkId -> character id
local PALETTE_SOURCE_BY_ID = {}  -- used by _applyOverworldSprite fallback
local BIKE_PATH_BY_ID      = {}  -- nil = use engine default
local TRUECOLOR_BY_ID      = {}
local FISH_PATHS_BY_ID     = {}
local KNOWN_ID             = {}
local AVAILABLE_ID         = {}

local PALETTE_FALLBACK_BY_ID = {
  -- Yellow cache can include Koga walk art without a matching SPRITE_KOGA
  -- entry in data.sprites; use Giovanni's trainer source as palette fallback.
  KOGA = "SPRITE_GIOVANNI",
}

-- DEFAULT is the no-op sentinel; VANILLA_ID is the character that IS the
-- vanilla player (used as the revert target when a sprite can't be found).
local DEFAULT_ID = "DEFAULT"
local VANILLA_ID = "RED"
local PSS_PREFIX = "MOD_PSS_"

local function isDefault(id)
  return id == DEFAULT_ID or id == VANILLA_ID
end

local function selectableId(id)
  return type(id) == "string"
      and (id == DEFAULT_ID or id == VANILLA_ID or AVAILABLE_ID[id] == true)
end

local function assetExists(path)
  if type(path) ~= "string" or path == "" then return false end
  local fs = love and love.filesystem
  if not (fs and fs.getInfo) then return true end
  local ok, Assets = pcall(require, "src.render.Assets")
  if ok and Assets and Assets.resolve then
    local resolved = Assets.resolve(path)
    return resolved ~= nil and fs.getInfo(resolved) ~= nil
  end
  return fs.getInfo(path) ~= nil
end

function CharacterSwap._resolveSelectedId(mod)
  local fromOptions = mod.options:get("character")
  local fromSave    = mod.save:get("selected_character")
  local chosen = selectableId(fromOptions) and fromOptions
              or (selectableId(fromSave) and fromSave)
              or DEFAULT_ID
  if fromSave ~= chosen then
    mod.save:set("selected_character", chosen)
  end
  return chosen
end

-- ── registration ──────────────────────────────────────────────────────────────

function CharacterSwap.init(mod, characters)
  local dataSprites = nil
  pcall(function()
    dataSprites = require("src.core.Data").sprites
  end)

  local function resolvePaletteSource(char)
    local source = char.paletteSource
    if type(source) ~= "string" or source == "" then return nil end
    if source:find("SpriteSheetPointerTable[", 1, true)
       or source:find("RedBikeSprite", 1, true) then
      return source
    end
    local def = dataSprites and dataSprites[source]
    if def and type(def.source) == "string" and def.source ~= "" then
      return def.source
    end
    local fallbackId = PALETTE_FALLBACK_BY_ID[char.id]
    local fallback   = fallbackId and dataSprites and dataSprites[fallbackId]
    if fallback and type(fallback.source) == "string" and fallback.source ~= "" then
      return fallback.source
    end
    mod.log:warn("character %s: paletteSource %q could not be resolved — sprite will use default palette",
                 char.id, tostring(source))
    return nil
  end

  -- 1. Register sprite defs immediately (before content freeze).
  for _, char in ipairs(characters) do
    AVAILABLE_ID[char.id]         = false
    KNOWN_ID[char.id]             = true
    BACK_PATH_BY_ID[char.id]      = char.backPath
    FRONT_PATH_BY_ID[char.id]     = char.frontPath
    WALK_IMAGE_BY_ID[char.id]     = char.walkImage
    WALK_ID_BY_ID[char.id]        = char.walkId
    ID_BY_WALK_ID[char.walkId]    = char.id
    PALETTE_SOURCE_BY_ID[char.id] = char.paletteSource
    BIKE_PATH_BY_ID[char.id]      = char.bikePath
    TRUECOLOR_BY_ID[char.id]      = char.trueColor and true or false
    FISH_PATHS_BY_ID[char.id]     = char.fishPaths or nil

    local walkOk = char.walkImage == nil
                   or (type(char.walkImage) == "string" and char.walkImage ~= "")
    if not walkOk then
      mod.log:error("character %s: walkImage must be a non-empty string or nil", char.id)
      goto continue
    end
    local walkFallbackOk = char.walkFallback == nil
                           or (type(char.walkFallback) == "string" and char.walkFallback ~= "")
    if not walkFallbackOk then
      mod.log:error("character %s: walkFallback must be a non-empty string or nil", char.id)
      goto continue
    end
    local backOk = char.backPath == nil
                   or (type(char.backPath) == "string" and char.backPath ~= "")
    if not backOk then
      mod.log:error("character %s: backPath must be a non-empty string or nil", char.id)
      goto continue
    end

    local walkImage = char.walkImage
    if walkImage and not assetExists(walkImage) then
      if char.walkFallback and assetExists(char.walkFallback) then
        mod.log:warn("character %s: walkImage %q not found - using walkFallback %q",
                     char.id, tostring(walkImage), tostring(char.walkFallback))
        walkImage = char.walkFallback
      else
        mod.log:warn("character %s: walkImage %q not found - character unavailable",
                     char.id, tostring(walkImage))
        goto continue
      end
    end
    WALK_IMAGE_BY_ID[char.id] = walkImage

    local ok, err = pcall(function()
      if walkImage then
        local paletteSource = resolvePaletteSource(char)
        mod.content.sprites:register(char.walkId, {
          image         = walkImage,
          frames        = 6,
          walker        = true,
          trueColor     = char.trueColor or false,
          paletteSource = paletteSource,
          source        = paletteSource,
        })
      else
        -- walkImage == nil: no custom overworld sprite.
        -- Character is still available for battle/trainer card usage if it has
        -- frontPath or backPath (via player.sprite hook) or if it's purely config-based.
        -- Only RED (VANILLA_ID) requires no sprite resources.
        if char.id ~= VANILLA_ID then
          mod.log:info("character %s: no walkImage provided — will use vanilla RED overworld sprite",
                       char.id)
        end
      end
    end)
    if not ok then
      mod.log:warn("character %s: sprites:register failed (%s) — skipped",
                   char.id, tostring(err))
      goto continue
    end
    AVAILABLE_ID[char.id] = true
    ::continue::
  end

  -- 2. Oak intro speech: inject custom player portrait + shrink walk sheet.
  -- OakSpeech caches both at construction time (before game.ready fires).
  -- intro.oak_speech.started fires after buildSteps() but before the first
  -- frame, giving a safe window to overwrite them.
  -- Skip entirely when DEFAULT or VANILLA_ID is selected.
  mod.events:on("intro.oak_speech.started", function(ev)
    local speech = ev and ev.speech
    if not speech then return end
    local id = CharacterSwap._resolveSelectedId(mod)
    if isDefault(id) then return end

    local okS, Sprites = pcall(require, "src.pokemon.Sprites")
    if not okS then return end
    local game = speech.game

    -- Front portrait (frames 1-4 of the shrink sequence).
    local path, trueColor = Sprites.playerPath(game.data, "front", { kind = "intro" })
    if path then
      local Assets   = require("src.render.Assets")
      local resolved = Assets.resolve and Assets.resolve(path) or path
      local imgOk, img = pcall(love.graphics.newImage, resolved)
      if imgOk and img then
        speech.playerPic       = img
        speech.playerTrueColor = trueColor and true or false
      else
        mod.log:warn("intro player pic load failed for %s: %s", id, tostring(img))
      end
    end

    -- Walk sheet (frames 29-78: sprite shrinks into the overworld character).
    -- OakSpeech hardcodes SPRITE_RED; replace with this character's walk sheet.
    local walkId   = WALK_ID_BY_ID[id]
    local spriteDef = walkId and mod.content.sprites:get(walkId)
    local walkImage = (spriteDef and spriteDef.image) or WALK_IMAGE_BY_ID[id]
    if walkImage then
      local Assets   = require("src.render.Assets")
      local resolved = Assets.resolve and Assets.resolve(walkImage) or walkImage
      local sheetOk, sheet = pcall(love.graphics.newImage, resolved)
      if sheetOk and sheet then
        speech.walkSheet = sheet
        speech.walkQuad  = nil  -- force quad rebuild at new dimensions
      else
        mod.log:warn("intro walk sheet load failed for %s: %s", id, tostring(sheet))
      end
    end
  end)

  -- 3. game.ready: log active character.
  mod.events:on("game.ready", function()
    local chosen = CharacterSwap._resolveSelectedId(mod)
    mod.log:info("character_swap: active character = %s", chosen)
  end)

  -- 4. save.loaded: re-sync and reapply overworld sprite.
  mod.events:on("save.loaded", function()
    local chosen = CharacterSwap._resolveSelectedId(mod)
    mod.log:info("save.loaded sync selected_character=%s", chosen)
    local world = mod.world
    local ow    = world and world.overworld and world:overworld() or nil
    if ow and ow.player then
      CharacterSwap._applyOverworldSprite(mod, ow)
      mod.log:info("save.loaded reapplied overworld sprite for %s", chosen)
    end
  end)

  -- 5. player.sprite hook: back/front sprites for battle, trainer card, HoF.
  -- DEFAULT → pass through to next() for all branches (vanilla RED).
  -- Demo battles (old man, Prof. Oak) always pass through regardless.
  -- Characters with nil frontPath/backPath use vanilla RED sprites.
  mod.hooks:wrap("player.sprite", function(next, path, ctx)
    if ctx.demo or ctx.oakDemo then
      return next(path, ctx)
    end
    local id = CharacterSwap._resolveSelectedId(mod)
    if isDefault(id) then
      return next(path, ctx)
    end
    if ctx.side == "back" then
      local bp = BACK_PATH_BY_ID[id]
      if bp and assetExists(bp) then
        if TRUECOLOR_BY_ID[id] then ctx.trueColor = true end
        return bp
      end
      -- backPath is nil or asset not found; use vanilla RED back sprite.
      return next(path, ctx)
    elseif ctx.side == "front" then
      local fp = FRONT_PATH_BY_ID[id]
      if fp then
        if TRUECOLOR_BY_ID[id] then ctx.trueColor = true end
        return fp
      end
      -- frontPath is nil; try walkImage as fallback.
      local wp = WALK_IMAGE_BY_ID[id]
      if wp then return wp end
      -- No front or walk image; use vanilla RED front sprite.
      return next(path, ctx)
    end
    return next(path, ctx)
  end)

  -- 6. map.entered: overworld sprite swap.
  -- DEFAULT → skip; engine keeps RED sprite untouched.
  mod.events:on("map.entered", function(ev)
    local okG, Game = pcall(require, "src.core.Game")
    local ow = okG and Game and Game.overworld
    if not (ow and ow.player) then return end
    CharacterSwap._applyOverworldSprite(mod, ow)
  end)

  -- 7. Option schema (returned to main.lua for the combined define call).
  -- DEFAULT is pinned first so it is always visible at the top of the list.
  local optionSchema = {
    {
      key     = "character",
      label   = "CHARACTER",
      type    = "choice",
      default = DEFAULT_ID,
      choices = CharacterSwap._buildChoices(characters),
    },
  }

  -- 8. Character selection screen.
  local SCREEN = PSS_PREFIX .. "SELECT"
  mod.content.screens:register(SCREEN, {
    new = function(game)
      local active       = CharacterSwap._resolveSelectedId(mod)
      local activeWalkId = WALK_ID_BY_ID[active] or ""

      local rows = {}
      -- DEFAULT pinned first.
      rows[#rows + 1] = { label = "DEFAULT (vanilla)", charId = DEFAULT_ID, walkId = "" }
      for id, wid in pairs(WALK_ID_BY_ID) do
        if AVAILABLE_ID[id] then
          rows[#rows + 1] = { label = id, charId = id, walkId = wid }
        end
      end
      table.sort(rows, function(a, b)
        if a.charId == DEFAULT_ID then return true end
        if b.charId == DEFAULT_ID then return false end
        return a.label < b.label
      end)

      local items = {}
      for _, row in ipairs(rows) do
        local isActive = (row.charId == DEFAULT_ID and isDefault(active))
                      or (row.charId == active)
        items[#items + 1] = {
          label  = (isActive and ">" or " ") .. " " .. row.label,
          charId = row.charId,
          right  = isActive and "*" or "",
        }
      end
      if #items == 0 then
        items[#items + 1] = { label = "No characters available.", charId = nil }
      end

      return mod.ui.ListMenu.new(game, "CHARACTER", items, {
        pageJump = true,
        onChoose = function(item, menu)
          if not item.charId then menu:close(); return end
          CharacterSwap._applySelection(mod, game, item.charId)
          menu:close()
        end,
      })
    end,
  })

  mod.events:on("ui.start_menu.items", function(ev)
    ev.items[#ev.items + 1] = {
      label  = "CHARACTER",
      action = function(game) game.screens:push(SCREEN) end,
    }
  end)

  return optionSchema
end

-- ── apply selection ───────────────────────────────────────────────────────────

function CharacterSwap._applySelection(mod, game, id)
  if not selectableId(id) then
    mod.log:warn("_applySelection: unavailable character id %q", tostring(id))
    return
  end
  mod.save:set("selected_character", id)
  mod.options:set("character", id)
  local ow = game and game.overworld
  if ow and ow.player then
    CharacterSwap._applyOverworldSprite(mod, ow)
  end
end

-- ── overworld sprite application ──────────────────────────────────────────────

function CharacterSwap._applyOverworldSprite(mod, ow)
  local id = CharacterSwap._resolveSelectedId(mod)

  -- DEFAULT or VANILLA_ID: let the engine keep its own RED sprite.
  if isDefault(id) then return end

  local wid = WALK_ID_BY_ID[id]
  if not wid then
    mod.log:warn("_applyOverworldSprite: %q not in registry — reverting to DEFAULT",
                 tostring(id))
    mod.save:set("selected_character", DEFAULT_ID)
    mod.options:set("character", DEFAULT_ID)
    return
  end

  -- Resolve sprite def: mod registry first, engine cache fallback.
  local def = mod.content.sprites:get(wid)
  if not def then
    local vanillaId = PALETTE_SOURCE_BY_ID[id]
    if vanillaId then
      local ok2, data = pcall(require, "src.core.Data")
      def = ok2 and data and data.sprites and data.sprites[vanillaId] or nil
    end
    if not def then
      mod.log:error("_applyOverworldSprite: sprite def %q missing from registry and engine cache", wid)
      mod.save:set("selected_character", DEFAULT_ID)
      mod.options:set("character", DEFAULT_ID)
      return
    end
  end

  local ok, result = pcall(function()
    return require("src.render.SpriteRenderer").new(def, "player")
  end)
  if not ok then
    mod.log:error("_applyOverworldSprite: failed to create sprite: %s", tostring(result))
    mod.save:set("selected_character", DEFAULT_ID)
    mod.options:set("character", DEFAULT_ID)
    return
  end
  ow.player.sprite = result

  -- Fishing pose tiles.
  local fishPaths = FISH_PATHS_BY_ID[id]
  local defaultFishTiles = (function()
    local okD, Data = pcall(require, "src.core.Data")
    local fx = okD and Data and Data.field and Data.field.overworldFx
    if not fx then return nil end
    local function p(name) local d = fx[name]; return d and d.path or nil end
    local t = { down = p("redFishFront"), up = p("redFishBack") }
    t.left = p("redFishSide"); t.right = t.left
    return (t.down or t.up or t.left) and t or nil
  end)()
  if fishPaths then
    ow.player.fishTiles = {
      down  = fishPaths.down  or (defaultFishTiles and defaultFishTiles.down),
      up    = fishPaths.up    or (defaultFishTiles and defaultFishTiles.up),
      left  = fishPaths.left  or (defaultFishTiles and defaultFishTiles.left),
      right = fishPaths.right or fishPaths.left
              or (defaultFishTiles and defaultFishTiles.right),
    }
  else
    ow.player.fishTiles = defaultFishTiles
  end

  -- Bike sprite.
  local bikePath = BIKE_PATH_BY_ID[id]
  if bikePath and assetExists(bikePath) then
    local bikeOk, bikeResult = pcall(function()
      return require("src.render.SpriteRenderer").new({
        image     = bikePath,
        frames    = 6,
        walker    = true,
        trueColor = true,
        source    = nil,
      }, "player")
    end)
    if bikeOk then
      ow.player.bikeSprite = bikeResult
    else
      mod.log:warn("_applyOverworldSprite: failed to create bikeSprite for %q: %s",
                   id, tostring(bikeResult))
    end
  elseif bikePath then
    mod.log:warn("_applyOverworldSprite: bikePath %q not found for %q — using default bike sprite",
                 bikePath, id)
  end
end

-- ── helpers ───────────────────────────────────────────────────────────────────

function CharacterSwap._buildChoices(characters)
  -- DEFAULT pinned first; remaining entries sorted alphabetically by id.
  local choices = { { "DEFAULT (vanilla)", DEFAULT_ID } }
  for _, char in ipairs(characters) do
    if AVAILABLE_ID[char.id] == true then
      choices[#choices + 1] = { char.label, char.id }
    end
  end
  table.sort(choices, function(a, b)
    if a[2] == DEFAULT_ID then return true end
    if b[2] == DEFAULT_ID then return false end
    return a[2] < b[2]
  end)
  return choices
end

-- Exposed for sharing with rival_swap.lua and follower_swap.lua.
CharacterSwap.AVAILABLE_ID = AVAILABLE_ID

return CharacterSwap
