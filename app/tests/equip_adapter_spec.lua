-- Runs equip_adapter.lua against mocked Cheat Engine memory. Invoked by test_equip_adapter.ps1.
-- The synthetic character mirrors runtime/equip-probe.txt (game 2.2.0.0, 2026-09-11).
local appRoot = ...
local mem, failWriteAt, writes = {}, nil, 0

function readInteger(a)
  local v = mem[a]
  if v == nil then return nil end
  v = v & 0xFFFFFFFF
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end
function writeInteger(a, v)
  writes = writes + 1
  if failWriteAt and writes == failWriteAt then return false end
  mem[a] = v & 0xFFFFFFFF
  return true
end
local function u32(a) return mem[a] and (mem[a] & 0xFFFFFFFF) end

local PLAYER, INV = 0x10000, 0x200000
local inventory = {
  {0x807F0081, 110000}, {0x807F0083, 110000}, {0x807F0084, 110000},
  {0x807F00D4, 34030025}, {0x807F00B2, 1040010},
  {0x907F0101, 0x10000000 | 1101000}, {0x907F0102, 0x10000000 | 860100}, {0x907F0103, 0x10000000 | 170200}, {0x907F0104, 0x10000000 | 80300},
  {0xA0000870, 0x20000870}, {0xA00007E4, 0x200007E4}, {0xA0001B76, 0x20001B76},
  {0x807F0200, 3180825}, {0x907F0300, 0x10000000 | 130000}, {0xA000047E, 0x2000047E},
  {0x807F0201, 3180825},
}

local function reset(idBase)
  mem, failWriteAt, writes = {}, nil, 0
  for i, e in ipairs(inventory) do
    local a = INV + (i - 1) * 0x18
    mem[a], mem[a + 4], mem[a + 8] = e[1], e[2], 1
  end
  local handleBase = idBase - 22 * 4
  local slots = {
    [0] = {0x807F00D4, 34030025}, [1] = {0x807F00B2, 1040010},
    [2] = {0x807F0081, 110000}, [3] = {0x807F0083, 110000}, [4] = {0x807F0084, 110000}, [5] = {0x807F0081, 110000},
    [12] = {0x907F0101, 1101000}, [13] = {0x907F0102, 860100}, [14] = {0x907F0103, 170200}, [15] = {0x907F0104, 80300},
    [17] = {0xA0000870, 2160}, [18] = {0xA00007E4, 2020}, [19] = {0xA0001B76, 7030}, [20] = {0, 0},
  }
  for i = 0, 21 do
    local s = slots[i] or {0xFFFFFFFF, 0xFFFFFFFF}
    mem[PLAYER + handleBase + 4 * i], mem[PLAYER + idBase + 4 * i] = s[1], s[2]
  end
end

local function check(cond, msg) if not cond then error('FAIL: ' .. msg, 2) end end
local adapter = assert(loadfile(appRoot .. '/equip_adapter.lua'))()
local n = #inventory

-- 1. layout observed on 2.2.0.0
reset(0x398)
local layout = adapter.calibrate(PLAYER, INV, n)
check(layout and layout.idBase == 0x398 and layout.handleBase == 0x340, 'calibrates 2.2.0.0 layout at 0x398')
check(layout.talismanFormat == 'id' and layout.evidence >= 9, 'talisman id format and evidence count')

-- 2. v8 table layout (4 bytes later) is detected, not assumed
reset(0x39C)
local l2 = adapter.calibrate(PLAYER, INV, n)
check(l2 and l2.idBase == 0x39C, 'calibrates shifted 2.7.0.0 layout at 0x39C')

-- 3. any inconsistency refuses the layout
reset(0x398)
mem[PLAYER + 0x398 + 4 * 13] = 999999
check(adapter.calibrate(PLAYER, INV, n) == nil, 'mismatching chest slot blocks calibration')

-- 4. equip owned weapon, armor, talisman
reset(0x398)
layout = adapter.calibrate(PLAYER, INV, n)
local res = adapter.equip(PLAYER, INV, n, layout, {
  {slot = 'R1', category = 'weapon', id = 3180800, upgrade = 25},
  {slot = 'Head', category = 'armor', id = 130000, upgrade = 0},
  {slot = 'Talisman4', category = 'talisman', id = 1150, upgrade = 0},
})
check(res[1].status == 'equipped' and res[2].status == 'equipped' and res[3].status == 'equipped', 'three items equipped')
check(u32(PLAYER + 0x340 + 4) == 0x807F0200 and u32(PLAYER + 0x398 + 4) == 3180825, 'R1 handle + raw id written')
check(u32(PLAYER + 0x340 + 48) == 0x907F0300 and u32(PLAYER + 0x398 + 48) == 130000, 'Head handle + plain param id written')
check(u32(PLAYER + 0x340 + 80) == 0xA000047E and u32(PLAYER + 0x398 + 80) == 1150, 'Talisman4 handle + id written')

-- 5. re-applying is idempotent
res = adapter.equip(PLAYER, INV, n, layout, {{slot = 'R1', category = 'weapon', id = 3180800, upgrade = 25}})
check(res[1].status == 'already-equipped', 'second apply reports already-equipped')

-- 6. second copy of the same weapon goes to another slot; a third request finds none
res = adapter.equip(PLAYER, INV, n, layout, {{slot = 'L2', category = 'weapon', id = 3180800, upgrade = 25}, {slot = 'L3', category = 'weapon', id = 3180800, upgrade = 25}})
check(res[1].status == 'equipped' and u32(PLAYER + 0x340 + 8) == 0x807F0201, 'second instance used for L2')
check(res[2].status == 'already-equipped-elsewhere', 'no third instance for L3')

-- 7. never equips items that are not owned, never writes the wrong category
local before = u32(PLAYER + 0x398 + 52)
res = adapter.equip(PLAYER, INV, n, layout, {{slot = 'Chest', category = 'armor', id = 424242, upgrade = 0}, {slot = 'Chest', category = 'weapon', id = 3180800, upgrade = 25}})
check(res[1].status == 'not-owned' and res[2].status == 'wrong-category' and u32(PLAYER + 0x398 + 52) == before, 'not-owned / wrong-category leave memory untouched')

-- 8. a failing write rolls back everything written by the request
reset(0x398)
layout = adapter.calibrate(PLAYER, INV, n)
local r1h, r1v = u32(PLAYER + 0x340 + 4), u32(PLAYER + 0x398 + 4)
failWriteAt = 3
local ok, err = pcall(adapter.equip, PLAYER, INV, n, layout, {
  {slot = 'R1', category = 'weapon', id = 3180800, upgrade = 25},
  {slot = 'Head', category = 'armor', id = 130000, upgrade = 0},
})
failWriteAt = nil
check(not ok and tostring(err):find('rolled back'), 'write failure raises rolled back error')
check(u32(PLAYER + 0x340 + 4) == r1h and u32(PLAYER + 0x398 + 4) == r1v, 'R1 restored after rollback')

return 'equip adapter spec passed (8 scenarios)'
