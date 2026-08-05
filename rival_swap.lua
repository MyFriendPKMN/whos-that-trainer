-- rival_swap.lua
-- Manages rival selection, persistence, and sprite substitution.
-- Depends on characters.lua and AVAILABLE_ID from character_swap.lua.
-- State is completely isolated from character_swap.lua.

local RivalSwap = {}

local RIVAL_DEFAULT_ID  = "BLUE"
local PSS_PREFIX        = "MOD_PSS_"
local RIVAL_SPRITE_ID   = "SPRITE_BLUE"
local RIVAL_OPP_CLASSES = {
  OPP_RIVAL1 = true, OPP_RIVAL2 = true, OPP_RIVAL3 = true,
}

local FRONT_PATH_BY_ID = {}
local WALK_IMAGE_BY_ID = {}

-- ── persistence ──────────────────────────────────────────────────────────────

function RivalSwap._resolveSelectedRival(mod, availableId)
  local fromOptions = mod.options:get("rival")
  local fromSave    = mod.save:get("selected_rival")
  local function valid(id)
    return type(id) == "string"
        and (id == RIVAL_DEFAULT_ID or availableId[id] == true)
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

-- ── initialization ─────────────────────────────────────────────────────────────

function RivalSwap.init(mod, characters, availableId)
  -- Populate lookup tables from characters.lua data
  for _, char in ipairs(characters) do
    FRONT_PATH_BY_ID[char.id] = char.frontPath
    WALK_IMAGE_BY_ID[char.id] = char.walkImage
  end

  -- Register "rival" option in mod.options (separate from "character")
  -- Does not call mod.options:define here: main.lua accumulates schemas from
  -- CharacterSwap and RivalSwap and makes a single combined call.
  local optionSchema = {
    {
      key     = "rival",
      label   = "RIVAL",
      type    = "choice",
      default = RIVAL_DEFAULT_ID,
      choices = RivalSwap._buildChoices(characters, availableId),
    },
  }

  -- Inject the custom rival portrait into the Oak intro speech.
  -- OakSpeech.new() captures rivalPic from trainers.OPP_RIVAL1.pic at
  -- construction time, before game.ready fires. The patch applied in
  -- game.ready/save.loaded is too late for a new-game flow.
  -- intro.oak_speech.started fires after buildSteps() but before the first
  -- frame renders, giving us a safe window to overwrite speech.rivalPic.
  mod.events:on("intro.oak_speech.started", function(ev)
    local speech = ev and ev.speech
    if not speech then return end
    local rivalId = RivalSwap._resolveSelectedRival(mod, availableId)
    if rivalId == RIVAL_DEFAULT_ID then return end
    local frontPath = FRONT_PATH_BY_ID[rivalId]
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

  -- Initial validation
  mod.events:on("game.ready", function()
    local chosen = RivalSwap._resolveSelectedRival(mod, availableId)
    mod.log:info("rival_swap: active rival = %s", chosen)
  end)

  -- Sync on save load
  mod.events:on("save.loaded", function()
    local chosen = RivalSwap._resolveSelectedRival(mod, availableId)
    mod.log:info("save.loaded sync selected_rival=%s", chosen)
    -- Apply immediately to overworld if available (like character_swap does)
    local game = mod.world and mod.world.game
    local ow = game and game.overworld
    if ow and ow.player then
      RivalSwap._applyRivalNPCSprites(mod, ow, chosen)
      mod.log:info("save.loaded reapplied rival sprite for %s", chosen)
    end
  end)

  -- ── overworld: rival NPC sprite substitution ────────────────────────────────
  mod.events:on("map.entered", function(ev)
    local ok, Game = pcall(require, "src.core.Game")
    local ow = ok and Game and Game.overworld
    if not ow then return end
    local rivalId = RivalSwap._resolveSelectedRival(mod, availableId)
    -- When BLUE is selected, no sprite override is needed —
    -- NPCs are already loaded with SPRITE_BLUE by native NPC.new.
    if rivalId == RIVAL_DEFAULT_ID then return end
    RivalSwap._applyRivalNPCSprites(mod, ow, rivalId)
  end)

  -- ── battle: opponent trainer portrait substitution ────────────────────────────
  -- BattleState.newTrainer builds self.trainerPic via getImage(trainerPicPath, trainerPalette).
  -- trainerPicPath reads trainer.pic; trainerPalette reads trainer.paletteSource.
  -- Patching both fields on the OPP_RIVAL* records before battle construction
  -- makes the engine apply the correct palette automatically — no hook needed.
  -- Patches are applied on game.ready and on save.loaded so they survive
  -- a continue/load flow. The patch is reset to BLUE defaults when BLUE is selected.
  local function _patchRivalTrainerRecords(rivalId)
    local frontPath     = FRONT_PATH_BY_ID[rivalId]
    local paletteSource = rivalId ~= RIVAL_DEFAULT_ID
                          and ("SPRITE_" .. rivalId)
                          or nil
    for oppClass in pairs(RIVAL_OPP_CLASSES) do
      if rivalId == RIVAL_DEFAULT_ID then
        -- restore vanilla: clear mod-set pic/paletteSource so the engine
        -- falls back to the original trainer.pic from game.data.trainers
        mod.content.trainers:patch(oppClass, { pic = nil, paletteSource = nil })
      else
        mod.content.trainers:patch(oppClass, {
          pic           = frontPath    or nil,
          paletteSource = paletteSource,
        })
      end
    end
  end

  mod.events:on("game.ready", function()
    local rivalId = RivalSwap._resolveSelectedRival(mod, availableId)
    _patchRivalTrainerRecords(rivalId)
  end)

  -- Re-apply after a continue/load because mod.content merges reset on save swap.
  mod.events:on("save.loaded", function()
    local rivalId = RivalSwap._resolveSelectedRival(mod, availableId)
    _patchRivalTrainerRecords(rivalId)
  end)

  -- ── selection screen ────────────────────────────────────────────────────────
  local RIVAL_SCREEN = PSS_PREFIX .. "RIVAL_SELECT"
  mod.content.screens:register(RIVAL_SCREEN, {
    new = function(game)
      local active = RivalSwap._resolveSelectedRival(mod, availableId)
      local rows   = {}
      for _, char in ipairs(characters) do
        if availableId[char.id] == true or char.id == RIVAL_DEFAULT_ID then
          rows[#rows + 1] = { label = char.label, charId = char.id }
        end
      end
      table.sort(rows, function(a, b) return a.label < b.label end)

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
        items[#items + 1] = { label = "No rivals available.", charId = nil }
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

  -- Inject "RIVAL" entry in start menu
  mod.events:on("ui.start_menu.items", function(ev)
    ev.items[#ev.items + 1] = {
      label  = "RIVAL",
      action = function(game) game.screens:push(RIVAL_SCREEN) end,
    }
  end)

  -- Return option schema so main.lua can combine it with character_swap's
  -- schema before calling mod.options:define once.
  return optionSchema
end

-- ── apply selection ───────────────────────────────────────────────────────────

function RivalSwap._applyRivalSelection(mod, game, id, availableId)
  if not (id == RIVAL_DEFAULT_ID or availableId[id] == true) then
    mod.log:warn("_applyRivalSelection: unavailable rival id %q", tostring(id))
    return
  end
  local ok1 = pcall(mod.save.set, mod.save, "selected_rival", id)
  local ok2 = pcall(mod.options.set, mod.options, "rival", id)
  if not ok1 then mod.log:error("_applyRivalSelection: save:set failed for %q", id) end
  if not ok2 then mod.log:error("_applyRivalSelection: options:set failed for %q", id) end
  -- Patch trainer records so the next battle uses the correct pic and palette.
  local frontPath     = FRONT_PATH_BY_ID[id]
  local paletteSource = id ~= RIVAL_DEFAULT_ID and ("SPRITE_" .. id) or nil
  for oppClass in pairs(RIVAL_OPP_CLASSES) do
    if id == RIVAL_DEFAULT_ID then
      mod.content.trainers:patch(oppClass, { pic = nil, paletteSource = nil })
    else
      mod.content.trainers:patch(oppClass, {
        pic           = frontPath    or nil,
        paletteSource = paletteSource,
      })
    end
  end
  -- Apply immediately to current map NPCs if available.
  local ow = game and game.overworld
  if ow then
    RivalSwap._applyRivalNPCSprites(mod, ow, id)
  end
end

-- ── overworld NPC ─────────────────────────────────────────────────────────────

function RivalSwap._applyRivalNPCSprites(mod, ow, rivalId)
  local SpriteRenderer = require("src.render.SpriteRenderer")

  -- Determine sprite definition to use for selected rival.
  -- BLUE (default) case: restores vanilla sprite via data.sprites["SPRITE_BLUE"]
  -- Character with registered walkImage (GIOVANNI, BROCK, etc.):
  --         → uses mod registry sprite "MOD_PSS_SPRITE_<rivalId>"
  -- Character without own walkImage (RED):
  --         → uses vanilla data.sprites["SPRITE_<rivalId>"]
  local spriteDef = nil
  local walkImage = WALK_IMAGE_BY_ID[rivalId]

  if rivalId == RIVAL_DEFAULT_ID then
    -- Restore vanilla BLUE sprite
    local ok, data = pcall(require, "src.core.Data")
    if ok and data and data.sprites then
      spriteDef = data.sprites[RIVAL_SPRITE_ID]  -- "SPRITE_BLUE"
    end
    if not spriteDef then
      mod.log:warn("_applyRivalNPCSprites: vanilla sprite %q not found", RIVAL_SPRITE_ID)
      return
    end
  elseif walkImage then
    -- Verify asset existence before using mod sprite
    local fs = love and love.filesystem
    if fs and fs.getInfo and not fs.getInfo(walkImage) then
      mod.log:error(
        "_applyRivalNPCSprites: walkImage %q not found — reverting rival to BLUE",
        walkImage)
      pcall(mod.save.set, mod.save, "selected_rival", "BLUE")
      pcall(mod.options.set, mod.options, "rival", "BLUE")
      return
    end
    local walkId = "MOD_PSS_SPRITE_" .. rivalId
    spriteDef = mod.content.sprites:get(walkId)
    if not spriteDef then
      mod.log:warn(
        "_applyRivalNPCSprites: sprite def %q not registered — rival stays vanilla",
        walkId)
      return
    end
  else
    -- walkImage == nil: character uses vanilla sprite (e.g. RED → SPRITE_RED)
    local vanillaId = "SPRITE_" .. rivalId
    local ok, data = pcall(require, "src.core.Data")
    if ok and data and data.sprites then
      spriteDef = data.sprites[vanillaId]
    end
    if not spriteDef then
      mod.log:warn(
        "_applyRivalNPCSprites: vanilla sprite %q not found — rival stays vanilla",
        vanillaId)
      return
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
  local choices = {}
  for _, char in ipairs(characters) do
    if availableId[char.id] == true or char.id == RIVAL_DEFAULT_ID then
      choices[#choices + 1] = { char.label, char.id }
    end
  end
  table.sort(choices, function(a, b) return a[2] < b[2] end)
  return choices
end

return RivalSwap
