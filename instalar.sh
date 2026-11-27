#!/bin/bash
# Instala o PredatorWMI.kext em /Library/Extensions. Rodar como root.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
K=/Library/Extensions/PredatorWMI.kext
rm -rf "$K"
cp -R "$D/build/PredatorWMI.kext" "$K"
xattr -dr com.apple.quarantine "$K" 2>/dev/null || true
chown -R root:wheel "$K"; chmod -R 755 "$K"
install -m 755 "$D/build/predator-rgb" /usr/local/bin/predator-rgb
kmutil load -p "$K" || true
echo "Se pedir aprovação: Ajustes > Privacidade e Segurança > Permitir, e reinicie."
