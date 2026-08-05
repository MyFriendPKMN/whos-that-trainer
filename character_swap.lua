-- character_swap.lua
-- Main Who's That Trainer? module: registers playable character sprites,
-- manages persisted selection, applies the overworld sprite, and exposes
-- back/front hooks for battle and trainer card.
-- All state is module-local - no global leakage.

local CharacterSwap = {}

-- indexed by character id ("RED", "GIOVANNI", "BROCK", ...)
local BACK_PATH_BY_ID   = {}
local FRONT_PATH_BY_ID  = {}   -- trainer card / battle intro / HoF front pic
local WALK_IMAGE_BY_ID  = {}   -- fallback: walk sprite used as back/front when no dedicated path
local WALK_ID_BY_ID     = {}
-- reverse lookup: walkId -> character id (used by selection screen onChoose)
local ID_BY_WALK_ID     = {}
-- char.paletteSource indexed by char.id; used by _applyOverworldSprite fallback
local PALETTE_SOURCE_BY_ID = {}
local BIKE_PATH_BY_ID   = {}   -- optional bike.png path; nil means use engine default
local TRUECOLOR_BY_ID   = {}   -- true only for characters whose sprites bypass the palette pipeline
local FISH_PATHS_BY_ID  = {}   -- optional { down, up, left } fishing pose tile paths per character
local KNOWN_ID          = {}
local AVAILABLE_ID      = {}
local PALETTE_FALLBACK_BY_ID = {
  -- Yellow cache can include Koga walk art without a matching SPRITE_KOGA
  -- entry in data.sprites; use Giovanni's trainer source as palette fallback.
  KOGA = "SPRITE_GIOVANNI",
}

local DEFAULT_ID = "RED"
local PSS_PREFIX = "MOD_PSS_"

local function validId(id)
  return type(id) == "string" and KNOWN_ID[id] == true
end

local function selectableId(id)
  return validId(id) and AVAILABLE_ID[id] == true
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
  -- Mod option is the source of truth; save state is kept in sync for runtime reads.
  local fromOptions = mod.options:get("character")
  local fromSave = mod.save:get("selected_character")
  local chosen = selectableId(fromOptions) and fromOptions
              or (selectableId(fromSave) and fromSave)
              or DEFAULT_ID
  if fromSave ~= chosen then
    mod.save:set("selected_character", chosen)
  end
  return chosen
end

-- ---- registration

function CharacterSwap.init(mod, characters)
  local dataSprites = nil
  pcall(function()
    dataSprites = require("src.core.Data").sprites
  end)

  local function resolvePaletteSource(char)
    local source = char.paletteSource
    if type(source) ~= "string" or source == "" then return nil end
    -- Already in ROM source-pointer format expected by PaletteFX.spriteObp.
    if source:find("SpriteSheetPointerTable[", 1, true)
       or source:find("RedBikeSprite", 1, true) then
      return source
    end
    -- Symbolic sprite id -> resolve to vanilla spriteDef.source.
    local def = dataSprites and dataSprites[source]
    if def and type(def.source) == "string" and def.source ~= "" then
      return def.source
    end
    -- Per-character fallback when no direct symbolic id exists.
    local fallbackId = PALETTE_FALLBACK_BY_ID[char.id]
    local fallback = fallbackId and dataSprites and dataSprites[fallbackId]
    if fallback and type(fallback.source) == "string" and fallback.source ~= "" then
      return fallback.source
    end
    -- paletteSource was set but could not be resolved to any ROM pointer.
    mod.log:warn("character %s: paletteSource %q could not be resolved — sprite will use default palette",
                 char.id, tostring(source))
    return nil
  end

  -- 1. Register sprite defs IMMEDIATELY (before content freeze)
  for _, char in ipairs(characters) do
    AVAILABLE_ID[char.id]          = false
    -- keep logical character metadata even if sprite registration fails
    KNOWN_ID[char.id]              = true
    BACK_PATH_BY_ID[char.id]       = char.backPath
    FRONT_PATH_BY_ID[char.id]      = char.frontPath
    WALK_IMAGE_BY_ID[char.id]      = char.walkImage
    WALK_ID_BY_ID[char.id]         = char.walkId
    ID_BY_WALK_ID[char.walkId]     = char.id
    PALETTE_SOURCE_BY_ID[char.id]  = char.paletteSource
    BIKE_PATH_BY_ID[char.id]       = char.bikePath
    TRUECOLOR_BY_ID[char.id]       = char.trueColor and true or false
    FISH_PATHS_BY_ID[char.id]      = char.fishPaths or nil

    -- validate required fields
    local walkOk = char.walkImage == nil or
                   (type(char.walkImage) == "string" and char.walkImage ~= "")
    if not walkOk then
      mod.log:error("character %s: walkImage must be a non-empty string or nil",
                    char.id)
      goto continue
    end
    local walkFallbackOk = char.walkFallback == nil or
                           (type(char.walkFallback) == "string" and char.walkFallback ~= "")
    if not walkFallbackOk then
      mod.log:error("character %s: walkFallback must be a non-empty string or nil",
                    char.id)
      goto continue
    end
    -- backPath is optional: nil means no dedicated back sprite (falls back to vanilla RED)
    local backOk = char.backPath == nil or
                   (type(char.backPath) == "string" and char.backPath ~= "")
    if not backOk then
      mod.log:error("character %s: backPath must be a non-empty string or nil",
                    char.id)
      goto continue
    end
    local walkImage = char.walkImage
    if walkImage and not assetExists(walkImage) then
      if char.walkFallback and assetExists(char.walkFallback) then
        -- Some ROM sets do not expose every leader/trainer walk sprite.
        -- Keep the character selectable by falling back to RED in overworld.
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
          image  = walkImage,
          frames = 6,
          walker = true,
          trueColor   = char.trueColor or false,
          -- Keep both fields for compatibility; PaletteFX reads paletteSource
          -- first and expects a ROM source-pointer shape.
          paletteSource = paletteSource,
          source = paletteSource,
        })
      else
        -- walkImage == nil: character relies on a vanilla engine sprite def.
        -- RED uses FieldDefaults and needs no check. Any other character
        -- (e.g. PIKACHU) requires its paletteSource sprite to exist in the
        -- engine cache — if it does not (e.g. Red/Blue ROM for Pikachu),
        -- raise an error so the surrounding pcall marks the character unavailable.
        if char.id ~= DEFAULT_ID then
          local vanillaId = char.paletteSource
          if not (vanillaId and dataSprites and dataSprites[vanillaId]) then
            mod.log:warn("character %s: vanilla sprite %q not found in engine cache — character unavailable",
                         char.id, tostring(vanillaId))
            error("vanilla sprite not found")
          end
        end
      end
    end)
    if not ok then
      -- Suppress redundant log for the "vanilla sprite not found" sentinel —
      -- the specific warning was already emitted inside the pcall above.
      if not tostring(err):find("vanilla sprite not found", 1, true) then
        mod.log:warn("character %s: sprites:register failed (%s) — skipped",
                     char.id, tostring(err))
      end
      goto continue
    end
    AVAILABLE_ID[char.id] = true
    ::continue::
  end

  -- Inject the custom player portrait into the Oak intro speech.
  -- OakSpeech.new() captures playerPic via Sprites.playerPath at construction
  -- time, before game.ready fires. intro.oak_speech.started fires after
  -- buildSteps() but before the first frame, giving a safe window to replace
  -- speech.playerPic and speech.playerTrueColor.
  -- The player.sprite hook already handles this path via Sprites.playerPath,
  -- but OakSpeech caches the result in self.playerPic at construction.
  -- Overwriting it here keeps the intro in sync with the selected character.
  mod.events:on("intro.oak_speech.started", function(ev)
    local speech = ev and ev.speech
    if not speech then return end
    local id = CharacterSwap._resolveSelectedId(mod)
    if id == DEFAULT_ID then return end
    -- Reuse the same hook seam: call Sprites.playerPath which will invoke
    -- our player.sprite hook and return the correct path for this character.
    local ok, Sprites = pcall(require, "src.pokemon.Sprites")
    if not ok then return end
    local game = speech.game
    local path, trueColor = Sprites.playerPath(game.data, "front", { kind = "intro" })
    if not path then return end
    local Assets = require("src.render.Assets")
    local resolved = Assets.resolve and Assets.resolve(path) or path
    local imgOk, img = pcall(love.graphics.newImage, resolved)
    if imgOk and img then
      speech.playerPic      = img
      speech.playerTrueColor = trueColor and true or false
    else
      mod.log:warn("intro player pic load failed for %s: %s", id, tostring(img))
    end
  end)

  -- 2. Initialize default selection on game.ready
  mod.events:on("game.ready", function()
    local chosen = CharacterSwap._resolveSelectedId(mod)
    if chosen == (mod.options:get("character")) then
      mod.log:info("Using character from options: %s", chosen)
    elseif chosen == DEFAULT_ID then
      mod.log:info("Using default character: %s", DEFAULT_ID)
    else
      mod.log:info("Using character from save: %s", chosen)
    end
  end)

  -- Continue/load can replace mod.save buckets after game.ready.
  mod.events:on("save.loaded", function()
    local chosen = CharacterSwap._resolveSelectedId(mod)
    mod.log:info("save.loaded sync selected_character=%s", chosen)
    local world = mod.world
    local ow = world and world.overworld and world:overworld() or nil
    if ow and ow.player then
      CharacterSwap._applyOverworldSprite(mod, ow, mod.path)
      mod.log:info("save.loaded reapplied overworld sprite for %s", chosen)
    end
  end)

  -- 3. battle back/front sprite hook (live, per battle init / trainer card / HoF)
  -- Back fallback chain:  dedicated backPath → next() (RED vanilla)
  -- Front fallback chain: dedicated frontPath → walkImage → next() (RED vanilla)
  mod.hooks:wrap("player.sprite", function(next, path, ctx)
    -- Demo battles (old man catch tutorial, Prof. Oak's Pallet intro) must
    -- show the old man / Oak back pic, not the player's custom sprite.
    -- ctx.demo == true  → old man (BATTLE_TYPE_OLD_MAN)
    -- ctx.oakDemo == true → Prof. Oak (BATTLE_TYPE_PIKACHU, Yellow only)
    if ctx.demo or ctx.oakDemo then
      return next(path, ctx)
    end
    local id = CharacterSwap._resolveSelectedId(mod)
    if ctx.side == "back" then
      -- 1st: dedicated back sprite (derived by transforms.lua for all non-RED characters)
      local bp = BACK_PATH_BY_ID[id]
      if bp and assetExists(bp) then
        if TRUECOLOR_BY_ID[id] then ctx.trueColor = true end
        return bp
      elseif bp then
        mod.log:warn("player.sprite: backPath %q not found for %q — falling back to vanilla RED",
                     tostring(bp), tostring(id))
      end
      -- Characters without a dedicated back sprite keep vanilla RED back.
      -- Using front/walk assets here creates oversized or malformed back pics.
      return next(path, ctx)
    elseif ctx.side == "front" then
      -- 1st: dedicated front pic (e.g. GIOVANNI, BROCK, BLUE)
      local fp = FRONT_PATH_BY_ID[id]
      if fp then
        if TRUECOLOR_BY_ID[id] then ctx.trueColor = true end
        return fp
      end
      -- 2nd: walk sprite as front fallback (e.g. MISTY, LT_SURGE, ...)
      local wp = WALK_IMAGE_BY_ID[id]
      if wp then return wp end
      -- 3rd: vanilla RED front pic via next()
      return next(path, ctx)
    end
    return next(path, ctx)
  end)

  -- 4. overworld sprite swap on map load
  mod.events:on("map.entered", function(ev)
    local ok, Game = pcall(require, "src.core.Game")
    local ow = ok and Game and Game.overworld
    if not (ow and ow.player) then return end
    CharacterSwap._applyOverworldSprite(mod, ow, mod.path)
  end)

  -- 5. mod options — choice list driven by built-in characters
  -- Não chama mod.options:define aqui: main.lua acumula os schemas de
  -- CharacterSwap e RivalSwap e faz uma única chamada combinada para evitar
  -- que a segunda chamada sobrescreva a primeira (define substitui, não acumula).
  local optionSchema = {
    {
      key     = "character",
      label   = "CHARACTER",
      type    = "choice",
      default = DEFAULT_ID,
      choices = CharacterSwap._buildChoices(characters),
    },
  }

  -- 6. character selection screen (sorted, with active marker)
  -- Wired to the start menu via ui.start_menu.items event.
  local SCREEN = PSS_PREFIX .. "SELECT"
  mod.content.screens:register(SCREEN, {
    new = function(game)
      local active = CharacterSwap._resolveSelectedId(mod)
      local activeWalkId = WALK_ID_BY_ID[active] or ""

      -- Build rows from the known character registry (not from sprites:each(),
      -- which would iterate all registered sprites and include unrelated ones).
      local rows = {}
      for id, wid in pairs(WALK_ID_BY_ID) do
        if AVAILABLE_ID[id] then
          local label = id  -- human-readable: "GIOVANNI", "BROCK", etc.
          rows[#rows + 1] = { label = label, charId = id, walkId = wid }
        end
      end
      table.sort(rows, function(a, b) return a.label < b.label end)

      local items = {}
      for _, row in ipairs(rows) do
        local marker = row.walkId == activeWalkId and ">" or " "
        items[#items + 1] = {
          label  = marker .. " " .. row.label,
          charId = row.charId,
          right  = row.walkId == activeWalkId and "*" or "",
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

  -- Wire the selection screen to the start menu.
  mod.events:on("ui.start_menu.items", function(ev)
    ev.items[#ev.items + 1] = {
      label  = "CHARACTER",
      action = function(game) game.screens:push(SCREEN) end,
    }
  end)

  -- Retorna o schema de opções para que main.lua possa combiná-lo com o de
  -- rival_swap antes de chamar mod.options:define uma única vez.
  return optionSchema
end

-- swap the active character, persist both save and options, and update live overworld sprite
function CharacterSwap._applySelection(mod, game, id)
  if not selectableId(id) then
    mod.log:warn("_applySelection: unavailable character id %q", tostring(id))
    return
  end
  local wid = WALK_ID_BY_ID[id]
  if not wid then
    mod.log:warn("_applySelection: unknown character id %q", tostring(id))
    return
  end
  -- Persist in both stores so _resolveSelectedId reads a consistent state
  -- regardless of which source it checks first.
  mod.save:set("selected_character", id)
  mod.options:set("character", id)
  local ow = game and game.overworld
  if ow and ow.player then
    CharacterSwap._applyOverworldSprite(mod, ow, mod.path)
  end
end

-- rebuild ow.player.sprite from the currently saved character
function CharacterSwap._applyOverworldSprite(mod, ow, modPath)
  local id = CharacterSwap._resolveSelectedId(mod)

  -- RED uses the engine's vanilla sprite; no custom def was registered.
  if id == "RED" then return end

  local wid = WALK_ID_BY_ID[id]
  if not wid then
    mod.log:warn("_applyOverworldSprite: %q not in registry — reverting to RED",
                 tostring(id))
    mod.save:set("selected_character", "RED")
    mod.options:set("character", "RED")
    return
  end
  -- use mod.content.sprites:get() to retrieve the sprite definition.
  -- For characters with walkImage=nil (e.g. PIKACHU), no mod sprite was
  -- registered; fall back to data.sprites[paletteSource] from the engine cache.
  local def = mod.content.sprites:get(wid)
  if not def then
    -- Attempt engine cache fallback for vanilla-sprite characters.
    local vanillaId = PALETTE_SOURCE_BY_ID[id]
    if vanillaId then
      local ok2, data = pcall(require, "src.core.Data")
      def = ok2 and data and data.sprites and data.sprites[vanillaId] or nil
    end
    if not def then
      mod.log:error("_applyOverworldSprite: sprite def %q missing from registry and engine cache",
                    wid)
      mod.save:set("selected_character", "RED")
      mod.options:set("character", "RED")
      return
    end
  end
  -- Create new SpriteRenderer instance using the mod's path.
  -- Requires engine_internals permission declared in manifest.json.
  local ok, result = pcall(function()
    local SpriteRenderer = require("src.render.SpriteRenderer")
    return SpriteRenderer.new(def, "player")
  end)
  if not ok then
    mod.log:error("_applyOverworldSprite: failed to create sprite: %s",
                  tostring(result))
    mod.save:set("selected_character", "RED")
    mod.options:set("character", "RED")
    return
  end
  ow.player.sprite = result

  -- Update fishing pose tiles; restore engine default when the character has none.
  local fishPaths = FISH_PATHS_BY_ID[id]
  local defaultFishTiles = (function()
    local ok, Data = pcall(require, "src.core.Data")
    local fx = ok and Data and Data.field and Data.field.overworldFx
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
      right = fishPaths.right or fishPaths.left or (defaultFishTiles and defaultFishTiles.right),
    }
  else
    ow.player.fishTiles = defaultFishTiles
  end

  -- Replace the bike sprite if this character has a custom bike.png.
  -- If bikePath is nil, leave ow.player.bikeSprite untouched so the engine
  -- falls back to its default SPRITE_RED_BIKE sheet.
  local bikePath = BIKE_PATH_BY_ID[id]
  if bikePath and assetExists(bikePath) then
    local bikeOk, bikeResult = pcall(function()
      local SpriteRenderer = require("src.render.SpriteRenderer")
      return SpriteRenderer.new({
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
    -- Path was registered but file no longer exists (e.g. user deleted it).
    mod.log:warn("_applyOverworldSprite: bikePath %q not found for %q — using default bike sprite",
                 bikePath, id)
  end
end

function CharacterSwap._buildChoices(characters)
  local choices = {}
  for _, char in ipairs(characters) do
    if AVAILABLE_ID[char.id] == true then
      choices[#choices + 1] = { char.label, char.id }
    end
  end
  table.sort(choices, function(a, b) return a[2] < b[2] end)
  return choices
end

-- Expõe AVAILABLE_ID para compartilhamento com rival_swap.lua (sem duplicar dados)
CharacterSwap.AVAILABLE_ID = AVAILABLE_ID

return CharacterSwap
