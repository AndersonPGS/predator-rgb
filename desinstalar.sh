#!/bin/bash
# Remove o PredatorWMI.kext. Rodar como root e reiniciar.
rm -rf /Library/Extensions/PredatorWMI.kext /usr/local/bin/predator-rgb
kmutil install --update-all
echo "Removido. Reinicie."
