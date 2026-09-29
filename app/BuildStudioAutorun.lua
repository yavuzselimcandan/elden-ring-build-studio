-- Opt-in bootstrap and persistent request listener. Ordinary CE launches do nothing.
local root = 'C:/Users/YAVUZ-PC/Documents/Codex/2026-09-06/referenced-chatgpt-conversation-this-is-an/build_configurator'
local lastRequest = ''
local function text(path)
  local f = io.open(path, 'r'); if not f then return nil end
  local v = f:read('*a'); f:close(); return v
end
local priorResult = text(root .. '/runtime/result.txt')
if priorResult and (priorResult:match('requestId=[%w]+[\r\n]+OK:') or priorResult:match('requestId=[%w]+[\r\n]+ERROR:')) then
  lastRequest = priorResult:match('requestId=([%w]+)') or ''
end
local function runRequest()
  local probe = 'process-absent'
  local pid = getProcessIDFromProcessName('eldenring.exe')
  if pid then
    local ok = pcall(function() openProcess(pid); assert(readSmallInteger('eldenring.exe') == 0x5A4D) end)
    probe = ok and 'probe-ok' or 'probe-denied'
  end
  local h = io.open(root .. '/runtime/heartbeat.txt', 'w'); if h then h:write(tostring(os.time()) .. '|' .. tostring(getCheatEngineProcessID()) .. '|' .. tostring(pid or 0) .. '|' .. probe); h:close() end
  local request = text(root .. '/runtime/request.txt')
  if not request then return end
  local id = request:match('requestId=([^\r\n]+)')
  if not id or id == lastRequest then return end
  lastRequest = id
  local ok, err = pcall(function() assert(loadfile(root .. '/bridge.lua'))(root) end)
  if not ok then
    local f = io.open(root .. '/runtime/result.txt', 'w')
    if f then f:write('requestId=' .. id .. '\nERROR: ' .. tostring(err)); f:close() end
  end
end

local boot = root .. '/runtime/boot.flag'
local stamp = tonumber(text(boot) or '')
if stamp and math.abs(os.time() - stamp) < 120 then
  if os.rename(boot, boot .. '.claimed.' .. tostring(getCheatEngineProcessID()) .. '.' .. tostring(stamp)) then
    local timer = createTimer(nil, false)
    timer.Interval = 1000
    timer.OnTimer = runRequest
    timer.Enabled = true
  end
end
