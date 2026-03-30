#!/usr/bin/env bash
set -euo pipefail

SOURCE=""
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="codex-main"
NO_BACKUP=false
CONFIG_EDIT=true
TMP_WORK=""

usage() {
  cat <<USAGE
Usage: ./scripts/install-release-main.sh --source <path-or-url> [options]

Installs a prebuilt patched Codex binary for the main-track test path.

Options:
  --source <path-or-url>  Local file path or HTTP(S) URL to binary or tarball.
  --install-dir <path>    Install directory (default: ~/.local/bin).
  --binary-name <name>    Output binary name (default: codex-main).
  --no-backup             Skip backup.
  --no-config-edit        Do not modify ~/.codex/config.toml.
  -h, --help              Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
      shift 2
      ;;
    --binary-name)
      BINARY_NAME="$2"
      shift 2
      ;;
    --no-backup)
      NO_BACKUP=true
      shift
      ;;
    --no-config-edit)
      CONFIG_EDIT=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  echo "Missing required --source <path-or-url>." >&2
  exit 1
fi

if [[ ! "$BINARY_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid --binary-name '$BINARY_NAME' (allowed: letters, digits, ., _, -)." >&2
  exit 1
fi

TARGET="$INSTALL_DIR/$BINARY_NAME"
echo "Will install test binary to: $TARGET"

echo

echo "[1/3] Preparing binary source"
TMP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/codex-release-main-install-XXXXXX")"
cleanup() {
  if [[ -n "$TMP_WORK" && -d "$TMP_WORK" ]]; then
    rm -rf "$TMP_WORK"
  fi
}
trap cleanup EXIT

SOURCE_FILE="$TMP_WORK/source"
if [[ "$SOURCE" =~ ^https?:// ]]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to download URL sources." >&2
    exit 1
  fi
  curl -fL --retry 3 "$SOURCE" -o "$SOURCE_FILE"
else
  if [[ ! -f "$SOURCE" ]]; then
    echo "Local source file not found: $SOURCE" >&2
    exit 1
  fi
  cp "$SOURCE" "$SOURCE_FILE"
fi

BUILT_BINARY=""
if [[ -x "$SOURCE_FILE" ]] && ! tar -tf "$SOURCE_FILE" >/dev/null 2>&1; then
  BUILT_BINARY="$SOURCE_FILE"
else
  mkdir -p "$TMP_WORK/extracted"
  if ! tar -xf "$SOURCE_FILE" -C "$TMP_WORK/extracted" >/dev/null 2>&1; then
    echo "Source is neither an executable binary nor a readable tar archive: $SOURCE" >&2
    exit 1
  fi
  BUILT_BINARY="$(find "$TMP_WORK/extracted" -type f -name codex -perm -u+x | head -n 1 || true)"
  if [[ -z "$BUILT_BINARY" ]]; then
    BUILT_BINARY="$(find "$TMP_WORK/extracted" -type f -name codex | head -n 1 || true)"
  fi
  if [[ -z "$BUILT_BINARY" ]]; then
    echo "Could not find a codex binary inside the archive." >&2
    exit 1
  fi
  chmod +x "$BUILT_BINARY"
fi

echo "[2/3] Installing to $TARGET"

stop_running_binary() {
  local target="$1"
  local target_real pids remaining pid
  target_real="$(readlink -f "$target" 2>/dev/null || echo "$target")"
  pids=""

  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t "$target_real" 2>/dev/null | sort -u | tr '\n' ' ' || true)"
  fi

  if [[ -z "${pids// }" ]] && command -v pgrep >/dev/null 2>&1; then
    pids="$(pgrep -f "$target_real" 2>/dev/null | tr '\n' ' ' || true)"
  fi

  if [[ -z "${pids// }" ]]; then
    return
  fi

  echo "  Stopping running processes using target binary: $pids"
  kill $pids 2>/dev/null || true
  sleep 1

  remaining=""
  for pid in $pids; do
    if kill -0 "$pid" 2>/dev/null; then
      remaining+="$pid "
    fi
  done

  if [[ -n "${remaining// }" ]]; then
    echo "  Forcing stop of remaining processes: $remaining"
    kill -9 $remaining 2>/dev/null || true
    sleep 0.2
  fi
}

stop_running_binary "$TARGET"

do_install() {
  local use_sudo="$1"
  local cmd_prefix=""
  local tmp_target
  [[ "$use_sudo" == true ]] && cmd_prefix="sudo"
  tmp_target="${TARGET}.new.$$"

  if [[ "$use_sudo" == true ]]; then
    $cmd_prefix mkdir -p "$INSTALL_DIR"
  else
    mkdir -p "$INSTALL_DIR"
  fi

  if [[ -f "$TARGET" && "$NO_BACKUP" != true ]]; then
    BACKUP="${TARGET}.bak"
    echo "  Backing up existing binary -> $BACKUP"
    $cmd_prefix cp "$TARGET" "$BACKUP"
  fi

  $cmd_prefix cp "$BUILT_BINARY" "$tmp_target"
  $cmd_prefix chmod +x "$tmp_target"
  $cmd_prefix mv -f "$tmp_target" "$TARGET"
}

if [[ -w "$INSTALL_DIR" ]]; then
  do_install false
else
  echo "  $INSTALL_DIR is not writable; requesting sudo."
  do_install true
fi

set_tool_output_display_full() {
  local config_dir="$HOME/.codex"
  local config_file="$config_dir/config.toml"
  mkdir -p "$config_dir"

  if [[ ! -f "$config_file" ]]; then
    cat >"$config_file" <<'CFG'
[tui]
tool_output_display = "full"
CFG
    return
  fi

  local tmp
  tmp="$(mktemp)"
  awk '
BEGIN {
  in_tui = 0
  found_tui = 0
  updated = 0
}
function emit_setting() {
  print "tool_output_display = \"full\""
  updated = 1
}
/^\[[^]]+\][[:space:]]*$/ {
  if (in_tui && !updated) {
    emit_setting()
  }
  in_tui = ($0 ~ /^\[tui\][[:space:]]*$/)
  if (in_tui) {
    found_tui = 1
  }
  print
  next
}
{
  if (in_tui && $0 ~ /^[[:space:]]*tool_output_display[[:space:]]*=/) {
    print "tool_output_display = \"full\""
    updated = 1
    next
  }
  print
}
END {
  if (in_tui && !updated) {
    emit_setting()
  }
  if (!found_tui) {
    if (NR > 0) {
      print ""
    }
    print "[tui]"
    print "tool_output_display = \"full\""
  }
}
' "$config_file" >"$tmp"
  mv "$tmp" "$config_file"
}

if [[ "$CONFIG_EDIT" == true ]]; then
  set_tool_output_display_full
fi

echo "[3/3] Done"
echo

echo "Main-track test binary installed to: $TARGET"
if [[ "$NO_BACKUP" != true ]] && [[ -f "${TARGET}.bak" ]]; then
  echo "Previous binary backed up to: ${TARGET}.bak"
fi
if [[ "$CONFIG_EDIT" == true ]]; then
  echo "Configured ~/.codex/config.toml: [tui].tool_output_display = \"full\""
fi
echo
"$TARGET" --version || true
echo "Run it with: $TARGET"
