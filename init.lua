-- parsec-pinch entry point. Loaded from ~/.hammerspoon/init.lua by install.sh.
-- Reads ~/.hammerspoon/parsec-pinch-config.lua and starts the client or the host.
-- Everything is wrapped so a bad config or a bug shows a message instead of breaking Hammerspoon.

local home = os.getenv("HOME")
local dir = home .. "/.hammerspoon/parsec-pinch"
local configPath = home .. "/.hammerspoon/parsec-pinch-config.lua"

local function fail(msg)
  print("parsec-pinch: " .. msg)
  hs.alert.show("parsec-pinch: " .. msg, 6)
  return nil
end

local ok, cfg = pcall(dofile, configPath)
if not ok or type(cfg) ~= "table" then
  return fail("no readable config at ~/.hammerspoon/parsec-pinch-config.lua")
end

cfg.port = tonumber(cfg.port) or 47801
cfg.token = cfg.token or "change-me"
cfg.scale = tonumber(cfg.scale) or 1.0
cfg.apps = cfg.apps or { "tv.parsec.www" }
cfg.hosts = cfg.hosts or {}
if cfg.fallback == nil then cfg.fallback = true end
cfg.fallback_keys = cfg.fallback_keys or { zoom_in = "=", zoom_out = "-" }
cfg.toggle_hotkey = cfg.toggle_hotkey or { mods = { "ctrl", "alt", "cmd" }, key = "z" }

pcall(hs.autoLaunch, true) -- come back after a reboot or login

local file
if cfg.role == "host" then file = dir .. "/host.lua"
elseif cfg.role == "client" then file = dir .. "/client.lua"
else return fail("config role must be \"client\" or \"host\"") end

local chunk, err = loadfile(file)
if not chunk then return fail("cannot load " .. file .. ": " .. tostring(err)) end
local ran, result = pcall(chunk, cfg)
if not ran then return fail("failed to start: " .. tostring(result)) end
return result
