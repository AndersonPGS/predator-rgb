# PredatorRGB

Control the 4-zone RGB keyboard of the **Acer Predator Helios 300 (PH315-53)** on a macOS
Hackintosh, from a menu bar app. No password prompts, no Windows/PredatorSense needed.

- Static color for all zones or one color per zone
- Built-in effects (keyboard firmware): Breath, Neon, Wave, Shifting, Zoom (speed, brightness, direction)
- Animated effects (driven by the app): Rainbow, Rainbow wave, Color cycle, Multi-color breathing,
  Strobe, Police, Aurora, Fire, Candle, Ocean, Sunset, Lava lamp, Heartbeat, Scanner, Sparkle,
  Ping-pong, CPU load meter, Battery meter, Time of day
- Low overhead: only changed zones are sent, adjustable frame rate (10/20/30 fps), meters run at 2 fps
- Optional menu bar icon with the current zone colors
- Profiles, launch at login, re-applies your lighting at login and after sleep
  (the keyboard resets to blue after a full power-off)
- Command line tool `predator-rgb` for scripts

Tested on: **Predator PH315-53, macOS 26 (Tahoe), OpenCore**. Other Acer Predator/Nitro laptops
with a 4-zone keyboard that expose the same WMI interface will probably work: the driver looks
for the interface itself, not for a model name. Please open an issue with your model and result.

## How it works

Acer laptops expose keyboard lighting through a WMI interface in ACPI
(GUID `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`). macOS has no WMI support, so:

- **`PredatorWMI.kext`** attaches to the ACPI WMI device (`PNP0C14`) whose `_WDG` table lists
  that GUID, finds the method object (`WMxx`) at runtime (no DSDT patching), and exposes a tiny
  user client. It only accepts the keyboard lighting methods (2, 4, 5, 6, 20, 21); fan, turbo and
  overclock methods are refused, so it is safe to use without root.
- **PredatorRGB.app** (SwiftUI, menu bar) and **`predator-rgb`** (CLI) send the commands.

## Requirements

- macOS 13 or later, Intel (x86_64)
- SIP with **Kext Signing disabled** (unsigned kext). Most Hackintosh setups already have it,
  e.g. `csr-active-config` = `03000000`. Check with `csrutil status`.

## Install

Download the latest release (or build it, see below), open Terminal in that folder and run:

```
sudo ./install.sh
```

Then:

1. **System Settings → Privacy & Security → Security**: click **Allow** for the PredatorWMI
   (or "unknown developer") system extension.
2. **Restart.**
3. Open **PredatorRGB** from Applications. A keyboard icon appears in the menu bar.
   The app is not notarized: the first time, right-click it → **Open**.
4. Optional: enable **Launch at login** in the app.

The driver lives in `/Library/Extensions`, not in your EFI, so it never touches your
OpenCore config. Updating the driver requires allowing it again and restarting; app updates don't.

### Uninstall

```
sudo ./uninstall.sh
```

and restart. If the driver ever prevents a normal boot, start in Safe Mode and delete
`/Library/Extensions/PredatorWMI.kext`.

### Alternative: inject with OpenCore (advanced)

You can instead copy `PredatorWMI.kext` to `EFI/OC/Kexts` and add it to `Kernel → Add`
(`ExecutablePath` `Contents/MacOS/PredatorWMI`, `PlistPath` `Contents/Info.plist`). No approval
prompt is needed this way, but a mistake in `config.plist` can stop your machine from booting:
keep a backup of your EFI.

## Command line

```
predator-rgb info                                  # read-only status
predator-rgb static 255 0 0                        # all zones red
predator-rgb static 0 0 255 2                      # zone 2 blue
predator-rgb zones 255,0,0 0,255,0 0,0,255 160,0,255
predator-rgb effect 3 5 100                        # wave, speed 5, brightness 100
predator-rgb effect 1 4 100 1 0 255 0              # green breath
predator-rgb off
```

Modes: 1 breath, 2 neon, 3 wave, 4 shifting, 5 zoom.
Direction: 1 right to left, 2 left to right. Color applies to breath, shifting and zoom.

## Build

Requires Xcode (Kernel.framework headers and Swift).

```
make
```

Outputs `build/PredatorWMI.kext`, `build/PredatorRGB.app` and `build/predator-rgb`.

## Credits

The WMI protocol (method IDs and payload layout) comes from the Linux
[acer-predator-turbo-and-rgb-keyboard-linux-module](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module)
by JafarAkhondali and contributors, based on the kernel `acer-wmi` driver. No code was copied;
this project is released under the same license.

## License

GPL-3.0. See [LICENSE](LICENSE).

No warranty: this talks to your laptop's embedded controller through ACPI. It only uses the
same lighting commands PredatorSense uses, but use it at your own risk.
