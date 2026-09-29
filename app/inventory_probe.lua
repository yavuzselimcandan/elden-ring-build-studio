-- REVIEW ONLY: never loaded by autorun. No hook is activated by this file.
-- Live bytes at InventoryAccessor (game 2.2.0.0):
--   8B C3 2B C1 48 8D 0C 40 48 8B 47 38 48 8D 0C C8 ...
-- The observed code computes 3*(ebx-ecx), loads [rdi+38], then uses
-- lea rcx,[rax+rcx*8]. Therefore the entry stride is 3*8 = 0x18.

local function scan(pattern)
  local s=createMemScan(); local b=getAddress('eldenring.exe')
  s.firstScan(soExactValue,vtByteArray,nil,pattern,nil,b,b+getModuleSize('eldenring.exe'),'+X',fsmNotAligned,'1',true,false,false,false)
  s.waitTillDone(); local f=createFoundList(s); f.initialize(); assert(f.Count==1,'InventoryAccessor is not unique')
  local a=tonumber(f.Address[0],16); f.destroy(); s.destroy(); return a
end

function InstallInventoryCapture(address)
  if _inventoryCaptureAddress then
    local currentPid=getProcessIDFromProcessName('eldenring.exe')
    if currentPid ~= _inventoryCapturePid then _inventoryCaptureAddress=nil; _inventoryCapturePid=nil
    else local live=readBytes(_inventoryCaptureAddress,8,true); if table.concat(live,',')=='139,195,43,193,72,141,12,64' then _inventoryCaptureAddress=nil else error('capture already installed') end end
  end
  address=address or scan('8B C3 2B C1 48 8D 0C ?? 48 8B 47 38 48 8D 0C ??')
  local original=readBytes(address,8,true)
  assert(table.concat(original,',')=='139,195,43,193,72,141,12,64','InventoryAccessor bytes changed')
  assert(getProcessIDFromProcessName('eldenring.exe') and getProcessIDFromProcessName('eldenring.exe')==_inventoryCapturePid or not _inventoryCapturePid,'game PID changed before install')
  registerSymbol('InventoryAccessorAddr',address)
  assert(autoAssemble([[
alloc(CaptureHook,64,InventoryAccessorAddr)
alloc(CaptureRdi,8,InventoryAccessorAddr)
registersymbol(CaptureHook)
registersymbol(CaptureRdi)
CaptureRdi:
dq 0
CaptureHook:
db 8B C3 2B C1 48 8D 0C 40
mov [CaptureRdi],rdi
jmp InventoryAccessorAddr+8
InventoryAccessorAddr:
jmp CaptureHook
nop
nop
nop
]]),'capture hook install failed')
  _inventoryCaptureAddress=address
  _inventoryCapturePid=getProcessIDFromProcessName('eldenring.exe')
  return address
end

function ReadInventoryCapture(address)
  local rdi=readQword('CaptureRdi'); assert(rdi and rdi>0,'capture did not run')
  _inventoryLastPid=getProcessIDFromProcessName('eldenring.exe')
  _inventoryLastRdi=rdi
  local base=readQword(rdi+0x38); _inventoryLastBase=base; assert(base and base>0,'inventory base unavailable')
  local count=readInteger(base-8); _inventoryLastCount=count; assert(count and count>=0 and count<=2688,'inventory count out of bounds')
  local rows={}; for i=0,count-1 do
    local entry=base+i*0x18; local raw=readInteger(entry+4); local quantity=readInteger(entry+8)
    assert(raw and raw>=0 and quantity and quantity>=0 and quantity<=9999,'inventory entry out of bounds')
    rows[#rows+1]={rawID=raw,quantity=quantity}
  end
  return rdi,base,count,rows
end

function RestoreInventoryCapture(address)
  assert(getProcessIDFromProcessName('eldenring.exe')==_inventoryCapturePid,'game PID changed before restore')
  assert(table.concat(readBytes(address,8,true),',') ~= '139,195,43,193,72,141,12,64','hook site already restored')
  writeBytes(address,139,195,43,193,72,141,12,64)
  assert(table.concat(readBytes(address,8,true),',')=='139,195,43,193,72,141,12,64','restore verification failed')
  unregisterSymbol('CaptureHook'); unregisterSymbol('CaptureRdi')
  _inventoryCaptureAddress=nil
  _inventoryCapturePid=nil
end
