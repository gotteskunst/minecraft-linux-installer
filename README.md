<div align="center">

# ⛏ Minecraft Linux Installer

**Install Minecraft Java Edition and Bedrock Edition on Linux from a clean terminal UI.**

![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Shell](https://img.shields.io/badge/shell-Bash%204.3%2B-lightgrey)
![Dependencies](https://img.shields.io/badge/extra%20dependencies-none-brightgreen)

</div>

---

## Overview

One script, one menu. Pick what you want with the arrow keys, and the installer takes care of package managers, Flatpak, Java and the Mojang server download for you.

It is written in pure Bash, so there is nothing to install before you can run it: no `whiptail`, no `dialog`, no Python.

<div align="center">

<img src="https://iili.io/nOqInu1.png" alt="Minecraft Linux Installer terminal UI" width="720">

</div>

## Features

- **Clean TUI** with arrow-key navigation, checkboxes, a spinner and clear ✔ / ✖ status per step
- **Automatic setup** of Flatpak and Flathub when they are missing
- **Distribution aware**: detects `apt`, `dnf`, `pacman` and `zypper`
- **Java server in one go**: downloads the latest release from Mojang, verifies its SHA-1 checksum and creates a ready-to-use start script
- **Installed state at a glance**: launchers you already have are marked in the menu
- **Easy removal** of installed launchers
- **Quiet by default**: all command output goes to a log file, which is only kept (and its path shown) if something fails

## What you can install

| Edition | Component | Source |
| --- | --- | --- |
| Java | Prism Launcher (recommended for mods and instances) | Flathub |
| Java | Official Minecraft Launcher | Flathub |
| Java | OpenJDK 21 runtime | system package manager |
| Java | Dedicated server | Mojang |
| Bedrock | Bedrock Launcher (mcpelauncher) | Flathub |

## Quick start

```bash
git clone https://github.com/gotteskunst/minecraft-linux-installer.git
cd minecraft-linux-installer
chmod +x install.sh
./install.sh
```

The installer asks for your `sudo` password only when it needs administrator rights. Do not start it with `sudo` yourself.

## Controls

| Key | Action |
| --- | --- |
| `↑` / `↓` or `k` / `j` | Move |
| `Space` | Toggle an entry |
| `Enter` | Confirm |
| `q` or `Esc` | Back / quit |

## Java server

Choose **Java Server** in the Java menu. The installer asks for:

1. the install directory (default: `~/minecraft-server`)
2. the amount of memory (1, 2, 4 or 8 GB)
3. whether you accept the [Minecraft EULA](https://aka.ms/MinecraftEULA)

It then installs missing tools (`curl`, `jq`) and Java 21 if needed, downloads and verifies the server, and creates:

| File | Purpose |
| --- | --- |
| `server.jar` | Official Mojang server |
| `start.sh` | Start script with your memory setting |
| `eula.txt` | Only created if you accepted the EULA |
| `.mc-version` | Installed Minecraft version |

Start the server with:

```bash
~/minecraft-server/start.sh
```

Make sure TCP port `25565` is open in your firewall so other players can join.

## Requirements

- Linux on `x86_64` or `aarch64`
- Bash 4.3 or newer
- `sudo` or root access
- An interactive terminal
- A graphical desktop for the launchers. On headless servers, only the Java server makes sense.
- For Bedrock: a legitimate copy of Minecraft Bedrock for Android tied to your Google Play account, and an OpenGL-capable graphics driver

## Supported package managers

| Family | Package manager |
| --- | --- |
| Debian, Ubuntu, Linux Mint | `apt` |
| Fedora, RHEL, AlmaLinux, Rocky | `dnf` |
| Arch, Manjaro | `pacman` |
| openSUSE | `zypper` |

## Troubleshooting

**Something failed.** The failing step is marked with ✖ and the last log lines are shown. The full log path is printed when you leave the installer.

**Launchers do not show up in the application menu.** Log out and back in once after Flatpak was installed.

**The server does not start.** Recent Minecraft versions need Java 21. Check with `java -version`.

**`bad interpreter` or `^M` errors.** The script was saved with Windows line endings. The repository enforces LF through `.gitattributes`; if you edited the file on Windows, convert it with `dos2unix install.sh`.

## Contributing

Issues and pull requests are welcome. Ideas that would be great to have:

- more distributions and package managers
- Bedrock dedicated server
- Paper, Fabric and Forge for the Java server
- translations

## Disclaimer

This project is not affiliated with, endorsed by, or connected to Mojang Studios or Microsoft. Minecraft is a trademark of Mojang Synergies AB. The installer does not distribute any game files; the launchers require your own account or purchase.

## License

Released under the [MIT License](LICENSE).