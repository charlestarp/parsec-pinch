-- parsec-pinch host.lua. Runs inside Hammerspoon on the REMOTE Mac (the one you connect to).
--
-- Listens for pinch packets from the client and replays each one as a native macOS
-- magnify gesture at the cursor. Any app that answers a trackpad pinch (Premiere, Final Cut,
-- Safari, Preview, Maps...) gets the real thing.
--
-- Wire format, one UDP packet each:
--   "<token> B"          gesture began
--   "<token> M <delta>"  magnification delta, same units as NSEvent.magnification
--   "<token> E"          gesture ended
--   "<token> P"          ping, answered with "<token> A"
--
-- CGEvent gesture fields (from Hammerspoon's TouchEvents.c and Apple's IOHIDEventTypes.h):
--   110 = subtype (8 is magnify), 113 = magnification (float), 132 = phase (1 began, 2 changed, 4 ended).
-- Hammerspoon's newGesture only writes began and ended, so each delta is created as "began"
-- and its phase is patched to "changed" with setProperty(132, 2).
--
-- Set and forget: the listener is rebuilt on wake, and a loopback probe every 30 seconds
-- rebuilds it if it has silently died.

local cfg = ...
local M = { received = 0, lastFrom = nil, rebuilt = 0, probeFailures = 0 }

local ev = hs.eventtap.event
local PHASE_FIELD, PHASE_CHANGED = 132, 2
local inGesture = false

local function post(kind, mag, changed)
  local ok, e = pcall(ev.newGesture, kind, mag)
  if not ok or not e then return end
  if changed then pcall(e.setProperty, e, PHASE_FIELD, PHASE_CHANGED) end
  pcall(e.post, e)
end

function M.begin() post("beginMagnify", 0, false); inGesture = true end
function M.change(delta)
  if not inGesture then M.begin() end
  post("beginMagnify", delta, true)
end
function M.finish() post("endMagnify", 0, false); inGesture = false end

local function onData(data, addr)
  local ok, err = pcall(function()
    local tok, cmd, val = data:match("^(%S+)%s+(%S)%s*(%S*)")
    if tok ~= cfg.token then return end
    M.received = M.received + 1
    local a = hs.socket.udp.parseAddress(addr)
    if a then M.lastFrom = a.host end
    if cmd == "P" then
      if a then M.sock:send(cfg.token .. " A", a.host, a.port) end
    elseif cmd == "B" then M.begin()
    elseif cmd == "M" then M.change(tonumber(val) or 0)
    elseif cmd == "E" then M.finish()
    end
  end)
  if not ok then print("parsec-pinch host: " .. tostring(err)) end
end

local function openListener()
  if M.sock then pcall(function() M.sock:close() end) end
  M.sock = hs.socket.udp.new(onData)
  if M.sock:listen(cfg.port) then
    M.sock:receive()
    M.rebuilt = M.rebuilt + 1
    M.listening = true
    print("parsec-pinch host listening on udp " .. cfg.port)
  else
    M.listening = false
    print("parsec-pinch host: could not bind udp " .. cfg.port .. ", will retry")
  end
end
openListener()

-- Rebuild after sleep.
M.wakeWatcher = hs.caffeinate.watcher.new(function(e)
  if e == hs.caffeinate.watcher.systemDidWake or e == hs.caffeinate.watcher.screensDidWake then
    openListener()
  end
end)
M.wakeWatcher:start()

-- Loopback probe: ping ourselves every 30s. No answer in 5s means the socket is dead, rebuild it.
local probeAnswered = false
M.probe = hs.socket.udp.new(function(data)
  if data == cfg.token .. " A" then probeAnswered = true end
end)
M.probe:listen(0)
M.probe:receive()

M.watchdog = hs.timer.doEvery(30, function()
  if not M.listening then openListener(); return end
  probeAnswered = false
  pcall(function() M.probe:send(cfg.token .. " P", "127.0.0.1", cfg.port) end)
  M.probeCheck = hs.timer.doAfter(5, function()
    if not probeAnswered then
      M.probeFailures = M.probeFailures + 1
      print("parsec-pinch host: loopback probe failed, rebuilding listener")
      openListener()
      pcall(function() M.probe:close() end)
      M.probe = hs.socket.udp.new(function(data) if data == cfg.token .. " A" then probeAnswered = true end end)
      M.probe:listen(0); M.probe:receive()
    end
  end)
end)

-- Accessibility: gesture replay needs it. Ask once, keep checking.
if not hs.accessibilityState() then
  hs.accessibilityState(true)
  M.axTimer = hs.timer.doEvery(5, function()
    if hs.accessibilityState() then hs.alert.show("parsec-pinch host ready"); M.axTimer:stop() end
  end)
else
  hs.alert.show("parsec-pinch host ready")
end

function M.status()
  return string.format("role=host port=%d listening=%s received=%d lastFrom=%s rebuilt=%d probeFailures=%d accessibility=%s",
    cfg.port, tostring(M.listening), M.received, tostring(M.lastFrom), M.rebuilt, M.probeFailures, tostring(hs.accessibilityState()))
end

return M
