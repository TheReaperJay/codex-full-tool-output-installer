#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
MODIFICATIONS_DIR="$REPO_ROOT/modifications-main"
CODEX_REPO="https://github.com/openai/codex.git"
CODEX_REF="main"
WORKDIR="${TMPDIR:-/tmp}/codex-full-tool-output-main-build"
INSTALL_DIR="$HOME/.local/bin"
BINARY_NAME="codex-main"
KEEP_WORKDIR=false
NO_BACKUP=false
CONFIG_EDIT=true

usage() {
  cat <<USAGE
Usage: ./scripts/install-source-main.sh [options]

Builds Codex from upstream main, overlays this repo's modifications-main/,
and installs a test binary.

Options:
  --codex-ref <ref>      Git ref for openai/codex (default: main)
  --workdir <path>       Build directory (default: /tmp/codex-full-tool-output-main-build)
  --install-dir <path>   Install directory (default: ~/.local/bin)
  --binary-name <name>   Output binary name (default: codex-main)
  --no-backup            Skip backing up existing target binary.
  --no-config-edit       Do not modify ~/.codex/config.toml.
  --keep-workdir         Do not delete build directory after install.
  -h, --help             Show this help.

Examples:
  ./scripts/install-source-main.sh
  ./scripts/install-source-main.sh --binary-name codex-main-test
  ./scripts/install-source-main.sh --install-dir ~/.local/bin --binary-name codex-main
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

if [[ ! "$BINARY_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid --binary-name '$BINARY_NAME' (allowed: letters, digits, ., _, -)." >&2
  exit 1
fi

for cmd in git cargo; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

if [[ ! -d "$MODIFICATIONS_DIR" ]]; then
  echo "modifications-main directory not found: $MODIFICATIONS_DIR" >&2
  exit 1
fi

if ! find "$MODIFICATIONS_DIR" -type f -print -quit >/dev/null; then
  echo "modifications-main is empty: $MODIFICATIONS_DIR" >&2
  exit 1
fi

echo "[1/4] Fetching openai/codex ($CODEX_REF)"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
git clone --depth 1 --branch "$CODEX_REF" "$CODEX_REPO" "$WORKDIR/codex"

echo "[2/4] Applying local main-track modifications"
cp -a "$MODIFICATIONS_DIR"/. "$WORKDIR/codex/"

if git -C "$WORKDIR/codex" diff --quiet; then
  echo "No changes detected after overlaying modifications-main." >&2
  echo "Ensure this repo's modifications-main matches upstream $CODEX_REF." >&2
  exit 1
fi

echo "[3/4] Building Codex (release)"
cargo build --release --manifest-path "$WORKDIR/codex/codex-rs/Cargo.toml" -p codex-cli

BUILT_BINARY="$WORKDIR/codex/codex-rs/target/release/codex"
if [[ ! -f "$BUILT_BINARY" ]]; then
  echo "Build succeeded but binary not found at expected path: $BUILT_BINARY" >&2
  find "$WORKDIR/codex/codex-rs/target/release" -maxdepth 1 -name 'codex*' -type f 2>/dev/null
  exit 1
fi

TARGET="$INSTALL_DIR/$BINARY_NAME"
echo "[4/4] Installing to $TARGET"

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

if [[ "$KEEP_WORKDIR" != true ]]; then
  rm -rf "$WORKDIR"
fi

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
