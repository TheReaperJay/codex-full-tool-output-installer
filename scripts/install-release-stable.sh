#!/usr/bin/env bash
set -euo pipefail

SOURCE=""
INSTALL_DIR=""
IN_PLACE=true
NO_BACKUP=false
CONFIG_EDIT=true
TMP_WORK=""

usage() {
  cat <<USAGE
Usage: ./scripts/install-release-stable.sh --source <path-or-url> [options]

Installs a prebuilt patched Codex binary for the stable track.

Options:
  --source <path-or-url>  Local file path or HTTP(S) URL to binary or tarball.
  --install-dir <path>    Explicit directory to install into (<path>/codex).
  --in-place              Replace current codex executable (default).
  --no-in-place           Install to ~/.local/bin/codex.
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
    --in-place)
      IN_PLACE=true
      shift
      ;;
    --no-in-place)
      IN_PLACE=false
      shift
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

target_triple() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os:$arch" in
    Linux:x86_64) echo "x86_64-unknown-linux-musl" ;;
    Linux:aarch64|Linux:arm64) echo "aarch64-unknown-linux-musl" ;;
    Darwin:x86_64) echo "x86_64-apple-darwin" ;;
    Darwin:arm64) echo "aarch64-apple-darwin" ;;
    *) return 1 ;;
  esac
}

platform_package_for_triple() {
  case "$1" in
    x86_64-unknown-linux-musl) echo "@openai/codex-linux-x64" ;;
    aarch64-unknown-linux-musl) echo "@openai/codex-linux-arm64" ;;
    x86_64-apple-darwin) echo "@openai/codex-darwin-x64" ;;
    aarch64-apple-darwin) echo "@openai/codex-darwin-arm64" ;;
    *) return 1 ;;
  esac
}

resolve_npm_wrapper_binary() {
  local wrapper_path="$1"
  local wrapper_dir wrapper_root triple package candidate1 candidate2 found
  wrapper_dir="$(dirname "$wrapper_path")"
  wrapper_root="$(cd "$wrapper_dir/.." && pwd)"

  triple="$(target_triple)" || return 1
  package="$(platform_package_for_triple "$triple")" || return 1

  candidate1="$wrapper_root/node_modules/$package/vendor/$triple/codex/codex"
  candidate2="$wrapper_root/vendor/$triple/codex/codex"

  if [[ -x "$candidate1" ]]; then
    readlink -f "$candidate1"
    return 0
  fi

  if [[ -x "$candidate2" ]]; then
    readlink -f "$candidate2"
    return 0
  fi

  found="$(find "$wrapper_root" -maxdepth 7 -type f -path "*/vendor/$triple/codex/codex" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$found" ]]; then
    readlink -f "$found"
    return 0
  fi

  return 1
}

EXISTING_CODEX_CMD="$(command -v codex 2>/dev/null || true)"
EXISTING_CODEX_REAL=""
if [[ -n "$EXISTING_CODEX_CMD" ]]; then
  EXISTING_CODEX_REAL="$(readlink -f "$EXISTING_CODEX_CMD")"
fi

TARGET=""
if [[ -n "$INSTALL_DIR" ]]; then
  TARGET="$INSTALL_DIR/codex"
  echo "Using explicit install directory: $INSTALL_DIR"
elif [[ "$IN_PLACE" == true ]]; then
  if [[ -z "$EXISTING_CODEX_CMD" ]]; then
    echo "No codex found on PATH for --in-place install. Use --install-dir instead." >&2
    exit 1
  fi

  if [[ "$(basename "$EXISTING_CODEX_REAL")" == "codex.js" ]]; then
    if ! TARGET="$(resolve_npm_wrapper_binary "$EXISTING_CODEX_REAL")"; then
      echo "Detected codex.js wrapper but could not locate underlying native codex binary." >&2
      echo "Use --no-in-place or --install-dir ~/.local/bin." >&2
      exit 1
    fi
    echo "Detected npm-managed codex wrapper:"
    echo "  wrapper: $EXISTING_CODEX_REAL"
    echo "  native : $TARGET"
  else
    TARGET="$EXISTING_CODEX_REAL"
    echo "Detected existing codex executable at: $TARGET"
  fi
else
  INSTALL_DIR="$HOME/.local/bin"
  TARGET="$INSTALL_DIR/codex"
  echo "Defaulting to PATH override install: $TARGET"
  if [[ -n "$EXISTING_CODEX_CMD" ]]; then
    echo "Current codex command resolves to: $EXISTING_CODEX_CMD"
  fi
fi
INSTALL_DIR="$(dirname "$TARGET")"
echo "Will install binary to: $TARGET"

echo

echo "[1/3] Preparing binary source"
TMP_WORK="$(mktemp -d "${TMPDIR:-/tmp}/codex-release-install-XXXXXX")"
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

echo "Binary installed to: $TARGET"
if [[ "$NO_BACKUP" != true ]] && [[ -f "${TARGET}.bak" ]]; then
  echo "Previous binary backed up to: ${TARGET}.bak"
fi

if [[ "$CONFIG_EDIT" == true ]]; then
  echo "Configured ~/.codex/config.toml: [tui].tool_output_display = \"full\""
fi

echo
if command -v codex >/dev/null 2>&1; then
  ACTIVE_CODEX="$(command -v codex)"
  ACTIVE_CODEX_REAL="$(readlink -f "$ACTIVE_CODEX")"
  TARGET_REAL="$(readlink -f "$TARGET" 2>/dev/null || echo "$TARGET")"

  echo "Verify command path: $ACTIVE_CODEX"
  echo "Verify real path:    $ACTIVE_CODEX_REAL"
  if [[ "$ACTIVE_CODEX_REAL" != "$TARGET_REAL" ]]; then
    echo "WARNING: shell is not resolving to the patched target."
    echo "Patch target: $TARGET_REAL"
  fi
  codex --version || true
else
  echo "codex is not on PATH. Add '$INSTALL_DIR' to your PATH."
fi
