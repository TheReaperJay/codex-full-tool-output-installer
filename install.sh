#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/patches/codex-full-tool-output.patch"
CODEX_REPO="https://github.com/openai/codex.git"
CODEX_REF="main"
WORKDIR="${TMPDIR:-/tmp}/codex-full-tool-output-build"
INSTALL_DIR=""
KEEP_WORKDIR=false
NO_BACKUP=false
CONFIG_EDIT=true

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

Options:
  --codex-ref <ref>      Git ref for openai/codex (default: main)
  --workdir <path>       Build directory (default: /tmp/codex-full-tool-output-build)
  --install-dir <path>   Explicit directory to install the binary into.
                         If omitted, the installer detects your existing codex
                         binary location and replaces it in-place.
  --no-backup            Skip backing up the existing binary before replacing.
  --no-config-edit       Do not modify ~/.codex/config.toml.
  --keep-workdir         Do not delete build directory after install.
  -h, --help             Show this help.

Examples:
  ./install.sh                          # auto-detect and replace existing codex
  ./install.sh --install-dir ~/.local/bin
  ./install.sh --codex-ref v0.116.0
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --codex-ref)
      CODEX_REF="$2"
      shift 2
      ;;
    --workdir)
      WORKDIR="$2"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="$2"
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
    --keep-workdir)
      KEEP_WORKDIR=true
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

for cmd in git cargo; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "Patch file not found: $PATCH_FILE" >&2
  exit 1
fi

# --- Detect existing codex install ---
if [[ -z "$INSTALL_DIR" ]]; then
  EXISTING_CODEX="$(command -v codex 2>/dev/null || true)"
  if [[ -n "$EXISTING_CODEX" ]]; then
    # Resolve symlinks to get the real path
    EXISTING_CODEX="$(readlink -f "$EXISTING_CODEX")"
    INSTALL_DIR="$(dirname "$EXISTING_CODEX")"
    echo "Detected existing codex at: $EXISTING_CODEX"
    echo "Will install patched binary to: $INSTALL_DIR/codex"
  else
    INSTALL_DIR="/usr/local/bin"
    echo "No existing codex found on PATH."
    echo "Will install to default location: $INSTALL_DIR/codex"
  fi
fi

echo

# --- Clone ---
echo "[1/4] Fetching openai/codex ($CODEX_REF)"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
git clone --depth 1 --branch "$CODEX_REF" "$CODEX_REPO" "$WORKDIR/codex"

# --- Patch ---
echo "[2/4] Applying tool-output full-display patch"
cd "$WORKDIR/codex"
if ! git apply --check "$PATCH_FILE" 2>/dev/null; then
  echo "Patch failed to apply cleanly. Upstream Codex may have changed; patch refresh required." >&2
  exit 1
fi
git apply "$PATCH_FILE"

# --- Build ---
echo "[3/4] Building Codex (release)"
cargo build --release --manifest-path codex-rs/Cargo.toml -p codex-cli

BUILT_BINARY="$WORKDIR/codex/codex-rs/target/release/codex"
if [[ ! -f "$BUILT_BINARY" ]]; then
  echo "Build succeeded but binary not found at expected path: $BUILT_BINARY" >&2
  echo "Checking target directory..."
  find "$WORKDIR/codex/codex-rs/target/release" -maxdepth 1 -name 'codex*' -type f 2>/dev/null
  exit 1
fi

# --- Install ---
echo "[4/4] Installing to $INSTALL_DIR/codex"
TARGET="$INSTALL_DIR/codex"

do_install() {
  local use_sudo="$1"
  local cmd_prefix=""
  [[ "$use_sudo" == true ]] && cmd_prefix="sudo"

  # Backup existing binary
  if [[ -f "$TARGET" && "$NO_BACKUP" != true ]]; then
    BACKUP="${TARGET}.bak"
    echo "  Backing up existing binary → $BACKUP"
    $cmd_prefix cp "$TARGET" "$BACKUP"
  fi

  $cmd_prefix cp "$BUILT_BINARY" "$TARGET"
  $cmd_prefix chmod +x "$TARGET"
}

if [[ -w "$INSTALL_DIR" ]]; then
  do_install false
else
  echo "  $INSTALL_DIR is not writable; requesting sudo."
  do_install true
fi

# --- Config update ---
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

# --- Cleanup ---
if [[ "$KEEP_WORKDIR" != true ]]; then
  rm -rf "$WORKDIR"
fi

# --- Summary ---
echo
echo "Patched codex installed to: $TARGET"

if [[ "$NO_BACKUP" != true ]] && [[ -f "${TARGET}.bak" ]]; then
  echo "Previous binary backed up to: ${TARGET}.bak"
fi

if [[ "$CONFIG_EDIT" == true ]]; then
  echo "Configured ~/.codex/config.toml:"
  echo "  [tui]"
  echo "  tool_output_display = \"full\""
else
  echo
  echo "Add this to ~/.codex/config.toml to enable full tool output:"
  echo
  cat <<'CFG'
  [tui]
  tool_output_display = "full"
CFG
fi

echo
if command -v codex >/dev/null 2>&1; then
  echo "Verify: $(command -v codex)"
  codex --version || true
else
  echo "codex is not on PATH. Add '$INSTALL_DIR' to your PATH."
fi
