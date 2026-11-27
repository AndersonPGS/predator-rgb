# predator-rgb

Controle do teclado RGB de 4 zonas do Acer Predator Helios 300 (PH315-53) no macOS (Hackintosh, macOS 26).

- `kext/`: `PredatorWMI.kext`, ponte mínima para a interface WMI de gaming da Acer
  (GUID `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`). Casa com o dispositivo ACPI `PNP0C14`
  cujo `_WDG` contém esse GUID e expõe um user client (somente administradores) que chama
  `WMxx(0, methodId, buffer)`. Toda a lógica de protocolo fica no espaço de usuário.
- `cli/predator-rgb.c`: comando de linha.

Protocolo: [acer-predator-turbo-and-rgb-keyboard-linux-module](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module)
(`facer.c`, `facer_rgb.py`): métodos 2 (LED gaming), 4, 5 (sys info), 6 (cor estática por zona), 20/21 (modo do teclado, 16 bytes).

## Uso

```
make
sudo ./instalar.sh        # aprovar em Ajustes > Privacidade e Segurança, reiniciar
ioreg -l -c PredatorWMIBridge | grep -E "WDG|GamingMethod"
sudo predator-rgb info
sudo predator-rgb static 255 0 0          # todas as zonas vermelhas
sudo predator-rgb static 0 0 255 2        # zona 2 azul
sudo predator-rgb effect 3 5 100          # onda
sudo ./desinstalar.sh
```

Requer SIP com Kext Signing desativado (já é o caso na EFI `efi-helios`). O kext não fica na EFI.
