# parsec-pinch

Pinch to zoom on your trackpad, over Parsec, Mac to Mac.

Parsec is brilliant for driving one Mac from another, but pinch on the laptop trackpad does nothing on the far side. That is not a setting. Parsec's protocol only carries keyboard, mouse buttons, mouse movement, scroll wheel and gamepads. It has no gesture channel.

parsec-pinch adds one alongside Parsec. A tiny script on your laptop catches the pinch while Parsec is in front and sends it to the other Mac, where a matching script replays it as a real macOS pinch at the cursor. Premiere, Final Cut, Safari, Preview, Maps, anything that zooms with a pinch, zooms exactly as if you were sitting at that Mac. Parsec itself is never touched.

Set and forget. It starts at login on both Macs, survives sleep, lid closes and moving between networks, and if the other Mac ever stops answering it quietly falls back to sending `=` and `-` keystrokes so a timeline still zooms in steps.

## What you need

- Two Macs. The laptop you connect from (say a MacBook) and the Mac you connect to (say a Mac mini). Apple silicon or Intel.
- Parsec already working between them.
- [Tailscale](https://tailscale.com) on both, signed into the same account. Free for personal use. It gives each Mac a private address that works from any network, home, office or hotel. The same Wi-Fi also works without Tailscale, but only while you are on it.

That is it. The installer fetches everything else it needs (one free helper app called [Hammerspoon](https://www.hammerspoon.org)).

## Install: one line on each Mac

### Step 1. On the Mac you connect TO (the Mac mini, the host)

Open Terminal on it (through Parsec is fine), paste this, press Return:

```
curl -fsSL https://raw.githubusercontent.com/charlestarp/parsec-pinch/main/install.sh | bash -s -- host
```

When macOS pops up asking to let Hammerspoon control the computer, click Open System Settings and switch Hammerspoon on under Accessibility. Nothing works until that is on.

At the end it prints a line that starts with `curl` and already has this Mac's address and a secret token filled in. Copy that whole line.

### Step 2. On the laptop you connect FROM (the MacBook, the client)

Open Terminal, paste the line from step 1, press Return. It looks like this:

```
curl -fsSL https://raw.githubusercontent.com/charlestarp/parsec-pinch/main/install.sh | bash -s -- client --token a1b2c3d4e5f6a7b8 --host 100.101.102.103 --host 192.168.1.20
```

Same Accessibility prompt here. Switch Hammerspoon on. You will see "parsec-pinch ready" flash on screen.

### Step 3. Pinch

Connect with Parsec, open something that zooms, pinch on the trackpad. Done.

## Finding the address yourself

Step 1 prints the addresses for you. If you ever need to find them by hand:

- **Tailscale address (use this one).** Click the Tailscale icon in the menu bar on the Mac mini. Its own name is at the top with an address like `100.101.102.103` next to it. Click it to copy. Or in Terminal: `tailscale ip -4`. This address never changes and works from any network, so it is the one to use.
- **Local address (backup).** System Settings, Wi-Fi or Network, Details. It looks like `192.168.1.20` and only works while both Macs are on the same Wi-Fi. It can change when the router feels like it.

You can give the client several `--host` addresses. It pings all of them and uses whichever answers, so Tailscale plus local is a good pair.

## Day to day

- **Turn it on or off:** Ctrl+Alt+Cmd+Z on the laptop. A note flashes "on" or "off".
- **Make it zoom more or less per pinch:** on the laptop, open `~/.hammerspoon/parsec-pinch-config.lua` in any text editor and change `scale = 1.0`. 1.5 is more, 0.7 is less. Then click the Hammerspoon menu bar icon and choose Reload Config.
- **Use it with another remote desktop app:** add that app's id to `apps` in the same file. Find an id with `osascript -e 'id of app "Splashtop Business"'` in Terminal.
- **Check it is alive:** click the Hammerspoon menu bar icon, Console, type `parsecPinch.status()`. Healthy looks like `host=100.101.102.103 ... acks=[100.101.102.103 3s ago]`.

## If something is off

- **Zoom is stepped, not smooth.** The laptop can't hear the other Mac, so it is in keys fallback. Check both Macs are signed into Tailscale (or on the same Wi-Fi), and that Hammerspoon on the other Mac has Accessibility switched on. If the other Mac's firewall is on, allow incoming connections for Hammerspoon under System Settings, Network, Firewall, Options.
- **Nothing at all, and the status says `tap=false` or `accessibility=false`.** Hammerspoon on that Mac has no Accessibility permission. Switch it on, it picks itself up within a few seconds.
- **It zooms the Parsec window itself instead of the far Mac.** Forwarding is toggled off (Ctrl+Alt+Cmd+Z), or Parsec is not in the `apps` list.
- **After a macOS upgrade it stopped.** Big upgrades sometimes reset Accessibility permissions. Switch Hammerspoon back on in Accessibility on both Macs.
- **Re-running the installer** is always safe. It keeps the existing token on the host and only adds what is missing.

## How it works

On the laptop, Hammerspoon watches trackpad gesture events. When a magnify event arrives and Parsec is the frontmost app, the magnification delta goes out as a tiny UDP packet to the other Mac and the local event is swallowed so Parsec's own window does not react. Packets are `B` (begin), `M <delta>` (change) and `E` (end), prefixed with the shared token.

On the other Mac, Hammerspoon receives them and creates real gesture events with `hs.eventtap.event.newGesture`, which writes the same private CGEvent fields a trackpad does (110 subtype, 113 magnification, 132 phase). Hammerspoon only knows how to make "began" and "ended" events, so each delta is created as "began" and its phase field is patched to "changed" before posting. The window under the cursor gets a pinch it cannot tell from a trackpad.

The client pings every address every five seconds and uses the most recently answering one. A laptop's UDP socket dies when the lid closes, so it is rebuilt on wake and any time a host that used to answer has been silent for fifteen seconds. The host probes its own listener every thirty seconds and rebuilds it if it has died. Every callback is wrapped so one error cannot take the whole thing down, and macOS's habit of disabling event taps it thinks are slow is undone within ten seconds.

## Security

- The link is plain UDP on port 47801 with a shared random token. The worst someone who knows the token could do is pinch on your Mac. It carries nothing else and cannot type, click or read anything.
- Keep it to your LAN or Tailscale. Do not open port 47801 to the internet.
- The token is generated per install and lives only in the two config files. It is never sent anywhere else.

## Uninstall

On each Mac, delete the two lines mentioning `hs.ipc` and `parsec-pinch` from `~/.hammerspoon/init.lua`, then remove `~/.hammerspoon/parsec-pinch` and `~/.hammerspoon/parsec-pinch-config.lua`. Hammerspoon itself can stay or go.

## Credits

By Charles Patterson. Built on [Hammerspoon](https://www.hammerspoon.org). Gesture synthesis uses the TouchEvents code Hammerspoon carries from [calftrail/Touch](https://github.com/calftrail/Touch). Field numbers confirmed against Apple's IOHIDEventTypes.h and WebKit's CoreGraphics test SPI.

MIT licence.
