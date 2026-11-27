# PredatorRGB

<img src="app/icon-preview.png" width="128" alt="Icono de PredatorRGB">

[English](README.md) · [Português](README.pt-BR.md) · **Español**

Controla el teclado RGB de 4 zonas del **Acer Predator Helios 300 (PH315-53)** en un Hackintosh con
macOS, desde una app en la barra de menús. Sin pedir contraseña y sin necesitar Windows ni
PredatorSense.

- Un color para todas las zonas o un color por zona
- Efectos del teclado (firmware): Respiración, Neón, Onda, Desplazamiento, Zoom (velocidad, brillo, dirección)
- Efectos animados (generados por la app): Arcoíris, Onda arcoíris, Ciclo de colores, Respiración
  con varios colores, Estroboscopio, Policía, Aurora, Fuego, Vela, Océano, Atardecer, Lámpara de
  lava, Latido, Escáner, Destellos, Ping-pong, Medidor de CPU, Medidor de batería, Hora del día
- Efectos de música (macOS 14.2+): espectro, pulso de graves, arcoíris al ritmo, vúmetro.
  Reaccionan a cualquier sonido que suene en el Mac. macOS pide el permiso de **Grabación de audio
  del sistema** solo la primera vez que eliges uno; el audio se analiza en directo y nunca se guarda
- Ligero: los modos estático y del teclado envían un solo comando y usan 0% de CPU; las animaciones
  solo envían las zonas que cambiaron, con fotogramas por segundo ajustables (10/20/30); los
  medidores se actualizan cada 0,5 a 30 s
- Icono opcional en la barra de menús con los colores actuales de las zonas
- App en inglés, portugués (Brasil) y español (sigue el idioma del sistema)
- Perfiles, abrir al iniciar sesión, vuelve a aplicar los colores al iniciar y al despertar
  (el teclado vuelve a azul después de apagarlo por completo)
- Comando de terminal `predator-rgb` para scripts

Probado en: **Predator PH315-53, macOS 26 (Tahoe), OpenCore**. Otros portátiles Acer Predator/Nitro
con teclado de 4 zonas y la misma interfaz WMI probablemente funcionen: el driver busca la
interfaz, no el nombre del modelo. Abre un issue con tu modelo y el resultado.

## Cómo funciona

Los portátiles Acer controlan la iluminación del teclado mediante una interfaz WMI en ACPI
(GUID `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`). macOS no tiene soporte WMI, así que:

- **`PredatorWMI.kext`** se conecta al dispositivo WMI de ACPI (`PNP0C14`) cuya tabla `_WDG`
  contiene ese GUID, encuentra el método (`WMxx`) por sí mismo (sin parchear el DSDT) y ofrece un
  puente mínimo. Solo acepta los comandos de iluminación del teclado (2, 4, 5, 6, 20, 21);
  ventiladores, turbo y overclock se rechazan, por eso puede usarse sin root.
- **PredatorRGB.app** (SwiftUI, barra de menús) y **`predator-rgb`** (terminal) envían los comandos.

## Requisitos

- macOS 13 o posterior, Intel (x86_64)
- SIP con **Kext Signing desactivado** (driver sin firma). La mayoría de los Hackintosh ya lo
  tienen, por ejemplo `csr-active-config` = `03000000`. Compruébalo con `csrutil status`.

## Instalación

Descarga la última release (o compílala, ver abajo), abre la Terminal en esa carpeta y ejecuta:

```
sudo ./install.sh
```

Después:

1. **Ajustes del Sistema → Privacidad y seguridad → Seguridad**: haz clic en **Permitir** en la
   extensión de PredatorWMI (o "desarrollador desconocido").
2. **Reinicia.**
3. Abre **PredatorRGB** desde Aplicaciones. Su icono (una tecla con una estrella) aparece en la barra de menús.
4. Opcional: activa **Abrir al iniciar sesión** en la app.

El driver vive en `/Library/Extensions`, no en tu EFI, así que nunca toca tu config de OpenCore.
Actualizar el driver requiere permitirlo de nuevo y reiniciar; actualizar la app, no.

### Desinstalar

```
sudo ./uninstall.sh
```

y reinicia. Si alguna vez el driver impide un arranque normal, entra en Modo seguro y borra
`/Library/Extensions/PredatorWMI.kext`.

### Alternativa: inyectar con OpenCore (avanzado)

Puedes copiar `PredatorWMI.kext` a `EFI/OC/Kexts` y añadirlo en `Kernel → Add`
(`ExecutablePath` `Contents/MacOS/PredatorWMI`, `PlistPath` `Contents/Info.plist`). Así no hace
falta aprobar nada, pero un error en `config.plist` puede impedir el arranque: guarda una copia de tu EFI.

## Terminal

```
predator-rgb info                                  # estado (solo lectura)
predator-rgb static 255 0 0                        # todas las zonas en rojo
predator-rgb static 0 0 255 2                      # zona 2 en azul
predator-rgb zones 255,0,0 0,255,0 0,0,255 160,0,255
predator-rgb effect 3 5 100                        # onda, velocidad 5, brillo 100
predator-rgb effect 1 4 100 1 0 255 0              # respiración verde
predator-rgb off
```

Modos: 1 respiración, 2 neón, 3 onda, 4 desplazamiento, 5 zoom.
Dirección: 1 de derecha a izquierda, 2 de izquierda a derecha. El color se aplica a respiración,
desplazamiento y zoom.

## Compilar

Requiere Xcode (cabeceras de Kernel.framework y Swift).

```
make
```

Genera `build/PredatorWMI.kext`, `build/PredatorRGB.app` y `build/predator-rgb`.

## Bienvenido al club

Si estás leyendo esto, probablemente ya eres parte del club: la GPU dedicada de tu PH315-53 se
quemó (un clásico de este modelo), tu portátil gamer fue degradado a "PC del trabajo" y, en un
momento de fe, pensaste: *"si ya no sirve para jugar, que por lo menos sea un Mac"*.

La GPU puede haber muerto, pero **el RGB no puede morir**. Es la última señal de vida del gamer
que lleva dentro. Y como todo el mundo sabe que el RGB da +30 FPS, tu portátil sigue firme como un
auténtico **gamer de oficina**: hojas de cálculo en ultra, correos a 144 Hz y videollamadas con
las luces al máximo.

Bienvenido al club.

## Créditos

El protocolo WMI (números de métodos y formato de los datos) viene del módulo de Linux
[acer-predator-turbo-and-rgb-keyboard-linux-module](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module),
de JafarAkhondali y colaboradores, basado en el driver `acer-wmi` del kernel. No se copió código;
este proyecto usa la misma licencia.

## Licencia

GPL-3.0. Consulta [LICENSE](LICENSE).

Sin garantía: la app se comunica con el controlador del portátil a través de ACPI. Solo usa los
mismos comandos de iluminación que PredatorSense, pero úsala bajo tu propia responsabilidad.
