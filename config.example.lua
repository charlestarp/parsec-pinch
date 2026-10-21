-- Copy to ~/.hammerspoon/parsec-pinch-config.lua (install.sh does this for you).
return {
  -- "host" on the Mac you connect TO. "client" on the laptop you connect FROM.
  role = "client",

  -- Client only: where the host Mac is. List every address it might have, the client uses
  -- whichever answers. Examples: its LAN address, its Tailscale address.
  hosts = { "192.0.2.10", "100.64.0.1" },

  -- Shared secret. Must be the same on both sides. install.sh generates one on the host.
  token = "change-me",

  -- UDP port. Same on both sides.
  port = 47801,

  -- Client only: multiply the pinch before sending. 1.0 feels like a local pinch.
  scale = 1.0,

  -- Client only: pinches are forwarded only while one of these apps is frontmost.
  -- Parsec is tv.parsec.www. Find another app's id with:
  --   osascript -e 'id of app "Splashtop Business"'
  apps = { "tv.parsec.www" },

  -- Client only: when no host answers, send zoom keys instead (Parsec carries keystrokes).
  fallback = true,
  fallback_keys = { zoom_in = "=", zoom_out = "-" },

  -- Client only: hotkey that turns forwarding on and off.
  toggle_hotkey = { mods = { "ctrl", "alt", "cmd" }, key = "z" },
}
