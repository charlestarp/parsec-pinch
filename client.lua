-- parsec-pinch client.lua. Runs inside Hammerspoon on the LAPTOP (the one you connect from).
--
-- While one of the configured apps (Parsec by default) is frontmost, every pinch on the
-- trackpad is sent to the host Mac over UDP, where host.lua replays it as a real magnify
-- gesture at the cursor. If no host answers the pings, it falls back to sending zoom keys
-- (= and - by default), which Parsec does carry.
--
-- Ctrl+Alt+Cmd+Z toggles it. `parsecPinch.status()` in the Hammerspoon console shows state.
--
-- Set and forget: the socket is rebuilt on wake and whenever the host goes quiet, the event
-- tap is restarted if macOS ever disables it, and every callback is wrapped so one error
-- can never take the whole thing down.

local cfg = ...
local M = { sent = 0, rebuilt = 0, tapRestarts = 0, lastMode = "idle", enabled = true }

local ACK_TTL = 15
local types = hs.eventtap.event.types
local lastAck = {}
local lastRebuild = 0
local inGesture, endTimer, acc = false, nil, 0

local appSet = {}
for _, id in ipairs(cfg.apps) do appSet[id] = true end

local function targetIsFront()
  local app = hs.application.frontmostApplication()
  return app ~= nil and appSet[app:bundleID() or ""] == true
end

local function onData(data, addr)
  if data == cfg.token .. " A" then
    local a = hs.socket.udp.parseAddress(addr)
    if a then lastAck[a.host] = hs.timer.secondsSinceEpoch() end
  end
end

-- The UDP socket silently dies across a lid close or sleep, so it is rebuilt on wake
-- and whenever a host that used to answer has gone quiet.
local function openSocket()
  if M.sock then pcall(function() M.sock:close() end) end
  M.sock = hs.socket.udp.new(onData)
  M.sock:listen(0)
  M.sock:receive()
  M.rebuilt = M.rebuilt + 1
  lastRebuild = hs.timer.secondsSinceEpoch()
end
openSocket()

local function send(msg, host)
  local ok = pcall(function() M.sock:send(cfg.token .. " " .. msg, host, cfg.port) end)
  if ok then M.sent = M.sent + 1 end
end

function M.bestHost()
  local now, best, bestT = hs.timer.secondsSinceEpoch(), nil, 0
  for h, t in pairs(lastAck) do
    if now - t < ACK_TTL and t > bestT then best, bestT = h, t end
  end
  return best
end

local function newestAck()
  local best = 0
  for _, t in pairs(lastAck) do if t > best then best = t end end
  return best
end

local function ping()
  local now = hs.timer.secondsSinceEpoch()
  local seen = newestAck()
  if seen > 0 and now - seen > ACK_TTL and now - lastRebuild > 30 then openSocket() end
  for _, h in ipairs(cfg.hosts or {}) do send("P", h) end
end
M.pinger = hs.timer.doEvery(5, function() pcall(ping) end)
pcall(ping)

M.wakeWatcher = hs.caffeinate.watcher.new(function(e)
  if e == hs.caffeinate.watcher.systemDidWake or e == hs.caffeinate.watcher.screensDidWake then
    pcall(openSocket); pcall(ping)
  end
end)
M.wakeWatcher:start()

local function endGesture(host)
  if inGesture then send("E", host); inGesture = false end
end

local KEY_STEP = 0.06
local function keysFallback(m)
  acc = acc + m
  while acc >= KEY_STEP do hs.eventtap.keyStroke({}, cfg.fallback_keys.zoom_in, 0); acc = acc - KEY_STEP end
  while acc <= -KEY_STEP do hs.eventtap.keyStroke({}, cfg.fallback_keys.zoom_out, 0); acc = acc + KEY_STEP end
end

local function handle(e)
  if not M.enabled then return false end
  if e:getType(true) ~= types.magnify then return false end
  if not targetIsFront() then acc = 0; return false end

  local d = e:getTouchDetails()
  local m = d and d.magnification
  if not m then return false end

  local host = M.bestHost()
  if host then
    M.lastMode = "gesture via " .. host
    if not inGesture then send("B", host); inGesture = true end
    send(string.format("M %.5f", m * cfg.scale), host)
    if endTimer then endTimer:stop() end
    endTimer = hs.timer.doAfter(0.15, function() pcall(endGesture, host) end)
  elseif cfg.fallback then
    M.lastMode = "keys (no host answering)"
    keysFallback(m)
  else
    M.lastMode = "no host answering"
    return false
  end
  return true -- swallow the local pinch so the remote desktop window itself does not react
end

M.tap = hs.eventtap.new({ types.gesture }, function(e)
  local ok, res = pcall(handle, e)
  if not ok then print("parsec-pinch client: " .. tostring(res)); return false end
  return res
end)

local function startTap()
  if hs.accessibilityState() then
    M.tap:start()
    return M.tap:isEnabled()
  end
  return false
end

if startTap() then
  hs.alert.show("parsec-pinch ready")
else
  hs.accessibilityState(true) -- opens the permission prompt
  M.retry = hs.timer.doEvery(3, function()
    if startTap() then hs.alert.show("parsec-pinch ready"); M.retry:stop() end
  end)
end

-- macOS disables an event tap it thinks is slow. Put it back.
M.tapWatchdog = hs.timer.doEvery(10, function()
  if hs.accessibilityState() and not M.tap:isEnabled() then
    M.tap:start()
    if M.tap:isEnabled() then M.tapRestarts = M.tapRestarts + 1 end
  end
end)

hs.hotkey.bind(cfg.toggle_hotkey.mods, cfg.toggle_hotkey.key, function()
  M.enabled = not M.enabled
  hs.alert.show("parsec-pinch: " .. (M.enabled and "on" or "off"))
end)

function M.status()
  local now = hs.timer.secondsSinceEpoch()
  local acks = {}
  for h, t in pairs(lastAck) do acks[#acks + 1] = string.format("%s %.0fs ago", h, now - t) end
  return string.format("role=client enabled=%s tap=%s accessibility=%s host=%s mode=%s sent=%d rebuilt=%d tapRestarts=%d acks=[%s]",
    tostring(M.enabled), tostring(M.tap:isEnabled()), tostring(hs.accessibilityState()),
    tostring(M.bestHost()), M.lastMode, M.sent, M.rebuilt, M.tapRestarts, table.concat(acks, ", "))
end

print("parsec-pinch client loaded")
return M
