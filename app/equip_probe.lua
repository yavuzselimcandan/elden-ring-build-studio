-- Read-only EquipGameData/inventory correlation helper.
-- Intentionally not loaded by bridge.lua until the request mode is reviewed.
local M = {}

local function u32(value)
  return value and (value & 0xFFFFFFFF) or nil
end

-- gd is the already-resolved GameDataMan global pointer target from the CT AOB.
-- No slot offset is inferred: the dump is raw and correlation is evidence-only.
function M.capture(gd, inventoryBase, inventoryCount, outPath)
  assert(gd and gd > 0x10000, 'GameDataMan pointer required')
  assert(inventoryBase and inventoryBase > 0x10000, 'inventory base required')
  assert(inventoryCount and inventoryCount >= 0 and inventoryCount <= 2688, 'inventory count invalid')
  local pid = getProcessIDFromProcessName('eldenring.exe')
  local manager = assert(readQword(gd), 'GameDataMan is null')
  local playerData = assert(readQword(manager + 0x8), 'player game data is null')
  -- Supplied Hexinton CT v5.0 uses GameDataMan -> +08 -> inline player fields.
  local lines = {'mode=equip_probe_read_only', 'pid=' .. tostring(pid), 'timestamp=' .. tostring(os.time()), 'gameDataMan=' .. tostring(manager), 'playerGameData=' .. tostring(playerData), 'layout=CT-v5.0-inline-playerGameData'}
  local slots = {
    {0x388,'Accessory1'},{0x38C,'Accessory2'},{0x390,'Accessory3'},{0x394,'Accessory4'},{0x398,'Accessory5'},
    {0x39C,'PrimaryLeftWep'},{0x3A0,'PrimaryRightWep'},{0x3A4,'SecondaryLeftWep'},{0x3A8,'SecondaryRightWep'},
    {0x3AC,'TertiaryLeftWep'},{0x3B0,'TertiaryRightWep'},{0x3B4,'PrimaryArrow'},{0x3B8,'PrimaryBolt'},
    {0x3BC,'SecondaryArrow'},{0x3C0,'SecondaryBolt'},{0x3C4,'TertiaryArrow'},{0x3C8,'Head'},
    {0x3CC,'Chest'},{0x3D0,'Arms'},{0x3D4,'Legs'},{0x3D8,'UnknownArmor'}
  }
  local equipValues = {}
  for _, slot in ipairs(slots) do
    local value = u32(readInteger(playerData + slot[1])); equipValues[value] = true
    lines[#lines + 1] = string.format('slot=%s,offset=0x%X,value=%u', slot[2], slot[1], value)
  end
  local matches = {}
  for i = 0, inventoryCount - 1 do
    local entry = inventoryBase + i * 0x18
    local instance = u32(readInteger(entry))
    local rawId = u32(readInteger(entry + 4))
    local quantity = u32(readInteger(entry + 8))
    if instance and instance > 0 and instance ~= 0xFFFFFFFF and rawId and rawId ~= 0xFFFFFFFF and quantity and quantity > 0 then
      lines[#lines + 1] = string.format('inventory%d=address:%s,first:%u,rawID:%u,quantity:%u', i, tostring(entry), instance, rawId, quantity)
      if equipValues[instance] then matches[#matches + 1] = string.format('match=inventory%d,field=firstDWORD', i) end
      if equipValues[rawId] then matches[#matches + 1] = string.format('match=inventory%d,field=rawID', i) end
    end
  end
  if #matches == 0 then lines[#lines + 1] = 'matches=none' else for _, line in ipairs(matches) do lines[#lines + 1] = line end end
  local f = assert(io.open(outPath, 'w')); f:write(table.concat(lines, '\n')); f:close()
  return {manager = manager, playerData = playerData, matches = #matches}
end

return M
