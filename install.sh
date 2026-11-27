#!/bin/bash
# PredatorRGB installer. Run: sudo ./install.sh   (from the release folder or after `make`)
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo ./install.sh"; exit 1; }
D="$(cd "$(dirname "$0")" && pwd)"
[ -d "$D/build" ] && D="$D/build"
for f in PredatorWMI.kext PredatorRGB.app predator-rgb; do
  [ -e "$D/$f" ] || { echo "Missing $f (run make first)"; exit 1; }
done
if csrutil status | grep -q "Kext Signing: enabled"; then
  echo "SIP Kext Signing is enabled: unsigned kexts cannot load."
  echo "Set csr-active-config so that Kext Signing is disabled (e.g. 03000000) in your OpenCore config."
  exit 1
fi
K=/Library/Extensions/PredatorWMI.kext
rm -rf "$K"; cp -R "$D/PredatorWMI.kext" "$K"
chown -R root:wheel "$K"; chmod -R 755 "$K"; xattr -cr "$K"
rm -rf /Applications/PredatorRGB.app; cp -R "$D/PredatorRGB.app" /Applications/
xattr -cr /Applications/PredatorRGB.app
mkdir -p /usr/local/bin; install -m 755 "$D/predator-rgb" /usr/local/bin/predator-rgb
kmutil load -p "$K" 2>/dev/null && echo "Driver loaded." || {
  echo
  echo "Next steps:"
  echo "  1. System Settings > Privacy & Security > Security: click Allow for PredatorWMI."
  echo "  2. Restart."
  echo "  3. Open PredatorRGB from Applications (keyboard icon in the menu bar)."
}
