-- rival_swap.lua
-- Manages rival selection, persistence, and sprite substitution.
-- Depends on characters.lua and AVAILABLE_ID from character_swap.lua.
-- State is completely isolated from character_swap.lua.
--
-- "DEFAULT" is the no-op sentinel: when selected, all overworld NPC sprites,
-- battle trainer portraits and intro speech portraits are left untouched,
-- preserving vanilla engine behaviour exactly like follower_swap does.

local RivalSwap = {}

local RIVAL_DEFAULT_ID  = "DEFAULT"
local RIVAL_VANILLA_ID  = "BLUE"       -- the character that IS the vanilla rival
local PSS_PREFIX        = "MOD_PSS_"
local RIVAL_SPRITE_ID   = "SPRITE_BLUE"
local RIVAL_OPP_CLASSES = {
  OPP_RIVAL1 = true, OPP_RIVAL2 = true, OPP_RIVAL3 = true,
}

local FRONT_PATH_BY_ID = {}
local WALK_IMAGE_BY_ID = {}
local RIVAL_FRONT_PATHS_BY_ID = {}  -- rival-specific front sprites per encounter number

-- ── persistence ──────────────────────────────────────────────────────────────

function RivalSwap._resolveSelectedRival(mod, availableId)
  local fromOptions = mod.options:get("rival")
  local fromSave    = mod.save:get("selected_rival")
  local function valid(id)
    return type(id) == "string"
        and (id == RIVAL_DEFAULT_ID
             or id == RIVAL_VANILLA_ID
             or availableId[id] == true)
  end
  local chosen = (valid(fromOptions) and fromOptions)
              or (valid(fromSave)    and fromSave)
              or RIVAL_DEFAULT_ID
  if fromSave ~= chosen then
    local ok, err = pcall(mod.save.set, mod.save, "selected_rival", chosen)
    if not ok then
      mod.log:error("_resolveSelectedRival: save:set failed: %s", tostring(err))
    end
  end
  return chosen
end

-- ── sprite-def resolver ───────────────────────────────────────────────────────
-- Shared helper: given a character id, return the best available sprite
-- definition (mod registry first, vanilla data.sprites fallback).
-- Returns nil when nothing can be found.
function RivalSwap._resolveSpriteDef(mod, charId)
  -- Try the mod content registry first (registered walk sprites).
  local walkId = "MOD_PSS_SPRITE_" .. charId
  local def = mod.content.sprites:get(walkId)
  if def then return def end

  -- Fallback: vanilla sprite from engine data cache.
  local ok, data = pcall(require, "src.core.Data")
  if ok and data and data.sprites then
    return data.sprites["SPRITE_" .. charId]
  end
  return nil
end

-- ── trainer record patcher ───────────────────────────────────────────────────
-- Writes the pic and paletteSource directly into game.data.trainers at
-- runtime. mod.content.trainers:patch() only affects the boot-time merge and
-- is frozen after that point, so live battles would still read the vanilla pic.
-- Direct mutation of game.data.trainers is the same approach BattleState uses
-- to swap the rival's name (setmetatable overlay in newTrainer).
-- rivalId == RIVAL_DEFAULT_ID or RIVAL_VANILLA_ID → restore the original pic
-- from the generated data backup so vanilla Blue shows correctly.
local TRAINER_PIC_BACKUP = {}  -- original pic values saved before first mutation

local function _getGameData()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and Game and Game.data
end

local function _patchTrainerRecord(mod, oppClass, rivalId)
  local data = _getGameData()
  if not (data and data.trainers and data.trainers[oppClass]) then return end
  local record = data.trainers[oppClass]

  -- Save the original pic on first call so we can restore it for DEFAULT/BLUE.
  if TRAINER_PIC_BACKUP[oppClass] == nil then
    TRAINER_PIC_BACKUP[oppClass] = record.pic or false  -- false = was nil
  end

  if rivalId == RIVAL_DEFAULT_ID or rivalId == RIVAL_VANILLA_ID then
    -- Restore vanilla pic.
    local orig = TRAINER_PIC_BACKUP[oppClass]
    record.pic           = orig ~= false and orig or nil
    record.paletteSource = nil
  else
    -- Extract the rival encounter number from the oppClass name.
    -- OPP_RIVAL1 -> 1, OPP_RIVAL2 -> 2, OPP_RIVAL3 -> 3
    local rivalNum = tonumber(oppClass:match("OPP_RIVAL(%d)"))
    local frontPath = FRONT_PATH_BY_ID[rivalId]

    -- Use rival-specific front sprite if available, else fall back to frontPath.
    if rivalNum and rivalNum > 0 then
      local rivalSpecificPaths = RIVAL_FRONT_PATHS_BY_ID[rivalId]
      if rivalSpecificPaths and rivalSpecificPaths[rivalNum] then
        frontPath = rivalSpecificPaths[rivalNum]
      end
    end

    record.pic           = frontPath or nil
    record.paletteSource = "SPRITE_" .. rivalId
  end
end

local function _patchAllRivalTrainerRecords(mod, rivalId)
  for oppClass in pairs(RIVAL_OPP_CLASSES) do
    _patchTrainerRecord(mod, oppClass, rivalId)
  end
end

-- ── initialization ─────────────────────────────────────────────────────────────

function RivalSwap.init(mod, characters, availableId)
  -- Populate lookup tables from characters.lua data.
  for _, char in ipairs(characters) do
    FRONT_PATH_BY_ID[char.id] = char.frontPath
    WALK_IMAGE_BY_ID[char.id] = char.walkImage
    -- Store rival-specific front sprites if available (front-rival1.png, front-rival2.png, etc.)
    if char.rivalFrontPaths then
      RIVAL_FRONT_PATHS_BY_ID[char.id] = char.rivalFrontPaths
    end
  end

  -- Option schema: DEFAULT is pinned first, then all available characters.
  local optionSchema = {
    {
      key     = "rival",
      label   = "RIVAL",
      type    = "choice",
      default = RIVAL_DEFAULT_ID,
      choices = RivalSwap._buildChoices(characters, availableId),
    },
  }

  -- ── Oak intro speech: inject custom rival portrait ────────────────────────
  -- OakSpeech.new() captures rivalPic from trainers.OPP_RIVAL1.pic at
  -- construction time, before game.ready fires. intro.oak_speech.started
  -- fires after buildSteps() but before the first frame, allowing us to
  -- overwrite speech.rivalPic safely. Skip when DEFAULT is selected.
  mod.events:on("intro.oak_speech.started", function(ev)
    local speech = ev and ev.speech
    if not speech then return end
    local rivalId = RivalSwap._resolveSelectedRival(mod, availableId)
    if rivalId == RIVAL_DEFAULT_ID or rivalId == RIVAL_VANILLA_ID then return end
    -- Oak intro uses OPP_RIVAL1 (first encounter), so use rival-specific sprite [1] if available.
    local rivalSpecificPaths = RIVAL_FRONT_PATHS_BY_ID[rivalId]
    local frontPath = (rivalSpecificPaths and rivalSpecificPaths[1])
                   or FRONT_PATH_BY_ID[rivalId]
    if not frontPath then return end
    local Assets = require("src.render.Assets")
    local resolved = Assets.resolve and Assets.resolve(frontPath) or frontPath
    local ok, img = pcall(love.graphics.newImage, resolved)
    if ok and img then
      speech.rivalPic = img
    else
      mod.log:warn("intro rival pic load failed for %s: %s", rivalId, tostring(img))
    end
  end)

  -- ── game.ready: initial log + trainer record patch ────────────────────────
  mod.events:on("game.ready", function()
    local chosen = RivalSwap._resolveSelectedRival(mod, availableId)
    mod.log:info("rival_swap: active rival = %s", chosen)
    _patchAllRivalTrainerRecords(mod, chosen)
  end)

  -- ── save.loaded: sync + re-patch (mod.content merges reset on save swap) ──
  mod.events:on("save.loaded", function()
    local chosen = RivalSwap._resolveSelectedRival(mod, availableId)
    mod.log:info("save.loaded sync selected_rival=%s", chosen)
    _patchAllRivalTrainerRecords(mod, chosen)
    -- Re-apply overworld NPC sprites if the world is live.
    local game = mod.world and mod.world.game
    local ow = game and game.overworld
    if ow then
      RivalSwap._applyRivalNPCSprites(mod, ow, chosen)
      mod.log:info("save.loaded reapplied rival sprite for %s", chosen)
    end
  end)

  -- ── map.entered: overworld NPC sprite substitution ────────────────────────
  mod.events:on("map.entered", function(ev)
    local ok, Game = pcall(require, "src.core.Game")
    local ow = ok and Game and Game.overworld
    if not ow then return end
    local rivalId = RivalSwap._resolveSelectedRival(mod, availableId)
    -- DEFAULT = vanilla Blue; no sprite override needed.
    if rivalId == RIVAL_DEFAULT_ID then return end
    RivalSwap._applyRivalNPCSprites(mod, ow, rivalId)
  end)

  -- ── selection screen ────────────────────────────────────────────────────────
  local RIVAL_SCREEN = PSS_PREFIX .. "RIVAL_SELECT"
  mod.content.screens:register(RIVAL_SCREEN, {
    new = function(game)
      local active = RivalSwap._resolveSelectedRival(mod, availableId)
      local rows   = {}
      -- DEFAULT is always pinned first.
      rows[#rows + 1] = { label = "DEFAULT (vanilla)", charId = RIVAL_DEFAULT_ID }
      for _, char in ipairs(characters) do
        if availableId[char.id] == true or char.id == RIVAL_VANILLA_ID then
          rows[#rows + 1] = { label = char.label, charId = char.id }
        end
      end
      table.sort(rows, function(a, b)
        if a.charId == RIVAL_DEFAULT_ID then return true end
        if b.charId == RIVAL_DEFAULT_ID then return false end
        return a.label < b.label
      end)

      local items = {}
      for _, row in ipairs(rows) do
        local isActive = row.charId == active
        items[#items + 1] = {
          label  = (isActive and ">" or " ") .. " " .. row.label,
          charId = row.charId,
          right  = isActive and "*" or "",
        }
      end
      if #items == 0 then
        items[#items + 1] = { label = "DEFAULT (vanilla)", charId = RIVAL_DEFAULT_ID }
      end

      return mod.ui.ListMenu.new(game, "RIVAL", items, {
        pageJump = true,
        onChoose = function(item, menu)
          if not item.charId then menu:close(); return end
          RivalSwap._applyRivalSelection(mod, game, item.charId, availableId)
          menu:close()
        end,
      })
    end,
  })

  -- Inject "RIVAL" entry in start menu.
  mod.events:on("ui.start_menu.items", function(ev)
    ev.items[#ev.items + 1] = {
      label  = "RIVAL",
      action = function(game) game.screens:push(RIVAL_SCREEN) end,
    }
  end)

  return optionSchema
end

-- ── apply selection ───────────────────────────────────────────────────────────

function RivalSwap._applyRivalSelection(mod, game, id, availableId)
  if not (id == RIVAL_DEFAULT_ID
       or id == RIVAL_VANILLA_ID
       or availableId[id] == true) then
    mod.log:warn("_applyRivalSelection: unavailable rival id %q", tostring(id))
    return
  end
  local ok1 = pcall(mod.save.set,    mod.save,    "selected_rival", id)
  local ok2 = pcall(mod.options.set, mod.options, "rival",          id)
  if not ok1 then mod.log:error("_applyRivalSelection: save:set failed for %q",    id) end
  if not ok2 then mod.log:error("_applyRivalSelection: options:set failed for %q", id) end
  -- Patch trainer records so the next battle uses the correct pic/palette.
  _patchAllRivalTrainerRecords(mod, id)
  -- Apply overworld NPC sprites immediately.
  local ow = game and game.overworld
  if ow then
    RivalSwap._applyRivalNPCSprites(mod, ow, id)
  end
end

-- ── overworld NPC sprite substitution ────────────────────────────────────────

function RivalSwap._applyRivalNPCSprites(mod, ow, rivalId)
  local SpriteRenderer = require("src.render.SpriteRenderer")

  -- Resolve the sprite definition to use.
  local spriteDef
  if rivalId == RIVAL_DEFAULT_ID or rivalId == RIVAL_VANILLA_ID then
    -- Restore the vanilla Blue sprite.
    local ok, data = pcall(require, "src.core.Data")
    spriteDef = ok and data and data.sprites and data.sprites[RIVAL_SPRITE_ID]
    if not spriteDef then
      mod.log:warn("_applyRivalNPCSprites: vanilla sprite %q not found", RIVAL_SPRITE_ID)
      return
    end
  else
    spriteDef = RivalSwap._resolveSpriteDef(mod, rivalId)
    if not spriteDef then
      mod.log:warn(
        "_applyRivalNPCSprites: sprite def not found for %q — rival stays vanilla",
        rivalId)
      return
    end
    -- Verify the walk image still exists on disk (user may have deleted custom sprites).
    local walkImage = WALK_IMAGE_BY_ID[rivalId]
    if walkImage then
      local fs = love and love.filesystem
      if fs and fs.getInfo and not fs.getInfo(walkImage) then
        mod.log:error(
          "_applyRivalNPCSprites: walkImage %q not found — reverting rival to DEFAULT",
          walkImage)
        pcall(mod.save.set,    mod.save,    "selected_rival", RIVAL_DEFAULT_ID)
        pcall(mod.options.set, mod.options, "rival",          RIVAL_DEFAULT_ID)
        return
      end
    end
  end

  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.sprite == RIVAL_SPRITE_ID then
      local ok, result = pcall(SpriteRenderer.new, spriteDef, npc.id)
      if ok then
        npc.sprite = result
      else
        mod.log:error(
          "_applyRivalNPCSprites: SpriteRenderer.new failed for npc %s: %s",
          tostring(npc.id), tostring(result))
      end
    end
  end
end

-- ── helpers ───────────────────────────────────────────────────────────────────

function RivalSwap._buildChoices(characters, availableId)
  -- DEFAULT pinned first; remaining entries sorted alphabetically.
  local choices = { { "DEFAULT (vanilla)", RIVAL_DEFAULT_ID } }
  for _, char in ipairs(characters) do
    if availableId[char.id] == true or char.id == RIVAL_VANILLA_ID then
      choices[#choices + 1] = { char.label, char.id }
    end
  end
  table.sort(choices, function(a, b)
    if a[2] == RIVAL_DEFAULT_ID then return true end
    if b[2] == RIVAL_DEFAULT_ID then return false end
    return a[2] < b[2]
  end)
  return choices
end

return RivalSwap
