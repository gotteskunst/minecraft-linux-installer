# Minecraft Linux Installer

Ein interaktives Installationsskript für **Minecraft Java Edition** und **Minecraft Bedrock Edition** unter Linux – mit Auswahlmenü.

## Features

- Menü mit `whiptail` oder `dialog` (automatischer Fallback auf ein Textmenü)
- Erkennt die Distribution und den Paketmanager (`apt`, `dnf`, `pacman`, `zypper`)
- Richtet Flatpak und Flathub automatisch ein, falls nötig
- **Java Edition**
  - Prism Launcher (empfohlen für Mods und mehrere Instanzen)
  - Offizieller Minecraft Launcher (Flatpak)
  - OpenJDK 21 Runtime
  - Java-Server (neueste Release-Version direkt von Mojang)
- **Bedrock Edition**
  - Minecraft Bedrock Launcher (mcpelauncher)
- Programme über das Menü wieder deinstallieren

## Installation

```bash
git clone https://github.com/DEIN-NAME/minecraft-linux-installer.git
cd minecraft-linux-installer
chmod +x install.sh
./install.sh
```

Textmenü erzwingen:

```bash
./install.sh --text
```

## Voraussetzungen

- Linux (x86_64 oder aarch64)
- `bash`, `curl`, `sudo` (für Paketinstallation)
- Für den Bedrock Launcher: eine **legale Kopie von Minecraft Bedrock für Android**, die an dein Google-Play-Konto gebunden ist, sowie ein OpenGL-fähiger Grafiktreiber

## Hinweise

- Der Java-Server wird mit `eula=true` vorbereitet. Mit dem Start akzeptierst du die [Minecraft EULA](https://aka.ms/MinecraftEULA).
- Dieses Projekt ist nicht mit Mojang, Microsoft oder Anthropic verbunden. Minecraft ist eine Marke von Mojang Synergies AB.
- Das Skript lädt keine Spieldateien herunter, die eine Lizenz erfordern; die Launcher verlangen einen eigenen Account bzw. Kauf.

## Mitmachen

Pull Requests sind willkommen, zum Beispiel für:

- weitere Distributionen
- Bedrock-Dedicated-Server
- Paper-/Fabric-/Forge-Installation
- Übersetzungen

## Lizenz

[MIT](LICENSE)