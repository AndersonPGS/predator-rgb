#!/bin/bash
# PredatorRGB uninstaller. Run: sudo ./uninstall.sh, then restart.
[ "$(id -u)" = 0 ] || { echo "Run with sudo: sudo ./uninstall.sh"; exit 1; }
pkill -x PredatorRGB 2>/dev/null
rm -rf /Library/Extensions/PredatorWMI.kext /Applications/PredatorRGB.app /usr/local/bin/predator-rgb
kmutil install --update-all >/dev/null 2>&1
echo "Removed. Restart to unload the driver."
