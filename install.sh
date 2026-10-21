#!/usr/bin/env bash
# =============================================================================
#  Minecraft Linux Installer
#  Java Edition & Bedrock Edition – mit eigener TUI (reines Bash, keine Extras)
# =============================================================================
set -uo pipefail

VERSION="2.0.0"
APP="Minecraft Installer"
SERVER_DIR_DEFAULT="${HOME}/minecraft-server"
MANIFEST_URL="https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
FLATHUB_URL="https://dl.flathub.org/repo/flathub.flatpakrepo"

ID_PRISM="org.prismlauncher.PrismLauncher"
ID_OFFICIAL="com.mojang.Minecraft"
ID_BEDROCK="io.mrarm.mcpelauncher"

LOG="$(mktemp "${TMPDIR:-/tmp}/mc-installer.XXXXXX")"
TOTAL_FAILS=0
FAILS=0

# --------------------------------------------------------------------------
# Optik
# --------------------------------------------------------------------------
ESC=$'\e'
R="${ESC}[0m"; B="${ESC}[1m"; DIM="${ESC}[2m"
ACC="${ESC}[38;5;78m"; RED="${ESC}[38;5;203m"; YEL="${ESC}[38;5;221m"

frame=""
f()     { frame+="$*"$'\n'; }
flush() { printf '%s' "${ESC}[H${ESC}[J${frame}"; frame=""; }

cur_show() { printf '%s' "${ESC}[?25h"; }
cur_hide() { printf '%s' "${ESC}[?25l"; }

has() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------
# System
# --------------------------------------------------------------------------
PM=""; DISTRO="Linux"; ARCH="$(uname -m)"
if (( EUID == 0 )); then SUDO=""; else SUDO="sudo"; fi

detect_system() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO="${PRETTY_NAME:-${NAME:-Linux}}"
  fi
  if   has apt-get; then PM="apt"
  elif has dnf;     then PM="dnf"
  elif has pacman;  then PM="pacman"
  elif has zypper;  then PM="zypper"
  fi
}

# --------------------------------------------------------------------------
# Eingabe
# --------------------------------------------------------------------------
read_key() {
  local k rest=""
  IFS= read -rsn1 k || { echo quit; return; }
  if [[ $k == "$ESC" ]]; then
    IFS= read -rsn2 -t 0.01 rest || true
    k+="$rest"
  fi
  case "$k" in
    "${ESC}[A"|"${ESC}OA"|k|K) echo up ;;
    "${ESC}[B"|"${ESC}OB"|j|J) echo down ;;
    "${ESC}[C"|"${ESC}OC"|l)   echo right ;;
    "${ESC}[D"|"${ESC}OD"|h)   echo left ;;
    "")                        echo enter ;;
    " ")                       echo space ;;
    q|Q)                       echo quit ;;
    y|Y)                       echo yes ;;
    n|N)                       echo no ;;
    "$ESC")                    echo esc ;;
    *)                         echo other ;;
  esac
}

# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------
header() {
  local w line
  w=$(( $(tput cols 2>/dev/null || echo 80) - 4 ))
  (( w > 64 )) && w=64
  (( w < 40 )) && w=40
  printf -v line '%*s' "$w" ''
  line="${line// /─}"
  f ""
  f "  ${ACC}${B}⛏  ${APP}${R}${DIM}   v${VERSION}${R}"
  f "  ${DIM}${line}${R}"
  f "  ${DIM}${DISTRO} · ${PM:-kein Paketmanager} · ${ARCH}${R}"
  f ""
}

# tui_menu TITEL ARRAYNAME [START]  ->  MENU_RESULT = Tag, Rückgabe 1 bei "zurück"
# Eintrag: tag|Label|Beschreibung
tui_menu() {
  local title="$1"; local -n _m="$2"
  local cur="${3:-0}" n=${#_m[@]} i key tag label desc pad
  while true; do
    header
    f "  ${B}${title}${R}"
    f ""
    for i in "${!_m[@]}"; do
      IFS='|' read -r tag label desc <<<"${_m[$i]}"
      printf -v pad '%-26s' "$label"
      if (( i == cur )); then
        f "  ${ACC}❯ ${B}${pad}${R} ${desc}"
      else
        f "    ${pad} ${DIM}${desc}${R}"
      fi
    done
    f ""
    f "  ${DIM}↑/↓ bewegen    Enter wählen    q zurück${R}"
    flush
    key="$(read_key)"
    case "$key" in
      up)         cur=$(( (cur - 1 + n) % n )) ;;
      down)       cur=$(( (cur + 1) % n )) ;;
      enter)      IFS='|' read -r MENU_RESULT _ <<<"${_m[$cur]}"; return 0 ;;
      quit|esc)   return 1 ;;
    esac
  done
}

# tui_multi TITEL ARRAYNAME  ->  CHOSEN (Array von Tags), Rückgabe 1 bei "zurück"
# Eintrag: tag|Label|Beschreibung|vorausgewählt(1/0)
tui_multi() {
  local title="$1"; local -n _x="$2"
  local cur=0 n=${#_x[@]} i key tag label desc on mark pad
  local -a state=()
  for i in "${!_x[@]}"; do
    IFS='|' read -r _ _ _ on <<<"${_x[$i]}"
    state[i]="${on:-0}"
  done
  while true; do
    header
    f "  ${B}${title}${R}"
    f ""
    for i in "${!_x[@]}"; do
      IFS='|' read -r tag label desc _ <<<"${_x[$i]}"
      if (( state[i] )); then mark="${ACC}◉${R}"; else mark="${DIM}○${R}"; fi
      printf -v pad '%-24s' "$label"
      if (( i == cur )); then
        f "  ${ACC}❯${R} ${mark} ${B}${pad}${R} ${desc}"
      else
        f "    ${mark} ${pad} ${DIM}${desc}${R}"
      fi
    done
    f ""
    f "  ${DIM}↑/↓ bewegen    Leertaste auswählen    Enter bestätigen    q zurück${R}"
    flush
    key="$(read_key)"
    case "$key" in
      up)       cur=$(( (cur - 1 + n) % n )) ;;
      down)     cur=$(( (cur + 1) % n )) ;;
      space)    state[cur]=$(( 1 - state[cur] )) ;;
      enter)
        CHOSEN=()
        for i in "${!_x[@]}"; do
          if (( state[i] )); then
            IFS='|' read -r tag _ <<<"${_x[$i]}"
            CHOSEN+=("$tag")
          fi
        done
        return 0 ;;
      quit|esc) return 1 ;;
    esac
  done
}

# tui_confirm TITEL [INFO]  ->  Rückgabe 0 = Ja, 1 = Nein
tui_confirm() {
  local title="$1" info="${2:-}" sel=0 key yes no
  while true; do
    header
    f "  ${B}${title}${R}"
    [[ -n "$info" ]] && f "  ${DIM}${info}${R}"
    f ""
    if (( sel == 0 )); then
      yes="${ACC}${B}❯ Ja${R}"; no="${DIM}  Nein${R}"
    else
      yes="${DIM}  Ja${R}";     no="${ACC}${B}❯ Nein${R}"
    fi
    f "  ${yes}     ${no}"
    f ""
    f "  ${DIM}←/→ wählen    Enter bestätigen    y / n${R}"
    flush
    key="$(read_key)"
    case "$key" in
      left|right|up|down) sel=$(( 1 - sel )) ;;
      yes)                return 0 ;;
      no|quit|esc)        return 1 ;;
      enter)              return "$sel" ;;
    esac
  done
}

# tui_input TITEL STANDARD  ->  INPUT_RESULT
tui_input() {
  local v
  header
  f "  ${B}$1${R}"
  f "  ${DIM}Enter zum Bestätigen${R}"
  f ""
  flush
  printf '  %s❯%s ' "$ACC" "$R"
  cur_show
  IFS= read -e -r -i "$2" v || v="$2"
  cur_hide
  v="${v:-$2}"
  INPUT_RESULT="${v/#\~/$HOME}"
}

# --------------------------------------------------------------------------
# Ausgabe-Bildschirm & Schritte
# --------------------------------------------------------------------------
screen() {
  FAILS=0
  header
  f "  ${B}$1${R}"
  f ""
  flush
}

note()      { printf '  %s%s%s\n' "$DIM" "$*" "$R"; }
note_warn() { printf '  %s!%s %s\n' "$YEL" "$R" "$*"; }
note_err()  { printf '  %s✖%s %s\n' "$RED" "$R" "$*"; }

wait_key() {
  printf '\n  %sEnter drücken, um zurückzukehren …%s' "$DIM" "$R"
  IFS= read -rsn1 _ || true
}

finish() {
  echo
  if (( FAILS == 0 )); then
    printf '  %s✔ Fertig.%s\n' "$ACC$B" "$R"
  else
    printf '  %s✖ %d Schritt(e) fehlgeschlagen.%s %sLog: %s%s\n' "$RED" "$FAILS" "$R" "$DIM" "$LOG" "$R"
  fi
  wait_key
}

# run_step "Beschreibung" befehl args ...
run_step() {
  local msg="$1"; shift
  local -a frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i=0 pid rc
  printf '\n### %s\n' "$msg" >>"$LOG"
  "$@" </dev/null >>"$LOG" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s' "$ACC" "${frames[i % 10]}" "$R" "$msg"
    i=$(( i + 1 ))
    sleep 0.1
  done
  wait "$pid"; rc=$?
  if (( rc == 0 )); then
    printf '\r%s  %s✔%s %s\n' "${ESC}[K" "$ACC" "$R" "$msg"
  else
    printf '\r%s  %s✖%s %s\n' "${ESC}[K" "$RED" "$R" "$msg"
    tail -n 6 "$LOG" | sed "s/^/      ${DIM}/; s/\$/${R}/"
    FAILS=$(( FAILS + 1 ))
    TOTAL_FAILS=$(( TOTAL_FAILS + 1 ))
  fi
  return "$rc"
}

# --------------------------------------------------------------------------
# Adminrechte, Pakete, Flatpak
# --------------------------------------------------------------------------
ADMIN_OK=""
need_admin() {
  if [[ -z "$ADMIN_OK" ]]; then
    if (( EUID == 0 )); then
      ADMIN_OK=0
    elif ! has sudo; then
      note_err "sudo nicht gefunden – bitte als root ausführen."
      ADMIN_OK=1
    else
      note "Administratorrechte werden benötigt."
      cur_show
      sudo -v
      ADMIN_OK=$?
      cur_hide
      (( ADMIN_OK != 0 )) && note_err "Authentifizierung fehlgeschlagen."
    fi
  fi
  return "$ADMIN_OK"
}

pkg_install() {
  case "$PM" in
    apt)    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
    *)      echo "Kein unterstützter Paketmanager gefunden."; return 1 ;;
  esac
}

INDEX_DONE=0
refresh_index() {
  if [[ "$PM" == "apt" && $INDEX_DONE -eq 0 ]]; then
    run_step "Paketlisten aktualisieren" $SUDO apt-get update || return 1
    INDEX_DONE=1
  fi
  return 0
}

# pkg_step "Beschreibung" paket ...
pkg_step() {
  local msg="$1"; shift
  need_admin || return 1
  refresh_index || return 1
  run_step "$msg" pkg_install "$@"
}

ensure_flatpak() {
  need_admin || return 1
  if ! has flatpak; then
    pkg_step "Flatpak installieren" flatpak || return 1
    note_warn "Nach der Flatpak-Installation ist evtl. ein Neustart nötig, damit Apps im Menü erscheinen."
  fi
  if ! flatpak remotes --system --columns=name 2>/dev/null | grep -qx flathub; then
    run_step "Flathub einrichten" $SUDO flatpak remote-add --if-not-exists --system flathub "$FLATHUB_URL" || return 1
  fi
  return 0
}

install_flatpak_app() {  # id name
  ensure_flatpak || return 1
  run_step "$2 installieren" $SUDO flatpak install -y --noninteractive --system flathub "$1"
}

INSTALLED=""
refresh_installed() {
  INSTALLED=""
  has flatpak && INSTALLED="$(flatpak list --app --columns=application 2>/dev/null)"
}
is_installed() { grep -qx "$1" <<<"$INSTALLED"; }
mark() { if is_installed "$1"; then printf ' · ✔ installiert'; fi; }

# --------------------------------------------------------------------------
# Java
# --------------------------------------------------------------------------
java_major() {
  has java || { echo 0; return; }
  java -version 2>&1 | awk -F'"' '/version/ { split($2, a, "."); print (a[1] == 1 ? a[2] : a[1]); exit }'
}
java_ok() { local m; m="$(java_major)"; (( ${m:-0} >= 21 )); }

java_install() {  # headless|full
  local sfx=""
  [[ "$1" == "headless" ]] && sfx="-headless"
  case "$PM" in
    apt)         pkg_install "openjdk-21-jre${sfx}" || pkg_install "openjdk-17-jre${sfx}" ;;
    dnf|zypper)  pkg_install "java-21-openjdk${sfx}" || pkg_install "java-17-openjdk${sfx}" ;;
    pacman)      pkg_install "jre21-openjdk${sfx}" || pkg_install "jre17-openjdk${sfx}" ;;
    *)           return 1 ;;
  esac
}

java_step() {  # headless|full
  need_admin || return 1
  refresh_index || return 1
  run_step "Java installieren (OpenJDK 21)" java_install "$1" || return 1
  if ! java_ok; then
    note_warn "Es wurde nur Java $(java_major) gefunden – neue Minecraft-Versionen benötigen Java 21."
  fi
  return 0
}

server_download() {
  local dir="$1" manifest latest vurl meta surl sha
  mkdir -p "$dir" || return 1
  manifest="$(curl -fsSL "$MANIFEST_URL")" || return 1
  latest="$(jq -r '.latest.release' <<<"$manifest")"
  vurl="$(jq -r --arg v "$latest" '.versions[] | select(.id==$v) | .url' <<<"$manifest")"
  meta="$(curl -fsSL "$vurl")" || return 1
  surl="$(jq -r '.downloads.server.url // empty' <<<"$meta")"
  sha="$(jq -r '.downloads.server.sha1 // empty' <<<"$meta")"
  [[ -n "$surl" ]] || { echo "Kein Server-Download für ${latest} gefunden."; return 1; }
  curl -fsSL -o "${dir}/server.jar" "$surl" || return 1
  if [[ -n "$sha" ]]; then
    echo "${sha}  ${dir}/server.jar" | sha1sum -c - || return 1
  fi
  echo "$latest" >"${dir}/.mc-version"
}

write_server_files() {  # dir ram eula(0/1)
  local dir="$1" ram="$2" eula="$3"
  cat >"${dir}/start.sh" <<EOF
#!/usr/bin/env bash
cd "\$(dirname "\$0")" || exit 1
exec java -Xms${ram} -Xmx${ram} -jar server.jar nogui
EOF
  chmod +x "${dir}/start.sh"
  if [[ "$eula" == "1" ]]; then echo "eula=true" >"${dir}/eula.txt"; fi
  return 0
}

# Abfragen für den Server, bevor der Ausgabe-Bildschirm startet
SRV_DIR=""; SRV_RAM="2G"; SRV_EULA=0
server_prompt() {
  tui_input "Installationsordner für den Java-Server" "$SERVER_DIR_DEFAULT"
  SRV_DIR="$INPUT_RESULT"

  local -a ram_items=(
    "1G|1 GB|kleine Welten, wenige Spieler"
    "2G|2 GB|empfohlener Standard"
    "4G|4 GB|mehr Spieler oder Mods"
    "8G|8 GB|große Server"
  )
  tui_menu "Arbeitsspeicher für den Server" ram_items 1 || return 1
  SRV_RAM="$MENU_RESULT"

  if tui_confirm "Minecraft EULA akzeptieren?" "https://aka.ms/MinecraftEULA"; then
    SRV_EULA=1
  else
    SRV_EULA=0
  fi
  return 0
}

install_java_server() {
  local -a need=()
  has curl || need+=(curl)
  has jq   || need+=(jq)
  if (( ${#need[@]} )); then
    pkg_step "Werkzeuge installieren (${need[*]})" "${need[@]}" || return 1
  fi
  if ! java_ok; then
    java_step headless || return 1
  fi
  run_step "Server herunterladen & prüfen" server_download "$SRV_DIR" || return 1
  run_step "Startskript erstellen" write_server_files "$SRV_DIR" "$SRV_RAM" "$SRV_EULA" || return 1

  local ver; ver="$(cat "${SRV_DIR}/.mc-version" 2>/dev/null)"
  echo
  note "Version ${ver} liegt in ${SRV_DIR}"
  note "Starten:  ${SRV_DIR}/start.sh"
  if (( SRV_EULA == 0 )); then
    note_warn "EULA nicht akzeptiert – setze 'eula=true' in ${SRV_DIR}/eula.txt vor dem Start."
  fi
  note "Port 25565 (TCP) muss in der Firewall offen sein, damit andere beitreten können."
}

# --------------------------------------------------------------------------
# Menüs
# --------------------------------------------------------------------------
no_desktop_hint() {
  if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    note_warn "Kein Desktop erkannt – Launcher brauchen eine grafische Oberfläche."
  fi
}

menu_java() {
  refresh_installed
  local -a items=(
    "runtime|Java Runtime|OpenJDK 21|0"
    "prism|Prism Launcher|Mods & Instanzen (empfohlen)$(mark "$ID_PRISM")|1"
    "official|Offizieller Launcher|Flatpak$(mark "$ID_OFFICIAL")|0"
    "server|Java-Server|neueste Version direkt von Mojang|0"
  )
  tui_multi "Java Edition" items || return 0
  (( ${#CHOSEN[@]} )) || return 0

  local t want_server=0
  for t in "${CHOSEN[@]}"; do [[ "$t" == server ]] && want_server=1; done
  if (( want_server )); then
    server_prompt || return 0
  fi

  screen "Java Edition installieren"
  for t in "${CHOSEN[@]}"; do
    case "$t" in
      runtime)  java_step full ;;
      prism)    no_desktop_hint; install_flatpak_app "$ID_PRISM" "Prism Launcher" ;;
      official) no_desktop_hint; install_flatpak_app "$ID_OFFICIAL" "Offizieller Launcher" ;;
      server)   install_java_server ;;
    esac
  done
  finish
}

menu_bedrock() {
  refresh_installed
  local -a items=(
    "launcher|Bedrock Launcher|mcpelauncher (Flatpak)$(mark "$ID_BEDROCK")|1"
  )
  tui_multi "Bedrock Edition" items || return 0
  (( ${#CHOSEN[@]} )) || return 0

  screen "Bedrock Edition installieren"
  no_desktop_hint
  if install_flatpak_app "$ID_BEDROCK" "Bedrock Launcher"; then
    echo
    note "Benötigt eine legale Android-Kopie von Minecraft Bedrock (Google-Play-Konto),"
    note "einen OpenGL-fähigen Grafiktreiber und ein 64-Bit-System."
  fi
  finish
}

menu_remove() {
  refresh_installed
  local -a items=()
  is_installed "$ID_PRISM"    && items+=("${ID_PRISM}|Prism Launcher||0")
  is_installed "$ID_OFFICIAL" && items+=("${ID_OFFICIAL}|Offizieller Launcher||0")
  is_installed "$ID_BEDROCK"  && items+=("${ID_BEDROCK}|Bedrock Launcher||0")

  if (( ${#items[@]} == 0 )); then
    screen "Deinstallieren"
    note "Es sind keine Launcher über Flatpak installiert."
    wait_key
    return 0
  fi

  tui_multi "Deinstallieren" items || return 0
  (( ${#CHOSEN[@]} )) || return 0
  tui_confirm "Ausgewählte Launcher wirklich entfernen?" || return 0

  screen "Deinstallieren"
  need_admin || { finish; return 0; }
  local id
  for id in "${CHOSEN[@]}"; do
    run_step "${id} entfernen" $SUDO flatpak uninstall -y --noninteractive --system "$id"
  done
  finish
}

main_menu() {
  local -a items=(
    "java|Java Edition|Launcher, Runtime & Server"
    "bedrock|Bedrock Edition|Launcher"
    "remove|Deinstallieren|installierte Launcher entfernen"
    "exit|Beenden|"
  )
  while tui_menu "Was möchtest du tun?" items; do
    case "$MENU_RESULT" in
      java)    menu_java ;;
      bedrock) menu_bedrock ;;
      remove)  menu_remove ;;
      exit)    break ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Start / Ende
# --------------------------------------------------------------------------
cleanup() {
  printf '%s' "${ESC}[?25h${ESC}[?1049l"
  stty sane 2>/dev/null || true
  if (( TOTAL_FAILS > 0 )); then
    printf 'Es gab Fehler. Log: %s\n' "$LOG"
  else
    rm -f "$LOG"
  fi
}

usage() {
  cat <<EOF
${APP} v${VERSION}

Nutzung: $0 [Option]

  -h, --help      Diese Hilfe anzeigen
  -v, --version   Version anzeigen

Bedienung: Pfeiltasten (oder j/k) · Leertaste auswählen · Enter bestätigen · q zurück
EOF
}

main() {
  case "${1:-}" in
    -h|--help)    usage; exit 0 ;;
    -v|--version) echo "$VERSION"; exit 0 ;;
  esac

  if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Dieses Skript funktioniert nur unter Linux." >&2; exit 1
  fi
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "Bash 4.3 oder neuer wird benötigt." >&2; exit 1
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    echo "Bitte in einem interaktiven Terminal starten." >&2; exit 1
  fi

  detect_system
  trap cleanup EXIT
  trap 'exit 130' INT TERM
  printf '%s' "${ESC}[?1049h"
  cur_hide
  main_menu
}

main "$@"