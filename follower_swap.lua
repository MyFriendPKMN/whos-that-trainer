-- follower_swap.lua
-- Manages follower sprite selection, persistence, and substitution.
-- Depends on characters.lua and AVAILABLE_ID from character_swap.lua.
-- State is completely isolated from character_swap.lua and rival_swap.lua.
--
-- The follower Pikachu lives in ow.npcs and is accessed via PikachuFollower.current(ow).
-- When "DEFAULT" is active the handler returns immediately without touching the follower
-- sprite, preserving vanilla engine behavior (Pikachu in Yellow, nothing in Red/Blue).

local FollowerSwap = {}

local FOLLOWER_DEFAULT_ID = "DEFAULT"   -- explicit vanilla no-op sentinel; not a character id
local PSS_PREFIX          = "MOD_PSS_"

-- Lookup table: character id -> char.walkId (canonical mod registry key for walk sprite)
local WALK_ID_BY_CHAR_ID = {}

-- ── persistence ──────────────────────────────────────────────────────────────

-- Resolves the active follower id from options and save state.
-- Mirrors the pattern used by RivalSwap._resolveSelectedRival.
function FollowerSwap._resolveSelected(mod, availableId)
  local fromOptions = mod.options:get("follower")
  local fromSave    = mod.save:get("selected_follower")
  local function valid(id)
    return type(id) == "string"
        and (id == FOLLOWER_DEFAULT_ID or availableId[id] == true)
  end
  local chosen = (valid(fromOptions) and fromOptions)
              or (valid(fromSave)    and fromSave)
              or FOLLOWER_DEFAULT_ID
  if fromSave ~= chosen then
    local ok, err = pcall(mod.save.set, mod.save, "selected_follower", chosen)
    if not ok then
      mod.log:error("_resolveSelected: save:set failed: %s", tostring(err))
    end
  end
  return chosen
end

-- ── initialization ────────────────────────────────────────────────────────────

-- Initializes the follower swap module.
-- Populates WALK_ID_BY_CHAR_ID, registers event handlers and the selection screen,
-- and returns the option schema for main.lua to accumulate into mod.options:define.
function FollowerSwap.init(mod, characters, availableId)
  -- Populate walk id lookup from the shared characters catalog
  for _, char in ipairs(characters) do
    WALK_ID_BY_CHAR_ID[char.id] = char.walkId
  end

  -- Option schema returned to main.lua for the combined define call
  local optionSchema = {
    {
      key     = "follower",
      label   = "FOLLOWER",
      type    = "choice",
      default = FOLLOWER_DEFAULT_ID,
      choices = FollowerSwap._buildChoices(characters, availableId),
    },
  }

  -- Sync on game.ready
  mod.events:on("game.ready", function()
    local chosen = FollowerSwap._resolveSelected(mod, availableId)
    mod.log:info("follower_swap: active follower = %s", chosen)
  end)

  -- Sync on save load; apply immediately if the overworld is available
  mod.events:on("save.loaded", function()
    local chosen = FollowerSwap._resolveSelected(mod, availableId)
    mod.log:info("save.loaded sync selected_follower=%s", chosen)
    local game = mod.world and mod.world.game
    local ow   = game and game.overworld
    if ow then
      FollowerSwap._applyFollowerSprite(mod, ow, chosen)
    end
  end)

  -- Apply on every map transition; skip when DEFAULT is selected
  mod.events:on("map.entered", function(ev)
    local ow = ev.overworld
    if not ow then return end
    local chosen = FollowerSwap._resolveSelected(mod, availableId)
    -- DEFAULT = vanilla Pikachu; nothing to override
    if chosen == FOLLOWER_DEFAULT_ID then return end
    FollowerSwap._applyFollowerSprite(mod, ow, chosen)
  end)

  -- Selection screen — mirrors the structure used by rival_swap
  local SCREEN = PSS_PREFIX .. "FOLLOWER_SELECT"
  mod.content.screens:register(SCREEN, {
    new = function(game)
      local active = FollowerSwap._resolveSelected(mod, availableId)
      local rows   = {}
      -- "DEFAULT" entry is always first — explicit vanilla restore escape hatch
      rows[#rows + 1] = { label = "DEFAULT (vanilla)", charId = FOLLOWER_DEFAULT_ID }
      for _, char in ipairs(characters) do
        if availableId[char.id] == true then
          rows[#rows + 1] = { label = char.label, charId = char.id }
        end
      end
      table.sort(rows, function(a, b)
        -- pin DEFAULT at index 1; sort all remaining entries alphabetically by label
        if a.charId == FOLLOWER_DEFAULT_ID then return true end
        if b.charId == FOLLOWER_DEFAULT_ID then return false end
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
        -- Defensive fallback; should never happen because DEFAULT is always inserted above.
        items[#items + 1] = { label = "DEFAULT (vanilla)", charId = FOLLOWER_DEFAULT_ID }
      end

      return mod.ui.ListMenu.new(game, "FOLLOWER", items, {
        pageJump = true,
        onChoose = function(item, menu)
          if not item.charId then menu:close(); return end
          FollowerSwap._applySelection(mod, game, item.charId, availableId)
          menu:close()
        end,
      })
    end,
  })

  -- Inject "FOLLOWER" entry into the start menu
  mod.events:on("ui.start_menu.items", function(ev)
    ev.items[#ev.items + 1] = {
      label  = "FOLLOWER",
      action = function(game) game.screens:push(SCREEN) end,
    }
  end)

  return optionSchema
end

-- ── apply selection ───────────────────────────────────────────────────────────

-- Persists the chosen follower id and applies the sprite to the live overworld.
function FollowerSwap._applySelection(mod, game, id, availableId)
  if not (id == FOLLOWER_DEFAULT_ID or availableId[id] == true) then
    mod.log:warn("_applySelection: unavailable follower id %q", tostring(id))
    return
  end
  pcall(mod.save.set,    mod.save,    "selected_follower", id)
  pcall(mod.options.set, mod.options, "follower",          id)
  local ow = game and game.overworld
  if ow then
    FollowerSwap._applyFollowerSprite(mod, ow, id)
  end
end

-- ── overworld follower ────────────────────────────────────────────────────────

-- Replaces the follower NPC's sprite with the walk sprite for followerId.
-- The Pikachu follower lives inside ow.npcs; PikachuFollower.current(ow) locates it.
function FollowerSwap._applyFollowerSprite(mod, ow, followerId)
  -- DEFAULT = vanilla Pikachu; do not touch the follower sprite at all
  if followerId == FOLLOWER_DEFAULT_ID then return end

  -- Locate the follower NPC via PikachuFollower — it lives inside ow.npcs, not ow.follower
  local PikachuFollower = require("src.world.PikachuFollower")
  local follower = PikachuFollower.current(ow)
  if not follower then return end   -- non-Yellow ROM or pre-starter state; silent skip

  local SpriteRenderer = require("src.render.SpriteRenderer")

  -- Resolve sprite definition using the canonical walkId from the characters catalog.
  -- Prefer mod.content.sprites (merged view) over data.sprites (vanilla only).
  local walkId    = WALK_ID_BY_CHAR_ID[followerId]
  local spriteDef = nil

  if walkId then
    spriteDef = mod.content.sprites:get(walkId)
  end

  if not spriteDef then
    -- Fallback: vanilla data.sprites entry for RED or any character without a mod registration
    local ok, data = pcall(require, "src.core.Data")
    if ok and data and data.sprites then
      spriteDef = data.sprites["SPRITE_" .. followerId]
    end
  end

  if not spriteDef then
    mod.log:warn(
      "_applyFollowerSprite: sprite def not found for %q — reverting to DEFAULT",
      followerId)
    pcall(mod.save.set,    mod.save,    "selected_follower", FOLLOWER_DEFAULT_ID)
    pcall(mod.options.set, mod.options, "follower",          FOLLOWER_DEFAULT_ID)
    return
  end

  local ok, result = pcall(SpriteRenderer.new, spriteDef, "follower")
  if ok then
    follower.sprite = result
  else
    mod.log:error(
      "_applyFollowerSprite: SpriteRenderer.new failed for %q: %s",
      followerId, tostring(result))
  end
end

-- ── helpers ───────────────────────────────────────────────────────────────────

-- Builds the choices list for the "follower" option.
-- "DEFAULT" is always pinned at index 1; available characters follow, sorted by id.
function FollowerSwap._buildChoices(characters, availableId)
  local choices = { { "DEFAULT (vanilla)", FOLLOWER_DEFAULT_ID } }
  for _, char in ipairs(characters) do
    if availableId[char.id] == true then
      choices[#choices + 1] = { char.label, char.id }
    end
  end
  table.sort(choices, function(a, b)
    if a[2] == FOLLOWER_DEFAULT_ID then return true end
    if b[2] == FOLLOWER_DEFAULT_ID then return false end
    return a[2] < b[2]
  end)
  return choices
end

return FollowerSwap
