# PredatorRGB

<img src="app/icon-preview.png" width="128" alt="Ícone do PredatorRGB">

[English](README.md) · **Português** · [Español](README.es.md)

Controle o teclado RGB de 4 zonas do **Acer Predator Helios 300 (PH315-53)** num Hackintosh com
macOS, por um app na barra de menus. Sem pedir senha e sem precisar do Windows ou do PredatorSense.

- Uma cor para todas as zonas ou uma cor por zona
- Efeitos do teclado (firmware): Respiração, Neon, Onda, Deslizante, Zoom (velocidade, brilho, direção)
- Efeitos animados (gerados pelo app): Arco-íris, Onda arco-íris, Ciclo de cores, Respiração com
  várias cores, Estroboscópio, Polícia, Aurora, Fogo, Vela, Oceano, Pôr do sol, Lâmpada de lava,
  Batimento cardíaco, Scanner, Brilhos, Pingue-pongue, Medidor de CPU, Medidor de bateria, Hora do dia
- Efeitos de música (macOS 14.2+): espectro, pulso do grave, arco-íris na batida, medidor de volume.
  Reagem a qualquer som tocando no Mac. O macOS pede a permissão de **Gravação de Áudio do Sistema**
  só na primeira vez que você escolhe um deles; o áudio é analisado na hora e nunca é salvo
- Leve: os modos estático e do teclado enviam um único comando e usam 0% de CPU; as animações só
  enviam as zonas que mudaram, com taxa de quadros ajustável (10/20/30 fps); os medidores atualizam
  a cada 0,5 a 30 s
- Ícone opcional na barra de menus com as cores atuais das zonas
- App em inglês, português (Brasil) e espanhol (segue o idioma do sistema)
- Perfis, abrir ao iniciar sessão, reaplica as cores ao iniciar e ao acordar do repouso
  (o teclado volta para azul depois de desligar de vez)
- Comando de terminal `predator-rgb` para scripts

Testado em: **Predator PH315-53, macOS 26 (Tahoe), OpenCore**. Outros notebooks Acer Predator/Nitro
com teclado de 4 zonas e a mesma interface WMI provavelmente funcionam: o driver procura a
interface, não o nome do modelo. Abra uma issue contando o seu modelo e o resultado.

## Como funciona

Os notebooks Acer controlam a iluminação do teclado por uma interface WMI no ACPI
(GUID `7A4DDFE7-5B5D-40B4-8595-4408E0CC7F56`). O macOS não tem suporte a WMI, então:

- **`PredatorWMI.kext`** se conecta ao dispositivo WMI do ACPI (`PNP0C14`) cuja tabela `_WDG`
  contém esse GUID, encontra o método (`WMxx`) sozinho (sem patch de DSDT) e oferece uma ponte
  mínima. Ele só aceita os comandos de iluminação do teclado (2, 4, 5, 6, 20, 21); ventoinha,
  turbo e overclock são recusados, por isso pode ser usado sem root.
- **PredatorRGB.app** (SwiftUI, barra de menus) e **`predator-rgb`** (terminal) enviam os comandos.

## Requisitos

- macOS 13 ou mais novo, Intel (x86_64)
- SIP com **Kext Signing desativado** (driver sem assinatura). A maioria dos Hackintosh já está
  assim, por exemplo `csr-active-config` = `03000000`. Confira com `csrutil status`.

## Instalação

Baixe a última release (ou compile, veja abaixo), abra o Terminal nessa pasta e rode:

```
sudo ./install.sh
```

Depois:

1. **Ajustes do Sistema → Privacidade e Segurança → Segurança**: clique em **Permitir** na
   extensão do PredatorWMI (ou "desenvolvedor desconhecido").
2. **Reinicie.**
3. Abra o **PredatorRGB** em Aplicativos. O ícone (uma tecla com uma estrela) aparece na barra de menus.
4. Opcional: ative **Abrir ao iniciar sessão** no app.

O driver fica em `/Library/Extensions`, não na sua EFI, então nunca mexe no seu config do
OpenCore. Atualizar o driver exige permitir de novo e reiniciar; atualizar o app, não.

### Desinstalar

```
sudo ./uninstall.sh
```

e reinicie. Se algum dia o driver impedir o boot normal, entre no Modo de Segurança e apague
`/Library/Extensions/PredatorWMI.kext`.

### Alternativa: injetar pelo OpenCore (avançado)

Você pode copiar o `PredatorWMI.kext` para `EFI/OC/Kexts` e adicioná-lo em `Kernel → Add`
(`ExecutablePath` `Contents/MacOS/PredatorWMI`, `PlistPath` `Contents/Info.plist`). Assim não é
preciso aprovar nada, mas um erro no `config.plist` pode impedir o boot: guarde um backup da EFI.

## Terminal

```
predator-rgb info                                  # estado (só leitura)
predator-rgb static 255 0 0                        # todas as zonas vermelhas
predator-rgb static 0 0 255 2                      # zona 2 azul
predator-rgb zones 255,0,0 0,255,0 0,0,255 160,0,255
predator-rgb effect 3 5 100                        # onda, velocidade 5, brilho 100
predator-rgb effect 1 4 100 1 0 255 0              # respiração verde
predator-rgb off
```

Modos: 1 respiração, 2 neon, 3 onda, 4 deslizante, 5 zoom.
Direção: 1 da direita para a esquerda, 2 da esquerda para a direita. A cor vale para respiração,
deslizante e zoom.

## Compilar

Requer o Xcode (cabeçalhos do Kernel.framework e Swift).

```
make
```

Gera `build/PredatorWMI.kext`, `build/PredatorRGB.app` e `build/predator-rgb`.

## Bem-vindo ao clube

Se você está lendo isto, provavelmente já faz parte do clube: a GPU dedicada do seu PH315-53
queimou, o notebook gamer foi rebaixado a "PC de trabalho" e, num
momento de fé, você pensou: *"já que não dá mais pra jogar, que pelo menos vire um Mac"*.

A GPU pode ter morrido, mas **o RGB não pode morrer**. Ele é o último sinal de vida do gamer que
existe aí dentro. E como todo mundo sabe que RGB dá mais FPS, o seu notebook continua firme como
um legítimo **gamer de trabalho**: planilha no ultra, e-mail a 144 Hz e call com a iluminação no
máximo.

Seja bem-vindo ao clube.

## Créditos

O protocolo WMI (números dos métodos e formato dos dados) vem do módulo Linux
[acer-predator-turbo-and-rgb-keyboard-linux-module](https://github.com/JafarAkhondali/acer-predator-turbo-and-rgb-keyboard-linux-module),
de JafarAkhondali e colaboradores, baseado no driver `acer-wmi` do kernel. Nenhum código foi
copiado; este projeto usa a mesma licença.

## Licença

GPL-3.0. Veja [LICENSE](LICENSE).

Sem garantia: o app conversa com o controlador do notebook pelo ACPI. Ele só usa os mesmos comandos
de iluminação que o PredatorSense usa, mas o uso é por sua conta e risco.
