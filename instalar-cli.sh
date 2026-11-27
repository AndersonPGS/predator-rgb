#!/bin/bash
# Instala/atualiza só o comando, o serviço de boot e a regra do sudo (sem tocar no kext). Rodar como root.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
mkdir -p /usr/local/bin /usr/local/etc
install -m 755 "$D/build/predator-rgb" /usr/local/bin/predator-rgb
install -m 644 -o root -g wheel "$D/com.predatorrgb.apply.plist" /Library/LaunchDaemons/com.predatorrgb.apply.plist
echo '%admin ALL=(root) NOPASSWD: /usr/local/bin/predator-rgb' > /tmp/predator-rgb.sudoers
visudo -cf /tmp/predator-rgb.sudoers
install -m 440 -o root -g wheel /tmp/predator-rgb.sudoers /etc/sudoers.d/predator-rgb
rm -f /tmp/predator-rgb.sudoers
launchctl bootout system/com.predatorrgb.apply 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.predatorrgb.apply.plist
echo ok
