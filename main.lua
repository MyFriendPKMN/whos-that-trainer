return function(mod)
  local function loadMod(filename)
    local src = mod:read(filename)
    if not src then error("Failed to read " .. filename) end
    local chunk, err = loadstring(src, filename)
    if not chunk then error("Failed to compile " .. filename .. ": " .. tostring(err)) end
    return chunk()
  end

  local Characters              = loadMod("characters.lua")
  local CustomCharacterLoader   = loadMod("custom_character_loader.lua")
  CustomCharacterLoader.load(mod, Characters)   -- registers game.ready handler before CharacterSwap
  local CharacterSwap           = loadMod("character_swap.lua")
  local RivalSwap     = loadMod("rival_swap.lua")
  local FollowerSwap  = loadMod("follower_swap.lua")

  -- Collect option schemas from each module before registering them.
  -- mod.options:define REPLACES the entire schema on each call, so
  -- both modules return their schemas and the call is made only once.
  local charSchema     = CharacterSwap.init(mod, Characters)
  local rivalSchema    = RivalSwap.init(mod, Characters, CharacterSwap.AVAILABLE_ID)
  local followerSchema = FollowerSwap.init(mod, Characters, CharacterSwap.AVAILABLE_ID)

  -- Single define call: combines rows from both modules.
  local combined = {}
  for _, row in ipairs(charSchema     or {}) do combined[#combined + 1] = row end
  for _, row in ipairs(rivalSchema    or {}) do combined[#combined + 1] = row end
  for _, row in ipairs(followerSchema or {}) do combined[#combined + 1] = row end
  if #combined > 0 then
    mod.options:define(combined)
  end
end
