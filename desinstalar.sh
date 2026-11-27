#!/bin/bash
# Remove o PredatorWMI.kext. Rodar como root e reiniciar.
launchctl bootout system/com.predatorrgb.apply 2>/dev/null
rm -rf /Library/Extensions/PredatorWMI.kext /usr/local/bin/predator-rgb /usr/local/etc/predator-rgb.conf /Library/LaunchDaemons/com.predatorrgb.apply.plist /etc/sudoers.d/predator-rgb
kmutil install --update-all
echo "Removido. Reinicie."
