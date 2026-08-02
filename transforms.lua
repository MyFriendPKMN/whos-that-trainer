-- transforms.lua
-- Derives battle back sprites for each selectable character from the player's
-- own ROM cache.
-- Source assets are trainer front sprites already extracted by RomExtractor
-- into the generated asset cache.
-- Nothing here runs before the player imports a ROM.
--
-- Pipeline: invoked by the engine's assets.transformed event.
-- Result: files written to the asset cache (never committed).
--
-- RED: vanilla paths already exist; no transform is needed - omitted here.
-- Walk sheets are already present in the ROM cache under their canonical paths
-- (sprites/<name>.png) and do not need to be copied — only back sprites are
-- derived here.

local function makeDerivedBack(id, srcFront, overrides)
  local out = {
    id = id,
    src_front = srcFront,
    dst_back = "battle/player_back/" .. string.lower(id) .. "_back.png",
    useOriginalSize = true,
    scale = 1.0,
    cropBottomRatio = 0.40,
    anchorX = "center",
    anchorY = "bottom",
    offsetX = 0,
    offsetY = -14,
  }
  if overrides then
    for k, v in pairs(overrides) do
      out[k] = v
    end
  end
  return out
end

local DERIVED_BACKS = {
  makeDerivedBack("GIOVANNI", "battle/trainers/giovanni.png", { mirror = true }),
  makeDerivedBack("BROCK", "battle/trainers/brock.png", { mirror = true }),
  makeDerivedBack("MISTY", "battle/trainers/misty.png", { mirror = true }),
  makeDerivedBack("LT_SURGE", "battle/trainers/lt.surge.png", { mirror = true }),
  makeDerivedBack("ERIKA", "battle/trainers/erika.png", { mirror = true }),
  makeDerivedBack("KOGA", "battle/trainers/koga.png", { mirror = true }),
  makeDerivedBack("SABRINA", "battle/trainers/sabrina.png", { mirror = true }),
  makeDerivedBack("BLAINE", "battle/trainers/blaine.png", { mirror = true }),
  makeDerivedBack("LORELEI", "battle/trainers/lorelei.png", { mirror = true }),
  makeDerivedBack("BRUNO", "battle/trainers/bruno.png", { mirror = true }),
  makeDerivedBack("AGATHA", "battle/trainers/agatha.png", { mirror = true }),
  makeDerivedBack("LANCE", "battle/trainers/lance.png", { mirror = true }),
  makeDerivedBack("BLUE", "battle/trainers/rival3.png", { mirror = true }),
  -- jessie_james.png is the only battle sprite available for the duo.
  -- useOriginalSize=false lets fitScale normalize the wide canvas first,
  -- then scale=0.5 halves it. integerScale=false avoids rounding up to
  -- a large integer step that would make the sprite oversized.
  makeDerivedBack("JESSIE", "battle/trainers/jessie_james.png", { mirror = true, useOriginalSize = false, scale = 0.95, integerScale = false }),
  makeDerivedBack("JAMES",  "battle/trainers/jessie_james.png", { mirror = true, useOriginalSize = false, scale = 0.95, integerScale = false }),
}

local function computeAnchorStart(canvasSize, spriteSize, anchor, margin)
  if anchor == "start" or anchor == "left" or anchor == "top" then
    return margin
  end
  if anchor == "end" or anchor == "right" or anchor == "bottom" then
    return canvasSize - spriteSize - margin
  end
  return math.floor((canvasSize - spriteSize) / 2)
end

local function clampStart(start, canvasSize, spriteSize, margin)
  if spriteSize + margin * 2 <= canvasSize then
    local minStart = margin
    local maxStart = canvasSize - spriteSize - margin
    if start < minStart then return minStart end
    if start > maxStart then return maxStart end
    return start
  end
  -- If sprite is larger than canvas, keep it centered to minimize bad crops.
  return math.floor((canvasSize - spriteSize) / 2)
end

local function opaqueBounds(img)
  local sw, sh = img:getDimensions()
  local minX, minY = sw - 1, sh - 1
  local maxX, maxY = 0, 0
  local found = false
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local _, _, _, a = img:getPixel(x, y)
      if a and a > 0 then
        found = true
        if x < minX then minX = x end
        if y < minY then minY = y end
        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
      end
    end
  end
  if not found then return nil end
  return minX, minY, maxX, maxY
end

local function deriveBackFromFront(ctx, srcRel, dstRel, opts)
  opts = opts or {}
  local refRel = "battle/redb.png"
  if not ctx.exists(srcRel) then
    return false
  end
  if not ctx.exists(refRel) then
    return false
  end

  local src = ctx.readImage(srcRel)
  local ref = ctx.readImage(refRel)
  local rw, rh = ref:getDimensions()
  local sw, sh = src:getDimensions()
  if sw <= 0 or sh <= 0 or rw <= 0 or rh <= 0 then
    return false
  end

  -- Crop to opaque bounds first; trainer sheets usually carry large transparent
  -- margins and scaling the full canvas makes the character look tiny.
  local minX, minY, maxX, maxY = opaqueBounds(src)
  if not minX then return false end

  -- [NOVO] Lógica de recorte da parte inferior
  local cropRatio = opts.cropBottomRatio or 0
  if cropRatio > 0 and cropRatio < 1 then
    local currentHeight = maxY - minY + 1
    local pixelsToKeep = math.floor(currentHeight * (1 - cropRatio))
    maxY = minY + pixelsToKeep - 1
  end

  local cw = maxX - minX + 1
  local ch = maxY - minY + 1
  if cw <= 0 or ch <= 0 then return false end

  local margin = 2
  local maxW = math.max(1, rw - margin * 2)
  local maxH = math.max(1, rh - margin * 2)
  local fitScale = math.min(maxW / cw, maxH / ch)
  local baseScale = opts.useOriginalSize and math.min(1, fitScale) or fitScale
  
  -- Integer scaling preserves pixel art sharpness. Set integerScale = false
  -- to use fractional scaling when the source sprite has unusual proportions
  -- (e.g. a duo sheet that would round up to an oversized integer step).
  local targetScale = baseScale * (opts.scale or 1)
  local scale
  if opts.integerScale == false then
    scale = math.max(0.25, targetScale)
  else
    scale = math.floor(targetScale + 0.5)
    if scale < 1 then scale = 1 end
  end

  local nw = math.max(1, math.floor(cw * scale + 0.5))
  local nh = math.max(1, math.floor(ch * scale + 0.5))
  local x0 = computeAnchorStart(rw, nw, opts.anchorX, margin) + (opts.offsetX or 0)
  local y0 = computeAnchorStart(rh, nh, opts.anchorY, margin) + (opts.offsetY or 0)
  if opts.clampToCanvas ~= false then
    x0 = clampStart(x0, rw, nw, margin)
    y0 = clampStart(y0, rh, nh, margin)
  end

  local out = ctx.blank(rw, rh, 0, 0, 0, 0)
  for y = 0, nh - 1 do
    for x = 0, nw - 1 do
      local sx = math.min(maxX, math.max(minX, minX + math.floor(x / scale)))
      local sy = math.min(maxY, math.max(minY, minY + math.floor(y / scale)))
      local dx = x0 + x
      local dy = y0 + y
      -- [NOVO] Espelhamento horizontal quando opts.mirror == true
      if opts.mirror then
        dx = x0 + (nw - 1 - x)
      end
      if dx >= 0 and dx < rw and dy >= 0 and dy < rh then
        out:setPixel(dx, dy, src:getPixel(sx, sy))
      end
    end
  end
  ctx.writeImage(out, dstRel)
  return true
end

return function(ctx)
  local count = 0
  for _, back in ipairs(DERIVED_BACKS) do
    if deriveBackFromFront(ctx, back.src_front, back.dst_back, back) then
      count = count + 1
    end
  end
  return count
end