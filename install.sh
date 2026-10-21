#!/usr/bin/env bash
# =============================================================================
# Minecraft Linux Installer
# Installiert Minecraft Java Edition und Bedrock Edition unter Linux
# mit einem interaktiven Auswahlmenü (whiptail/dialog, Fallback: Textmenü).
# =============================================================================
set -uo pipefail

VERSION="1.0.0"
TITLE="Minecraft Linux Installer v${VERSION}"
SERVER_DIR_DEFAULT="${HOME}/minecraft-server"

# --------------------------------------------------------------------------
# Hilfsfunktionen
# --------------------------------------------------------------------------
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'

info()  { printf '%s[INFO]%s %s\n'  "$BLUE"   "$NC" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n'  "$GREEN"  "$NC" "$*"; }
warn()  { printf '%s[WARN]%s %s\n'  "$YELLOW" "$NC" "$*"; }
err()   { printf '%s[FEHLER]%s %s\n' "$RED"   "$NC" "$*" >&2; }

has() { command -v "$1" >/dev/null 2>&1; }

pause() {
  echo
  read -r -p "Enter drücken, um zum Menü zurückzukehren ..." _
}

# sudo nur verwenden, wenn wir nicht root sind
if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  if has sudo; then SUDO="sudo"; else SUDO=""; fi
fi

# --------------------------------------------------------------------------
# Distribution & Paketmanager erkennen
# --------------------------------------------------------------------------
PM=""
DISTRO="unbekannt"

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="${PRETTY_NAME:-${NAME:-unbekannt}}"
  fi

  if   has apt-get; then PM="apt"
  elif has dnf;     then PM="dnf"
  elif has pacman;  then PM="pacman"
  elif has zypper;  then PM="zypper"
  else PM=""
  fi
}

pkg_install() {
  # Nutzung: pkg_install paket1 paket2 ...
  if [[ -z "$PM" ]]; then
    err "Kein unterstützter Paketmanager gefunden (apt, dnf, pacman, zypper)."
    return 1
  fi
  case "$PM" in
    apt)    $SUDO apt-get update && $SUDO apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
  esac
}

# --------------------------------------------------------------------------
# Flatpak einrichten
# --------------------------------------------------------------------------
ensure_flatpak() {
  if ! has flatpak; then
    info "Flatpak ist nicht installiert – installiere es ..."
    pkg_install flatpak || { err "Flatpak konnte nicht installiert werden."; return 1; }
    warn "Nach der Flatpak-Installation kann ein Neustart/Neuanmeldung nötig sein,"
    warn "damit Programme im Anwendungsmenü erscheinen."
  fi

  if ! flatpak remotes --columns=name 2>/dev/null | grep -qx flathub; then
    info "Füge Flathub-Repository hinzu ..."
    $SUDO flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
      || { err "Flathub konnte nicht hinzugefügt werden."; return 1; }
  fi
  return 0
}

flatpak_install() {
  local app_id="$1" name="$2"
  ensure_flatpak || return 1
  info "Installiere ${name} (${app_id}) ..."
  if flatpak install -y flathub "$app_id"; then
    ok "${name} wurde installiert. Start: flatpak run ${app_id}"
  else
    err "Installation von ${name} fehlgeschlagen."
    return 1
  fi
}

flatpak_uninstall() {
  local app_id="$1" name="$2"
  if has flatpak && flatpak list --app --columns=application 2>/dev/null | grep -qx "$app_id"; then
    flatpak uninstall -y "$app_id" && ok "${name} wurde entfernt."
  else
    warn "${name} ist nicht installiert."
  fi
}

# --------------------------------------------------------------------------
# Java Edition
# --------------------------------------------------------------------------
install_java_runtime() {
  info "Installiere OpenJDK 21 (für aktuelle Minecraft-Versionen) ..."
  case "$PM" in
    apt)    pkg_install openjdk-21-jre || pkg_install openjdk-17-jre ;;
    dnf)    pkg_install java-21-openjdk || pkg_install java-17-openjdk ;;
    pacman) pkg_install jre21-openjdk || pkg_install jre17-openjdk ;;
    zypper) pkg_install java-21-openjdk || pkg_install java-17-openjdk ;;
    *)      err "Kein unterstützter Paketmanager."; return 1 ;;
  esac
  if has java; then
    ok "Java installiert: $(java -version 2>&1 | head -n1)"
  fi
}

install_java_prism()    { flatpak_install "org.prismlauncher.PrismLauncher" "Prism Launcher"; }
install_java_official() { flatpak_install "com.mojang.Minecraft" "Minecraft Launcher (offiziell)"; }

# Java-Server (offiziell von Mojang)
install_java_server() {
  local dir="${1:-$SERVER_DIR_DEFAULT}"

  for tool in curl jq; do
    if ! has "$tool"; then
      info "Installiere benötigtes Werkzeug: ${tool}"
      pkg_install "$tool" || { err "${tool} fehlt."; return 1; }
    fi
  done
  if ! has java; then
    install_java_runtime || return 1
  fi

  info "Hole Versionsliste von Mojang ..."
  local manifest latest ver_url server_url
  manifest="$(curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest_v2.json)" \
    || { err "Versionsliste konnte nicht geladen werden."; return 1; }
  latest="$(jq -r '.latest.release' <<<"$manifest")"
  ver_url="$(jq -r --arg v "$latest" '.versions[] | select(.id==$v) | .url' <<<"$manifest")"
  server_url="$(curl -fsSL "$ver_url" | jq -r '.downloads.server.url')"

  if [[ -z "$server_url" || "$server_url" == "null" ]]; then
    err "Server-Download für Version ${latest} nicht gefunden."
    return 1
  fi

  mkdir -p "$dir" || return 1
  info "Lade Minecraft Java Server ${latest} nach ${dir} ..."
  curl -fL --progress-bar -o "${dir}/server.jar" "$server_url" || { err "Download fehlgeschlagen."; return 1; }

  echo "eula=true" > "${dir}/eula.txt"
  cat > "${dir}/start.sh" <<'EOF'
#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
exec java -Xms1G -Xmx2G -jar server.jar nogui
EOF
  chmod +x "${dir}/start.sh"

  ok "Server ${latest} installiert in ${dir}"
  warn "Mit dem Start akzeptierst du die Minecraft EULA: https://aka.ms/MinecraftEULA"
  info "Starten mit: ${dir}/start.sh"
}

# --------------------------------------------------------------------------
# Bedrock Edition
# --------------------------------------------------------------------------
install_bedrock_launcher() {
  flatpak_install "io.mrarm.mcpelauncher" "Minecraft Bedrock Launcher (mcpelauncher)" || return 1
  echo
  warn "Hinweis: Der Bedrock Launcher benötigt eine legale Kopie von"
  warn "Minecraft Bedrock für Android, die an dein Google-Play-Konto gebunden ist."
  warn "Außerdem werden ein OpenGL-fähiger Grafiktreiber und ein 64-Bit-System benötigt."
}

# --------------------------------------------------------------------------
# Deinstallation
# --------------------------------------------------------------------------
uninstall_menu_action() {
  local choice="$1"
  case "$choice" in
    prism)   flatpak_uninstall "org.prismlauncher.PrismLauncher" "Prism Launcher" ;;
    official) flatpak_uninstall "com.mojang.Minecraft" "Minecraft Launcher" ;;
    bedrock) flatpak_uninstall "io.mrarm.mcpelauncher" "Bedrock Launcher" ;;
  esac
}

# --------------------------------------------------------------------------
# Menü-Abstraktion (whiptail > dialog > Textmenü)
# --------------------------------------------------------------------------
UI=""
detect_ui() {
  if   has whiptail; then UI="whiptail"
  elif has dialog;   then UI="dialog"
  else UI="text"
  fi
}

# menu "Titel" "Text" tag1 "Beschreibung1" tag2 "Beschreibung2" ...
# gibt den gewählten Tag auf stdout aus, Rückgabewert 1 bei Abbruch
menu() {
  local title="$1" text="$2"; shift 2
  local choice

  if [[ "$UI" == "text" ]]; then
    echo >&2
    echo "=== ${title} ===" >&2
    echo "${text}" >&2
    local -a tags=() descs=()
    while (( $# )); do tags+=("$1"); descs+=("$2"); shift 2; done
    local i
    for i in "${!tags[@]}"; do
      printf '  %d) %s\n' "$((i+1))" "${descs[$i]}" >&2
    done
    read -r -p "Auswahl [1-${#tags[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#tags[@]} )); then
      echo "${tags[$((choice-1))]}"
      return 0
    fi
    return 1
  fi

  choice="$($UI --title "$title" --menu "$text" 20 72 10 "$@" 3>&1 1>&2 2>&3)" || return 1
  echo "$choice"
}

# checklist "Titel" "Text" tag "Beschreibung" ON|OFF ...
checklist() {
  local title="$1" text="$2"; shift 2
  if [[ "$UI" == "text" ]]; then
    echo >&2
    echo "=== ${title} ===" >&2
    echo "${text}" >&2
    local -a tags=() descs=()
    while (( $# )); do tags+=("$1"); descs+=("$2"); shift 3; done
    local i
    for i in "${!tags[@]}"; do
      printf '  %d) %s\n' "$((i+1))" "${descs[$i]}" >&2
    done
    local input n
    read -r -p "Nummern mit Leerzeichen getrennt (z. B. 1 3): " input
    for n in $input; do
      if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#tags[@]} )); then
        echo "${tags[$((n-1))]}"
      fi
    done
    return 0
  fi

  $UI --title "$title" --separate-output --checklist "$text" 20 72 10 "$@" 3>&1 1>&2 2>&3
}

ask_yesno() {
  local text="$1"
  if [[ "$UI" == "text" ]]; then
    local a; read -r -p "${text} [j/N]: " a
    [[ "$a" =~ ^[jJyY] ]]
  else
    $UI --title "$TITLE" --yesno "$text" 10 60
  fi
}

ask_input() {
  local text="$1" default="$2" value
  if [[ "$UI" == "text" ]]; then
    read -r -p "${text} [${default}]: " value
    echo "${value:-$default}"
  else
    value="$($UI --title "$TITLE" --inputbox "$text" 10 60 "$default" 3>&1 1>&2 2>&3)" || return 1
    echo "${value:-$default}"
  fi
}

# --------------------------------------------------------------------------
# Untermenüs
# --------------------------------------------------------------------------
menu_java() {
  local sel
  sel="$(checklist "Java Edition" "Was möchtest du installieren? (Leertaste = auswählen)" \
    runtime  "Java Runtime (OpenJDK 21)"                 OFF \
    prism    "Prism Launcher (empfohlen, Mods/Instanzen)" ON  \
    official "Offizieller Minecraft Launcher (Flatpak)"   OFF \
    server   "Java Server (Mojang, neueste Version)"      OFF)" || return 0

  [[ -z "$sel" ]] && { warn "Nichts ausgewählt."; pause; return 0; }

  local item
  for item in $sel; do
    item="${item//\"/}"
    case "$item" in
      runtime)  install_java_runtime ;;
      prism)    install_java_prism ;;
      official) install_java_official ;;
      server)
        local dir
        dir="$(ask_input "Installationsordner für den Server:" "$SERVER_DIR_DEFAULT")" || continue
        install_java_server "$dir" ;;
    esac
  done
  pause
}

menu_bedrock() {
  local sel
  sel="$(checklist "Bedrock Edition" "Was möchtest du installieren? (Leertaste = auswählen)" \
    launcher "Minecraft Bedrock Launcher (mcpelauncher, Flatpak)" ON)" || return 0

  [[ -z "$sel" ]] && { warn "Nichts ausgewählt."; pause; return 0; }

  local item
  for item in $sel; do
    item="${item//\"/}"
    case "$item" in
      launcher) install_bedrock_launcher ;;
    esac
  done
  pause
}

menu_uninstall() {
  local sel
  sel="$(checklist "Deinstallieren" "Was soll entfernt werden?" \
    prism    "Prism Launcher"                OFF \
    official "Offizieller Minecraft Launcher" OFF \
    bedrock  "Bedrock Launcher"              OFF)" || return 0

  [[ -z "$sel" ]] && { warn "Nichts ausgewählt."; pause; return 0; }

  if ask_yesno "Ausgewählte Programme wirklich entfernen?"; then
    local item
    for item in $sel; do
      item="${item//\"/}"
      uninstall_menu_action "$item"
    done
  fi
  pause
}

show_system_info() {
  clear
  echo "=== Systeminformationen ==="
  echo "Distribution : ${DISTRO}"
  echo "Paketmanager : ${PM:-keiner erkannt}"
  echo "Architektur  : $(uname -m)"
  echo "Flatpak      : $(has flatpak && flatpak --version || echo nicht installiert)"
  echo "Java         : $(has java && java -version 2>&1 | head -n1 || echo nicht installiert)"
  echo "Menü-Backend : ${UI}"
  if [[ "$(uname -m)" != "x86_64" && "$(uname -m)" != "aarch64" ]]; then
    warn "Nicht-unterstützte Architektur – manche Programme laufen eventuell nicht."
  fi
  pause
}

main_menu() {
  while true; do
    local choice
    choice="$(menu "$TITLE" "Distribution: ${DISTRO}\nWas möchtest du tun?" \
      java      "Java Edition installieren" \
      bedrock   "Bedrock Edition installieren" \
      uninstall "Programme deinstallieren" \
      info      "Systeminformationen" \
      quit      "Beenden")" || break

    case "$choice" in
      java)      menu_java ;;
      bedrock)   menu_bedrock ;;
      uninstall) menu_uninstall ;;
      info)      show_system_info ;;
      quit)      break ;;
    esac
  done
  clear
  echo "Viel Spaß beim Spielen!"
}

# --------------------------------------------------------------------------
# Start
# --------------------------------------------------------------------------
usage() {
  cat <<EOF
${TITLE}

Nutzung: $0 [Option]

  -h, --help      Diese Hilfe anzeigen
  -v, --version   Version anzeigen
  --text          Textmenü erzwingen (kein whiptail/dialog)
EOF
}

main() {
  local force_text=0
  case "${1:-}" in
    -h|--help)    usage; exit 0 ;;
    -v|--version) echo "$VERSION"; exit 0 ;;
    --text)       force_text=1 ;;
  esac

  if [[ "$(uname -s)" != "Linux" ]]; then
    err "Dieses Skript funktioniert nur unter Linux."
    exit 1
  fi

  detect_distro
  detect_ui
  [[ $force_text -eq 1 ]] && UI="text"

  if [[ -z "$PM" ]]; then
    warn "Kein unterstützter Paketmanager erkannt – nur Flatpak-Installationen sind eventuell möglich."
  fi

  if [[ "$UI" == "text" ]] && [[ $force_text -eq 0 ]]; then
    warn "whiptail/dialog nicht gefunden – verwende Textmenü."
  fi

  main_menu
}

main "$@"