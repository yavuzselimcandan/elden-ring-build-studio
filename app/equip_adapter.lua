-- Equip adapter: places items the character already owns into equipment slots.
--
-- Layout evidence (runtime/equip-probe.txt, game 2.2.0.0, 2026-09-11) and CT v8.0.1 (game 2.7.0.0):
-- PlayerGameData holds two parallel 22-entry arrays in this order:
--   L1 R1 L2 R2 L3 R3 Arrow1 Bolt1 Arrow2 Bolt2 Arrow3 Bolt3 Head Chest Arms Legs Hair Acc1..Acc5
--   * handle array: GaItem handle of the equipped inventory entry (inventory entry +0)
--   * id array (directly after it): weapon raw ID (id+upgrade), armor param ID, talisman ID
-- On 2.2.0.0 the id array starts at +0x398; the v8 table (2.7.0.0) puts it at +0x39C.
-- Offsets are therefore NEVER assumed: calibrate() accepts a base only when every
-- occupied slot is consistent with an inventory entry (same handle, matching item),
-- and equip() refuses to write without a calibrated layout.
local M = {}

M.SLOT_INDEX = {
  L1 = 0, R1 = 1, L2 = 2, R2 = 3, L3 = 4, R3 = 5,
  Arrow1 = 6, Bolt1 = 7, Arrow2 = 8, Bolt2 = 9,
  Head = 12, Chest = 13, Arms = 14, Legs = 15,
  Talisman1 = 17, Talisman2 = 18, Talisman3 = 19, Talisman4 = 20
}
local COUNT = 22
local ID_BASE_CANDIDATES = { 0x398, 0x39C }
local EMPTY = 0xFFFFFFFF
local UNARMED = 110000

local function u32(v) return v and (v & 0xFFFFFFFF) or nil end
-- writeInteger takes a signed 32-bit value; handles such as 0x807F0081 must be passed as negatives.
local function s32(v) v = v & 0xFFFFFFFF; if v >= 0x80000000 then return v - 0x100000000 end; return v end

local function kindOf(index)
  if index <= 11 then return 'weapon' elseif index <= 15 then return 'armor' elseif index == 16 then return 'hair' else return 'talisman' end
end

-- Inventory raw IDs carry the category in the top nibble: weapon 0, armor 1, talisman 2, goods 4, ash 8.
local function rawFor(kind, id, upgrade)
  if kind == 'weapon' then return id + (upgrade or 0) end
  if kind == 'armor' then return 0x10000000 | id end
  if kind == 'talisman' then return 0x20000000 | id end
  return nil
end

function M.readInventory(base, count)
  local rows, byHandle = {}, {}
  for i = 0, count - 1 do
    local e = base + i * 0x18
    local handle, raw, qty = u32(readInteger(e)), u32(readInteger(e + 4)), u32(readInteger(e + 8))
    if handle and raw and qty and qty > 0 and handle ~= 0 and handle ~= EMPTY and raw ~= EMPTY then
      local row = { handle = handle, raw = raw, qty = qty }
      rows[#rows + 1] = row
      byHandle[handle] = row
    end
  end
  return rows, byHandle
end

-- Does the equipped id value agree with the inventory entry the handle points at?
local function consistent(kind, value, row)
  if not row then return false, nil end
  if kind == 'weapon' then return row.raw == value, 'id' end
  if kind == 'armor' then return row.raw == (0x10000000 | value), 'id' end
  -- (armor piece vs. slot is checked by the caller)
  if kind == 'talisman' then
    if row.raw == (0x20000000 | (value & 0x0FFFFFFF)) and value < 0x10000000 then return true, 'id' end
    if value == row.handle then return true, 'handle' end
  end
  return false, nil
end

function M.calibrate(playerData, invBase, invCount)
  local _, byHandle = M.readInventory(invBase, invCount)
  local report, accepted = {}, {}
  for _, idBase in ipairs(ID_BASE_CANDIDATES) do
    local handleBase = idBase - COUNT * 4
    local ok, bad, kinds, talismanFormat, lines = 0, 0, {}, nil, {}
    for i = 0, COUNT - 1 do
      local kind = kindOf(i)
      local value = u32(readInteger(playerData + idBase + 4 * i))
      local handle = u32(readInteger(playerData + handleBase + 4 * i))
      if kind ~= 'hair' and value and handle and value ~= EMPTY and value ~= 0 and handle ~= EMPTY and handle ~= 0 then
        local good, format = consistent(kind, value, byHandle[handle])
        -- A layout shifted by one slot keeps handle/id pairs consistent, so also require the
        -- armor piece to match its slot (param id x000 head, x100 chest, x200 arms, x300 legs).
        if good and kind == 'armor' and (value % 1000) // 100 ~= i - 12 then good = false end
        if good then
          ok = ok + 1; kinds[kind] = true
          if kind == 'talisman' then talismanFormat = talismanFormat or format end
        elseif not (kind == 'weapon' and value == UNARMED) then
          bad = bad + 1
        end
        lines[#lines + 1] = string.format('idx=%d kind=%s value=%u handle=%08X %s', i, kind, value, handle, good and 'ok' or 'MISMATCH')
      end
    end
    report[#report + 1] = string.format('candidate idBase=0x%X ok=%d bad=%d', idBase, ok, bad)
    for _, l in ipairs(lines) do report[#report + 1] = '  ' .. l end
    if bad == 0 and ok >= 3 and kinds.weapon and kinds.armor then
      accepted[#accepted + 1] = { idBase = idBase, handleBase = handleBase, talismanFormat = talismanFormat or 'id', evidence = ok }
    end
  end
  -- Exactly one candidate must fit; ambiguity is treated like a mismatch.
  if #accepted == 1 then return accepted[1], report end
  report[#report + 1] = string.format('accepted candidates=%d (need exactly 1)', #accepted)
  return nil, report
end

-- requests: { {slot='R1', category='weapon', id=3180800, upgrade=25}, ... }
-- Only items present in the inventory are equipped; nothing is created here.
function M.equip(playerData, invBase, invCount, layout, requests)
  assert(layout and layout.idBase and layout.handleBase, 'equip layout is not calibrated')
  local rows = M.readInventory(invBase, invCount)
  local used = {}
  for i = 0, COUNT - 1 do
    local h = u32(readInteger(playerData + layout.handleBase + 4 * i))
    if h and h ~= EMPTY and h ~= 0 then used[h] = i end
  end
  local results, written = {}, {}
  local function rollback()
    for k = #written, 1, -1 do
      local w = written[k]
      writeInteger(playerData + layout.handleBase + 4 * w.index, s32(w.oldHandle))
      writeInteger(playerData + layout.idBase + 4 * w.index, s32(w.oldValue))
    end
  end
  local ok, err = pcall(function()
    for _, r in ipairs(requests) do
      local index = M.SLOT_INDEX[r.slot]
      local kind = index and kindOf(index)
      local raw = kind and rawFor(kind, r.id, r.upgrade)
      local status
      if not index then status = 'unsupported-slot'
      elseif kind ~= r.category then status = 'wrong-category'
      else
        local oldHandle = u32(readInteger(playerData + layout.handleBase + 4 * index))
        local oldValue = u32(readInteger(playerData + layout.idBase + 4 * index))
        local current = oldHandle and used[oldHandle] == index and oldHandle
        local pick
        for _, row in ipairs(rows) do
          if row.raw == raw and (used[row.handle] == nil or row.handle == current) then pick = row; break end
        end
        if not pick then
          local owned = false
          for _, row in ipairs(rows) do if row.raw == raw then owned = true; break end end
          status = owned and 'already-equipped-elsewhere' or 'not-owned'
        elseif pick.handle == oldHandle then
          status = 'already-equipped'
        else
          local value = raw
          if kind == 'armor' then value = r.id elseif kind == 'talisman' then value = (layout.talismanFormat == 'handle') and pick.handle or r.id end
          written[#written + 1] = { index = index, oldHandle = oldHandle, oldValue = oldValue }
          assert(writeInteger(playerData + layout.handleBase + 4 * index, s32(pick.handle)), 'handle write failed')
          assert(writeInteger(playerData + layout.idBase + 4 * index, s32(value)), 'id write failed')
          assert(u32(readInteger(playerData + layout.handleBase + 4 * index)) == pick.handle, 'handle readback mismatch')
          assert(u32(readInteger(playerData + layout.idBase + 4 * index)) == value, 'id readback mismatch')
          if oldHandle then used[oldHandle] = nil end
          used[pick.handle] = index
          status = 'equipped'
        end
      end
      results[#results + 1] = { slot = r.slot, id = r.id, status = status }
    end
  end)
  if not ok then
    rollback()
    error(tostring(err) .. '; equipment rolled back')
  end
  return results
end

return M
