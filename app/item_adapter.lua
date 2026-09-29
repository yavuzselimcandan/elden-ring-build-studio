-- Review-only item adapter. Not loaded by autorun and never grants items yet.
-- CT 1337092247's relevant vetted ABI (Hexinton v8.0.1):
--   itembuffer: dq 0,0,0,0,F00006AE00000001,0000000000000001,
--                    FFFFFFFFFFFFFFFF,FFFFFFFF00000000,
--                    FFFFFFFFFFFFFFFF,FFFFFFFF00000000
--   itemgib:
--     mov rdx,rcx
--     cmp rdx,10000
--     jge itemgib1
--     lea rdx,[itembuffer+20]
--   itemgib1:
--     sub rsp,28
--     xor r9,r9
--     lea r8,[itembuffer]
--     mov rax,InventoryAccessor+19
--     mov rcx,InventoryAccessor+1D
--     mov eax,[rax]
--     cdqe
--     add rcx,rax
--     mov rcx,[rcx]
--     cmp rcx,10000
--     jl exit
--     call AddItemFunc
--   exit: add rsp,28; ret

local CATEGORY = { weapon=0, armor=1, talisman=2, goods=4, ash=8 }

-- Exact CT conversion table, indexed by ItemGib.CEComboBox2.ItemIndex.
-- The form's ComboBox2 Items are serialized in the CT form blob; they are
-- not proven equal to memory record 22032404, so raw Ash IDs stay rejected.
local ASH_ENGINE_IDS = {
  -1,2147543848,2147548648,2147523748,2147513748,2147548848,2147505748,
  2147506048,2147494448,2147563748,2147504048,2147549048,2147505448,
  2147505548,2147514148,2147494148,2147506348,2147544348,2147543648,
  2147494848,2147504848,2147524048,2147553648,2147504348,2147534148,
  2147505048,2147495248,2147503648,2147503948,2147504948,2147514348,
  2147534348,2147543948,2147504548,2147534248,2147534548,2147533748,
  2147553848,2147503848,2147493748,2147533948,2147504148,2147534048,
  2147505348,2147493648,2147495448,2147523848,2147514548,2147513848,
  2147506148,2147493848,2147495548,2147506448,2147504448,2147494948,
  2147563648,2147524248,2147563848,2147494548,2147543748,2147503748,
  2147544048,2147505848,2147544248,2147544148,2147513648,2147514448,
  2147524148,2147506248,2147493948,2147494748,2147495648,2147495148,
  2147494348,2147494248,2147495848,2147504648,2147533848,2147514248,
  2147495948,2147496048,2147514648,2147523648,2147505248,2147548948,
  2147495048,2147505648,2147553748,2147548748,2147534448,2147568648,
  2147494648
}

function ResolveAshConversionIndex(index)
  index = tonumber(index)
  if not index or index % 1 ~= 0 or index < 0 or index >= #ASH_ENGINE_IDS then
    return nil, 'Ash ComboBox index has no ConvertAshofWarTable value'
  end
  return ASH_ENGINE_IDS[index + 1]
end

function AshCatalogSelfTest()
  assert(ResolveAshConversionIndex(0) == -1, 'Ash conversion first row mismatch')
  assert(ResolveAshConversionIndex(91) == 2147494648, 'Ash conversion last row mismatch')
  assert(ResolveAshConversionIndex(92) == nil, 'unmapped Ash index must remain unsupported')
  assert(#ASH_ENGINE_IDS == 92, 'Ash conversion table length mismatch')
  return true
end

function PreviewItemGrant(item, inventory)
  assert(type(item) == 'table', 'item request must be a table')
  local category = CATEGORY[item.category]
  assert(category, 'unsupported item category')
  local id = tonumber(item.itemId); local upgrade = tonumber(item.upgrade or 0); local quantity = tonumber(item.quantity or 1)
  assert(id and id > 0 and id <= 0x0fffffff and id % 1 == 0, 'invalid item id')
  assert(upgrade and upgrade >= 0 and upgrade <= 25 and upgrade % 1 == 0, 'invalid upgrade')
  assert(quantity and quantity >= 1 and quantity <= 999 and quantity % 1 == 0, 'invalid quantity')
  if item.category ~= 'weapon' then assert(upgrade == 0, 'upgrade is only valid for weapons') end
  assert(item.ashOfWarId == nil, 'Ash attachment is not supported')
  assert(item.category == 'weapon' or item.category == 'armor' or item.category == 'talisman' or item.category == 'goods' or item.category == 'ash', 'item category is not supported')
  local encoded = id + upgrade + category * 0x10000000
  local existing = 0
  if inventory then
    for _, row in ipairs(inventory) do if row.rawID == encoded and row.quantity > 0 then existing = existing + row.quantity end end
  end
  return { category=category, itemId=id, upgrade=upgrade, quantity=quantity, encodedId=encoded, existing=existing, writes=false }
end

function BuildItemBuffer(item)
  local p=PreviewItemGrant(item, {})
  return { {offset=0x24,value=p.encodedId}, {offset=0x28,value=p.quantity}, {offset=0x30,value=-1}, packed=p.encodedId }
end

function InstallItemGib()
  assert(not _itemGibInstalled, 'item adapter already installed')
  local function find(pattern)
    local s=createMemScan(); local b=getAddress('eldenring.exe')
    s.firstScan(soExactValue,vtByteArray,nil,pattern,nil,b,b+getModuleSize('eldenring.exe'),'+X',fsmNotAligned,'1',true,false,false,false); s.waitTillDone()
    local f=createFoundList(s); f.initialize(); assert(f.Count==1,'item signature is not unique'); local a=tonumber(f.Address[0],16); f.destroy(); s.destroy(); return a
  end
  local inv=find('44 8B 61 1C 41 8B FC C1 EF 07 40 80 E7 01 41 C1 EC 08 41 80 E4 01 48 8B 0D')
  local add=find('40 55 56 57 41 54 41 55 41 56 41 57 48 8D AC 24 70 FF FF FF 48 81 EC 90 01 00 00 48 C7 45 C8 FE FF FF FF 48 89 9C 24 D8 01 00 00 48 8B 05')
  assert(autoAssemble(string.format([[
alloc(itembuffer,4096,eldenring.exe)
alloc(itemgib,256,eldenring.exe)
registersymbol(itembuffer)
registersymbol(itemgib)
label(itemgib1)
label(exit)
itembuffer:
dq 0,0,0,0,F00006AE00000001,0000000000000001,FFFFFFFFFFFFFFFF,FFFFFFFF00000000,FFFFFFFFFFFFFFFF,FFFFFFFF00000000
itemgib:
mov rdx,rcx
cmp rdx,10000
jge itemgib1
lea rdx,[itembuffer+20]
itemgib1:
sub rsp,28
xor r9,r9
lea r8,[itembuffer]
mov rax,%X+19
mov rcx,%X+1D
mov eax,[rax]
cdqe
add rcx,rax
mov rcx,[rcx]
cmp rcx,10000
jl exit
call %X
exit:
add rsp,28
ret
]],inv,inv,add)),'itemgib install failed')
  _itemGibInstalled=true
  return inv,add
end

function GrantItem(item, inventory, armed)
  assert(armed == true, 'item grant requires explicit review arm')
  assert(type(inventory) == 'table' and type(inventory.read) == 'function','captured inventory reader required')
  local preview=PreviewItemGrant(item, inventory.read()); assert(preview.existing==0,'dedup refused: item already present')
  assert(_itemGibInstalled,'install item adapter first')
  local buffer=BuildItemBuffer(item)
  for _,field in ipairs(buffer) do writeInteger('itembuffer+' .. string.format('%X',field.offset),field.value) end
  local ledger={request=preview,packed=buffer.packed,before=0,status='call-pending'}
  executeCode('itemgib',0)
  local after=inventory.read(); local delta=0
  for _,row in ipairs(after) do if row.rawID==buffer.packed then delta=delta+row.quantity end end
  assert(delta>=preview.quantity,'item grant outcome unknown; do not retry')
  ledger.after=delta; ledger.status='verified'; return ledger
end
