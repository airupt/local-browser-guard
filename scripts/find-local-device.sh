#!/usr/bin/env bash
#
# find-local-device.sh - work out which Claude in Chrome deviceId actually
# lives in a browser profile on THIS machine.
#
# The Chrome extension writes its bridgeDeviceId into the profile's extension
# storage. A browser paired from someone else's machine never leaves that
# trace here, so "the id is on disk" is the one reliable local signal.
#
# Usage:
#   find-local-device.sh                      # report every local deviceId
#   find-local-device.sh <id> [<id> ...]      # keep only these ids
#   echo '<list_connected_browsers json>' | find-local-device.sh
#
# Exit codes:
#   0  exactly one local match (safe to select_browser)
#   3  no local match
#   4  more than one local match
#   1  usage or environment error

set -uo pipefail

# Profile stores are binary LevelDB files; a UTF-8 locale makes grep and sort
# bail out with "Illegal byte sequence" on them.
export LC_ALL=C

UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
DEEP=0
QUIET=0
MAXDEPTH="${LBG_MAXDEPTH:-8}"

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

candidates=()
for arg in "$@"; do
  case "$arg" in
    --deep)  DEEP=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help) usage ;;
    -*) echo "unknown flag: $arg" >&2; exit 1 ;;
    *) candidates+=("$arg") ;;
  esac
done

# Accept the raw list_connected_browsers payload on stdin too.
if [ ${#candidates[@]} -eq 0 ] && [ ! -t 0 ]; then
  stdin_blob="$(cat)"
  if [ -n "$stdin_blob" ]; then
    while IFS= read -r id; do
      [ -n "$id" ] && candidates+=("$id")
    done < <(printf '%s' "$stdin_blob" | grep -oE "$UUID_RE" | sort -u)
  fi
fi

# ---------------------------------------------------------------- roots ----
to_unix_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
  else printf '%s' "$1" | sed 's#\\#/#g; s#^\([A-Za-z]\):#/\l\1#'; fi
}

roots=()
platform="unknown"
case "$(uname -s 2>/dev/null)" in
  Darwin)
    platform="macos"
    roots+=("$HOME/Library/Application Support")
    ;;
  Linux)
    platform="linux"
    roots+=("$HOME/.config")
    [ -d "$HOME/snap" ] && roots+=("$HOME/snap")
    [ -d "$HOME/.var/app" ] && roots+=("$HOME/.var/app")
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    platform="windows"
    [ -n "${LOCALAPPDATA:-}" ] && roots+=("$(to_unix_path "$LOCALAPPDATA")")
    [ -n "${APPDATA:-}" ]      && roots+=("$(to_unix_path "$APPDATA")")
    ;;
esac

existing_roots=()
for r in ${roots[@]+"${roots[@]}"}; do
  [ -d "$r" ] && existing_roots+=("$r")
done

if [ ${#existing_roots[@]} -eq 0 ]; then
  printf '{"platform":"%s","error":"no browser profile root found","count":0,"matches":[]}\n' "$platform"
  exit 1
fi

# ------------------------------------------------------------ scan dirs ----
# Chromium profiles keep extension storage in "Local Extension Settings".
# Finding those directories first keeps the grep off the rest of the disk.
scan_dirs=()
while IFS= read -r d; do
  [ -n "$d" ] && scan_dirs+=("$d")
done < <(find "${existing_roots[@]}" -maxdepth "$MAXDEPTH" -type d \
           \( -name "Local Extension Settings" -o -name "Sync Extension Settings" \) 2>/dev/null)

if [ "$DEEP" -eq 1 ] || [ ${#scan_dirs[@]} -eq 0 ]; then
  scan_dirs=("${existing_roots[@]}")
fi

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Name the browser from the vendor folder in the path.
browser_of() {
  case "$1" in
    *BraveSoftware*)                 echo "Brave" ;;
    *"Google/Chrome Beta"*|*"Google\\Chrome Beta"*)   echo "Chrome Beta" ;;
    *"Google/Chrome Canary"*|*Chrome*SxS*)            echo "Chrome Canary" ;;
    *"Google/Chrome Dev"*)            echo "Chrome Dev" ;;
    *Google*Chrome*)                 echo "Chrome" ;;
    *Microsoft*Edge*)                echo "Edge" ;;
    *Arc*)                           echo "Arc" ;;
    *Vivaldi*)                       echo "Vivaldi" ;;
    *[Oo]pera*)                      echo "Opera" ;;
    *Chromium*)                      echo "Chromium" ;;
    *Dia*)                           echo "Dia" ;;
    *Comet*|*Perplexity*)            echo "Comet" ;;
    *Sidekick*)                      echo "Sidekick" ;;
    *Yandex*)                        echo "Yandex" ;;
    *) echo "unknown" ;;
  esac
}

# The profile is the directory holding "Local Extension Settings".
profile_of() {
  local p="$1"
  case "$p" in
    */Local\ Extension\ Settings/*) echo "${p%%/Local Extension Settings/*}" ;;
    */Sync\ Extension\ Settings/*)  echo "${p%%/Sync Extension Settings/*}" ;;
    *) dirname "$p" ;;
  esac
}

emit() {  # deviceId, file path
  local id="$1" file="$2" prof brow
  prof="$(profile_of "$file")"
  brow="$(browser_of "$file")"
  printf '{"deviceId":"%s","browser":"%s","profile":"%s","evidence":"%s"}' \
    "$(json_escape "$id")" "$(json_escape "$brow")" \
    "$(json_escape "$(basename "$prof")")" "$(json_escape "$file")"
}

matches=()
widened=0

scan_for_candidates() {
  local id hit
  matches=()
  for id in "${candidates[@]}"; do
    hit="$(grep -rlaF -- "$id" "${scan_dirs[@]}" 2>/dev/null | head -1)"
    [ -n "$hit" ] && matches+=("$(emit "$id" "$hit")")
  done
}

if [ ${#candidates[@]} -gt 0 ]; then
  # Filter mode: look for each supplied id.
  scan_for_candidates
  # A browser that keeps the id somewhere other than extension storage would
  # look like "not on this machine". Widen to the whole profile root before
  # reporting nothing, so a miss is a real miss.
  if [ ${#matches[@]} -eq 0 ] && [ "$DEEP" -eq 0 ]; then
    scan_dirs=("${existing_roots[@]}")
    widened=1
    scan_for_candidates
  fi
else
  # Harvest mode: pull every bridgeDeviceId written on this machine.
  while IFS= read -r line; do
    file="${line%%:*}"
    id="$(printf '%s' "${line#*:}" | grep -oE "$UUID_RE" | head -1)"
    [ -n "$id" ] && matches+=("$(emit "$id" "$file")")
  done < <(grep -rhoaE "bridgeDeviceId.{0,8}$UUID_RE" "${scan_dirs[@]}" 2>/dev/null \
           | sort -u \
           | while IFS= read -r m; do
               f="$(grep -rlaF -- "$m" "${scan_dirs[@]}" 2>/dev/null | head -1)"
               printf '%s:%s\n' "$f" "$m"
             done)
fi

# De-duplicate on deviceId.
if [ ${#matches[@]} -gt 1 ]; then
  mapfile -t matches < <(printf '%s\n' "${matches[@]}" | awk '!seen[$0]++')
fi

count=${#matches[@]}
roots_json=""
for r in "${existing_roots[@]}"; do
  roots_json="$roots_json,\"$(json_escape "$r")\""
done
roots_json="[${roots_json#,}]"

if [ "$QUIET" -eq 0 ]; then
  printf '{"platform":"%s","scanned_roots":%s,"scan_dir_count":%s,"widened_scan":%s,"candidates":%s,"count":%s,"matches":[%s]}\n' \
    "$platform" "$roots_json" "${#scan_dirs[@]}" "$widened" "${#candidates[@]}" "$count" \
    "$(IFS=,; echo "${matches[*]-}")"
fi

case "$count" in
  1) exit 0 ;;
  0) exit 3 ;;
  *) exit 4 ;;
esac
