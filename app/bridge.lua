-- Fail-closed runtime probe.  Writes stay disabled until the table's remote
-- call ABI and readback path are verified against the running game build.
local root = ...

local function put(name, value)
  local f = assert(io.open(root .. '/runtime/' .. name, 'w'))
  f:write(value)
  f:close()
end

local function parse_request()
  local f = assert(io.open(root .. '/runtime/request.txt', 'r'))
  local version, mode, requestId, targetId, items, stats = false, 'probe', nil, nil, {}, {}
  for line in f:lines() do
    local key, value = line:match('^(%w+)=(.*)$')
    if key == 'version' then
      version = value == '1'
    elseif key == 'mode' then
      mode = value
    elseif key == 'requestId' then
      requestId = value
    elseif key == 'targetId' then
      targetId = tonumber(value)
    elseif key == 'item' then
      local category, id, upgrade, quantity = value:match('^([^|]+)|(%d+)|(%d+)|(%d+)$')
      assert(category and id and upgrade and quantity, 'invalid item request')
      assert(category == 'weapon' or category == 'armor' or category == 'talisman' or category == 'goods' or category == 'ash', 'unsupported item category')
      items[#items + 1] = { category = category, id = tonumber(id), upgrade = tonumber(upgrade), quantity = tonumber(quantity) }
    elseif key == 'stat' then
      local name, number = value:match('^(%a+)|(%d+)$')
      assert(name and number and ({vig=true,mind=true,['end']=true,str=true,dex=true,['int']=true,fai=true,arc=true})[name], 'invalid stat request')
      number = tonumber(number)
      assert(number >= 1 and number <= 99, 'stat out of range')
      stats[name] = number
    end
  end
  f:close()
  assert(version, 'unsupported request version')
  assert(requestId and requestId:match('^%w+$'), 'missing request id')
  assert(mode == 'probe' or mode == 'stats' or mode == 'build' or mode == 'inventory_probe' or mode == 'inventory_read' or mode == 'equip_probe' or mode == 'equip_head_trial' or mode == 'equip_head_restore' or mode == 'armor_test' or mode == 'spell_test', 'unsupported request mode')
  return requestId, mode, items, stats, targetId
end

local function scan(pattern)
  local s = createMemScan()
  local base = getAddress('eldenring.exe')
  s.firstScan(soExactValue, vtByteArray, nil, pattern, nil, base, base + getModuleSize('eldenring.exe'), '+X', fsmNotAligned, '1', true, false, false, false)
  s.waitTillDone()
  local found = createFoundList(s); found.initialize()
  local n = found.Count; local address = n == 1 and tonumber(found.Address[0], 16) or nil
  found.destroy(); s.destroy(); assert(address, 'signature not unique/found (' .. n .. ')')
  return address
end
local function rip(pattern)
  local address = scan(pattern)
  return address + 7 + readInteger(address + 3, true)
end
local function ensureInventory(pid)
  if _inventoryLastPid == pid and _inventoryLastRdi and _inventoryLastBase and readQword(_inventoryLastRdi + 0x38) == _inventoryLastBase then return end
  assert(loadfile(root .. '/inventory_probe.lua'))()
  local site=scan('8B C3 2B C1 48 8D 0C ?? 48 8B 47 ?? 48 8D 0C ?? E8 ?? ?? ?? ?? 85 C0 0F 45 DE 48 8B 7C 24 ?? 8B C3 48 8B 5C 24 ?? 48 83 C4 20 5E C3')
  InstallInventoryCapture(site);local deadline=(getTickCount64 and getTickCount64() or os.time()*1000)+10000;local ok,err=false,nil
  while (getTickCount64 and getTickCount64() or os.time()*1000)<deadline do local good,a,b,c,d=pcall(ReadInventoryCapture,site);if good then ok=true;break else err=a;sleep(100)end end
  local restored,rerr=pcall(RestoreInventoryCapture,site);assert(restored,rerr);assert(ok,'open inventory and retry: '..tostring(err));assert(getProcessIDFromProcessName('eldenring.exe')==pid,'game PID changed during capture')
end

getMainForm().hide()
local requestText = io.open(root .. '/runtime/request.txt', 'r')
local requestId = requestText and requestText:read('*a'):match('requestId=([%w]+)') or 'unknown'
if requestText then requestText:close() end
local ok, err = pcall(function()
  local parsedRequestId, mode, items, stats, targetId = parse_request()
  requestId = parsedRequestId
  assert(not getProcessIDFromProcessName('EasyAntiCheat_EOS.exe'), 'EAC running: offline session required')
  local pid = getProcessIDFromProcessName('eldenring.exe')
  assert(pid, 'Waiting for eldenring.exe')
  openProcess(pid)
  assert(readSmallInteger('eldenring.exe') == 0x5A4D, 'Cannot read game process')
  local gd = rip('48 8B 05 ?? ?? ?? ?? 48 85 C0 74 05 48 8B 40 58 C3 C3')
  local manager = assert(readQword(gd), 'GameDataMan is null')
  local player = assert(readQword(manager + 8), 'Character is not loaded')
  local names = {'vig','mind','end','str','dex','int','fai','arc'}
  local offsets = {0x3c,0x40,0x44,0x48,0x4c,0x50,0x54,0x58}
  local values = {}
  for i = 1, #names do
    local value = assert(readInteger(player + offsets[i]), 'invalid character stat')
    assert(value >= 1 and value <= 99, 'character stat out of range')
    values[#values + 1] = names[i] .. '=' .. value
  end
  local oldLevel = assert(readInteger(player + 0x68), 'invalid level')
  values[#values + 1] = 'level=' .. tostring(oldLevel)
  put('probe.txt', table.concat(values, '\n'))
  if mode == 'equip_probe' then
    ensureInventory(pid)
    assert(_inventoryLastPid and getProcessIDFromProcessName('eldenring.exe') == _inventoryLastPid, 'fresh inventory capture required')
    assert(_inventoryLastRdi and _inventoryLastBase and readQword(_inventoryLastRdi + 0x38) == _inventoryLastBase, 'inventory pointer changed')
    local equip=assert(loadfile(root..'/equip_probe.lua'))();local count=readInteger(_inventoryLastBase-8);assert(count and count>=0 and count<=2688,'inventory capacity invalid');local result=equip.capture(gd,_inventoryLastBase,count,root..'/runtime/equip-probe.txt');put('result.txt','requestId='..requestId..'\nOK: equip-probe-read-only; matches='..result.matches);return
  end
  if mode == 'equip_head_trial' then
    ensureInventory(pid)
    assert(_inventoryLastPid == pid and _inventoryLastBase, 'fresh inventory capture required')
    local count=readInteger(_inventoryLastBase-8);assert(count and count>=0 and count<=2688,'inventory capacity invalid')
    local haveHead, haveTrial=false,false
    for i=0,count-1 do local e=_inventoryLastBase+i*0x18;local raw=readInteger(e+4);local q=readInteger(e+8);if q and q>0 then if raw==269536456 then haveHead=true elseif raw==269115456 then haveTrial=true end end end
    assert(haveHead and haveTrial, 'both head inventory records required')
    local slot=player+0x3C8;local old=assert(readInteger(slot),'head slot unreadable');assert(old==1101000,'manual validation baseline changed; refusing trial')
    put('equip-head-trial.txt','requestId='..requestId..'\npid='..pid..'\nplayerGameData='..player..'\nslot=0x3C8\nold='..old..'\nrequested=680000\nbackup-only=true')
    assert(getProcessIDFromProcessName('eldenring.exe')==pid and readQword(manager+8)==player,'character pointer changed before head write')
    assert(writeInteger(slot,680000),'head trial write failed');assert(readInteger(slot)==680000,'head trial readback failed')
    put('result.txt','requestId='..requestId..'\nOK: HEAD_TRIAL_READBACK; visual-confirmation-required; stats=false; save-backup=not-created; memory-only-trial=true')
    return
  end
  if mode == 'equip_head_restore' then
    assert(targetId == 680000 or targetId == 1101000, 'restore target must be an explicitly approved head ID')
    local slot=player+0x3C8;local before=assert(readInteger(slot),'head slot unreadable')
    assert(getProcessIDFromProcessName('eldenring.exe')==pid and readQword(manager+8)==player,'character pointer changed before restore')
    assert(writeInteger(slot,targetId),'head restore failed');assert(readInteger(slot)==targetId,'head restore readback failed')
    put('result.txt','requestId='..requestId..'\nOK: HEAD_RESTORE_READBACK; value='..targetId..'; previous='..before..'; save-write=false')
    return
  end
  assert(#items > 0 or next(stats) or mode == 'inventory_probe' or mode == 'inventory_read' or mode == 'equip_probe', 'empty build request')
  if mode == 'inventory_read' then
    if not _inventoryLastPid then
      local sf=io.open(root .. '/runtime/inventory-probe.txt','r'); local raw=sf and sf:read('*a') or ''; if sf then sf:close() end
      _inventoryLastPid=tonumber(raw:match('lastPid=(%d+)')); _inventoryLastRdi=tonumber(raw:match('lastRdi=(%d+)')); _inventoryLastBase=tonumber(raw:match('lastBase=(%d+)'))
      if not _inventoryLastPid then local hf=io.open(root .. '/runtime/heartbeat.txt','r'); local h=hf and hf:read('*a') or ''; if hf then hf:close() end; _inventoryLastPid=tonumber(h:match('^%d+|%d+|(%d+)')) end
    end
    assert(_inventoryLastPid and getProcessIDFromProcessName('eldenring.exe') == _inventoryLastPid, 'captured inventory belongs to another game PID')
    assert(_inventoryLastRdi and _inventoryLastBase, 'no captured inventory pointers')
    assert(readQword(_inventoryLastRdi + 0x38) == _inventoryLastBase, 'inventory pointer changed')
    local count = readInteger(_inventoryLastBase - 8); assert(count and count >= 0 and count <= 2688, 'inventory capacity invalid')
    local valid, empty, sample = 0, 0, {}
    for i = 0, count - 1 do
      local entry = _inventoryLastBase + i * 0x18; local raw = readInteger(entry + 4); local quantity = readInteger(entry + 8)
      if raw == 0 or raw == -1 or quantity == 0 then empty = empty + 1
      elseif raw and quantity and quantity > 0 and quantity <= 9999 then valid = valid + 1; if #sample < 32 then sample[#sample + 1] = string.format('entry%d=rawID:%u,quantity:%u', i, raw, quantity) end end
    end
    put('inventory-read.txt', 'pid=' .. _inventoryLastPid .. '\nrdi=' .. _inventoryLastRdi .. '\nbase=' .. _inventoryLastBase .. '\ncount=' .. count .. '\nvalid=' .. valid .. '\nempty=' .. empty .. '\n' .. table.concat(sample, '\n'))
    put('result.txt', 'requestId=' .. requestId .. '\nOK: inventory-read-only; writes=false')
    return
  end
  if mode == 'build' then
    ensureInventory(pid)
    assert(_inventoryLastRdi and _inventoryLastBase and readQword(_inventoryLastRdi + 0x38) == _inventoryLastBase, 'inventory pointer changed')
    local count=readInteger(_inventoryLastBase-8);assert(count and count>=0 and count<=2688,'inventory capacity invalid')
    local rows={};for i=0,count-1 do local e=_inventoryLastBase+i*0x18;rows[#rows+1]={rawID=readInteger(e+4),quantity=readInteger(e+8)} end
    assert(loadfile(root..'/item_adapter.lua'))();if not _itemGibInstalled then InstallItemGib() end
    local ledger={requestId=requestId,items={}};put('build-ledger-'..requestId..'.txt','requestId='..requestId..'\nstatus=prepared')
    for _,item in ipairs(items) do
      assert(item.category and item.id and item.upgrade and item.quantity,'invalid typed item')
      local preview=PreviewItemGrant({category=item.category,itemId=item.id,upgrade=item.upgrade,quantity=item.quantity},rows);local deficit=math.max(0,item.quantity-preview.existing)
      if deficit>0 then
        local req={category=item.category,itemId=item.id,upgrade=item.upgrade,quantity=deficit};local buf=BuildItemBuffer(req);for _,field in ipairs(buf)do assert(writeInteger('itembuffer+'..string.format('%X',field.offset),field.value),'buffer write failed')end
        executeCode('itemgib',0);sleep(250);assert(readQword(_inventoryLastRdi+0x38)==_inventoryLastBase,'inventory pointer changed after grant');local freshCount=readInteger(_inventoryLastBase-8);assert(freshCount and freshCount>=0 and freshCount<=2688,'inventory capacity changed');local seen=0;for i=0,freshCount-1 do local e=_inventoryLastBase+i*0x18;if readInteger(e+4)==buf.packed then seen=seen+readInteger(e+8) end end;assert(seen>=item.quantity,'item readback delta missing');ledger.items[#ledger.items+1]={itemId=item.id,category=item.category,requested=item.quantity,applied=deficit,existing=preview.existing,verified=true}
      else ledger.items[#ledger.items+1]={itemId=item.id,category=item.category,requested=item.quantity,applied=0,existing=preview.existing,verified=true} end
    end
    local statsVerified=true;if next(stats) then local oldStats={};for i,name in ipairs(names)do oldStats[name]=readInteger(player+offsets[i]) end;assert(getProcessIDFromProcessName('eldenring.exe')==pid and readQword(manager+8)==player,'character changed before stats');for name,value in pairs(stats)do local index=({vig=1,mind=2,['end']=3,str=4,dex=5,['int']=6,fai=7,arc=8})[name];assert(index and writeInteger(player+offsets[index],value),'stat write failed')end;for i,name in ipairs(names)do assert(readInteger(player+offsets[i])==(stats[name] or oldStats[name]),'stat readback mismatch')end;assert(readInteger(player+0x68)==oldLevel,'level changed unexpectedly')end
    put('build-ledger-'..requestId..'.txt','requestId='..requestId..'\nstatus=verified\n'..table.concat((function()local x={};for _,v in ipairs(ledger.items)do x[#x+1]=string.format('item=%s,%s,requested=%d,applied=%d,existing=%d,verified=%s',v.category,v.itemId,v.requested,v.applied,v.existing,tostring(v.verified))end;return x end)(), '\n'))
    put('result.txt','requestId='..requestId..'\nOK: APPLIED build-verified; stats-verified='..tostring(statsVerified));return
  end
  if mode == 'armor_test' or mode == 'spell_test' then
    assert(_inventoryLastPid and getProcessIDFromProcessName('eldenring.exe') == _inventoryLastPid, 'inventory capture PID changed')
    assert(_inventoryLastRdi and _inventoryLastBase and readQword(_inventoryLastRdi + 0x38) == _inventoryLastBase, 'inventory pointer changed')
    local targets=mode == 'spell_test' and {{name=targetId==4120 and 'Gavel of Haima' or 'Cannon of Haima',itemId=targetId}} or {{name="Spellblade's Pointed Hat",itemId=130000},{name="Spellblade's Traveling Attire",itemId=130100},{name="Spellblade's Gloves",itemId=130200},{name="Spellblade's Trousers",itemId=130300}}
    assert(mode ~= 'spell_test' or targetId == 4120 or targetId == 4080,'explicit spell target required')
    assert(readQword(_inventoryLastRdi + 0x38) == _inventoryLastBase,'inventory pointer changed')
    local rows={};local count=readInteger(_inventoryLastBase-8);assert(count and count>=0 and count<=2688,'inventory capacity invalid')
    for i=0,count-1 do local e=_inventoryLastBase+i*0x18;rows[#rows+1]={rawID=readInteger(e+4),quantity=readInteger(e+8)} end
    local item_adapter=assert(loadfile(root..'/item_adapter.lua'));item_adapter();local chosen
    for _,t in ipairs(targets) do local raw=t.itemId+0x10000000;local have=false;for _,r in ipairs(rows)do if r.rawID==raw and r.quantity>0 then have=true end end;if not have then chosen=t;break end end
    assert(chosen,'all four target armor pieces already present')
    local category=mode == 'spell_test' and 'goods' or 'armor';local ledgerPath=mode == 'spell_test' and 'spell-ledger-'..requestId..'.txt' or 'armor-ledger.txt';put(ledgerPath,'requestId='..requestId..'\nname='..chosen.name..'\nitemId='..chosen.itemId..'\nstatus=prepared')
    if not _itemGibInstalled then InstallItemGib() end;local preview=PreviewItemGrant({category=category,itemId=chosen.itemId,upgrade=0,quantity=1},rows);local buf=BuildItemBuffer({category=category,itemId=chosen.itemId,upgrade=0,quantity=1});for _,field in ipairs(buf)do assert(writeInteger('itembuffer+'..string.format('%X',field.offset),field.value),'buffer write failed')end;executeCode('itemgib',0);sleep(250)
    local after=readInteger(_inventoryLastBase+0x24);assert(after,'inventory readback unavailable');local found=false;for i=0,count+64 do local e=_inventoryLastBase+i*0x18;local raw=readInteger(e+4);local q=readInteger(e+8);if raw==buf.packed and q>=1 then found=true end end;assert(found,'armor readback delta missing');put(ledgerPath,'requestId='..requestId..'\nname='..chosen.name..'\nitemId='..chosen.itemId..'\nstatus=verified\nquantity=1');put('result.txt','requestId='..requestId..'\nOK: '..(mode == 'spell_test' and 'spell-test-verified' or 'armor-test-verified')..'; writes=true');return
  end
  if mode == 'inventory_probe' then
    local inventory = scan('8B C3 2B C1 48 8D 0C ?? 48 8B 47 ?? 48 8D 0C ?? E8 ?? ?? ?? ?? 85 C0 0F 45 DE 48 8B 7C 24 ?? 8B C3 48 8B 5C 24 ?? 48 83 C4 20 5E C3')
    local bytes = readBytes(inventory, 8, true)
    local hex = {}; for i = 1, #bytes do hex[#hex + 1] = string.format('%02X', bytes[i]) end
    local following = readBytes(inventory, 32, true)
    local disassembly = {}; for i = 1, #following do disassembly[#disassembly + 1] = string.format('%02X', following[i]) end
    local itemgib = scan('40 55 56 57 41 54 41 55 41 56 41 57 48 8D AC 24 ?? ?? ?? ?? 48 81 EC ?? ?? ?? ?? 48 C7 45 C8 ?? ?? ?? ?? 48 89 9C 24 ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 ?? ?? ?? ?? 44 89 4C 24 ?? 4D 8B F8')
    local additem = itemgib
    local installed, capture, lastCaptureError
    local okHook, hookErr = pcall(function()
      assert(loadfile(root .. '/inventory_probe.lua'))()
      InstallInventoryCapture(inventory); installed = true
      local now = getTickCount64 or function() return os.time() * 1000 end
      local deadline = now() + 10000
      while now() < deadline do
        local okCapture, rdi, base, count, rows = pcall(ReadInventoryCapture, inventory)
        if okCapture then capture={rdi=rdi,base=base,count=count,rows=rows}; break end
        lastCaptureError = tostring(rdi)
        sleep(100)
      end
      assert(capture, 'inventory capture timed out; last=' .. tostring(lastCaptureError))
    end)
    local restoreOk, restoreErr = true, nil
    if installed then restoreOk, restoreErr = pcall(RestoreInventoryCapture, inventory) end
    local lines={'InventoryAccessor=' .. string.format('%X', inventory),'bytes=' .. table.concat(hex, ' '),'following32=' .. table.concat(disassembly, ' '),'ItemGib=' .. string.format('%X', itemgib),'AddItemFunc=' .. string.format('%X', additem),'lastPid=' .. tostring(_inventoryLastPid),'lastError=' .. tostring(lastCaptureError),'lastRdi=' .. tostring(_inventoryLastRdi),'lastBase=' .. tostring(_inventoryLastBase),'lastCount=' .. tostring(_inventoryLastCount)}
    if capture then lines[#lines+1]='rdi=' .. string.format('%X', capture.rdi); lines[#lines+1]='base=' .. string.format('%X', capture.base); lines[#lines+1]='count=' .. capture.count; for i,row in ipairs(capture.rows) do lines[#lines+1]=string.format('entry%d=rawID:%u,quantity:%u',i-1,row.rawID,row.quantity) end end
    lines[#lines+1]='writes=false;hook-restored=true'; put('inventory-probe.txt', table.concat(lines,'\n'))
    assert(restoreOk, tostring(restoreErr)); assert(okHook, tostring(hookErr))
    put('result.txt', 'requestId=' .. requestId .. '\nOK: inventory-capture-read-only; hook-restored=true')
    return
  end
  assert(#items == 0, 'item writes are not enabled')
  if mode == 'stats' then
    assert(next(stats), 'stats request is empty')
    local old = {}
    for i = 1, #names do old[names[i]] = readInteger(player + offsets[i]) end
    assert(getProcessIDFromProcessName('eldenring.exe') == pid, 'game PID changed before write')
    assert(readQword(gd) == manager and readQword(manager + 8) == player, 'character pointer changed before write')
    local okWrite, writeErr = pcall(function()
      for name, value in pairs(stats) do
        local index = ({vig=1,mind=2,['end']=3,str=4,dex=5,['int']=6,fai=7,arc=8})[name]
        assert(index, 'invalid stat')
        assert(writeInteger(player + offsets[index], value), 'stat write failed')
      end
      for i = 1, #names do
        local expected = stats[names[i]] or old[names[i]]
        assert(readInteger(player + offsets[i]) == expected, 'stat readback mismatch')
      end
      assert(readInteger(player + 0x68) == oldLevel, 'level changed unexpectedly')
    end)
    if not okWrite then
      for i = 1, #names do writeInteger(player + offsets[i], old[names[i]]) end
      for i = 1, #names do assert(readInteger(player + offsets[i]) == old[names[i]], 'rollback verification failed') end
      error(tostring(writeErr) .. '; rolled back')
    end
    assert(readInteger(player + 0x68) == oldLevel, 'level changed unexpectedly')
    put('result.txt', 'requestId=' .. requestId .. '\nOK: APPLIED stats-readback-verified; level-unchanged=true')
  else
    put('result.txt', 'requestId=' .. requestId .. '\nERROR: WRITE_DISABLED; read-only process probe succeeded; items=' .. #items .. '; stats=' .. tostring(next(stats) ~= nil) .. '; equipment=false; ashAttachment=false')
  end
end)
if not ok then
  put('result.txt', 'requestId=' .. requestId .. '\nERROR: ' .. tostring(err))
end
