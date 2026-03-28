#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/patches/codex-full-tool-output.patch"
CODEX_REPO="https://github.com/openai/codex.git"
CODEX_REF="main"
WORKDIR="${TMPDIR:-/tmp}/codex-full-tool-output-build"
PREFIX="/usr/local"
USER_INSTALL=false
KEEP_WORKDIR=false

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

Options:
  --codex-ref <ref>    Git ref for openai/codex (default: main)
  --workdir <path>     Build directory (default: /tmp/codex-full-tool-output-build)
  --prefix <path>      Install prefix for cargo install (default: /usr/local)
  --user-install       Install under ~/.local (sets --prefix ~/.local)
  --keep-workdir       Do not delete build directory after install
  -h, --help           Show this help
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
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --user-install)
      USER_INSTALL=true
      PREFIX="$HOME/.local"
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

echo "[1/4] Fetching latest Codex ($CODEX_REF)"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
git clone --depth 1 --branch "$CODEX_REF" "$CODEX_REPO" "$WORKDIR/codex"

echo "[2/4] Applying tool-output full-display patch"
cd "$WORKDIR/codex"
if ! git apply --check "$PATCH_FILE"; then
  echo "Patch failed to apply cleanly. Upstream Codex changed; patch refresh is required." >&2
  exit 1
fi
git apply "$PATCH_FILE"

echo "[3/4] Building Codex"
cargo build --release --manifest-path codex-rs/Cargo.toml -p codex-cli

echo "[4/4] Installing Codex"
INSTALL_ARGS=(install --path codex-rs/cli --bin codex --locked --force --root "$PREFIX")

if [[ "$USER_INSTALL" == true ]]; then
  cargo "${INSTALL_ARGS[@]}"
else
  if [[ -w "$PREFIX" ]]; then
    cargo "${INSTALL_ARGS[@]}"
  else
    echo "Install prefix is not writable; requesting sudo for install step."
    sudo env "PATH=$PATH" cargo "${INSTALL_ARGS[@]}"
  fi
fi

if [[ "$KEEP_WORKDIR" != true ]]; then
  rm -rf "$WORKDIR"
fi

echo

echo "Installed patched Codex."
echo "Set this in ~/.codex/config.toml to force full tool output:"
echo
cat <<'CFG'
[tui]
tool_output_display = "full"
CFG

echo
if command -v codex >/dev/null 2>&1; then
  echo "Current codex binary: $(command -v codex)"
  codex --version || true
else
  echo "codex is not on PATH yet. Add '$PREFIX/bin' to PATH."
fi
