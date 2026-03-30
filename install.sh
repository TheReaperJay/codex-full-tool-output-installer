#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

MODE=""
TRACK=""
BINARY_SOURCE=""
PASSTHROUGH=()

usage() {
  cat <<USAGE
Usage: ./install.sh [options] [-- extra-script-options]

Unified installer launcher.

Modes:
  source  Build from source (slow, ~30+ minutes)
  binary  Install from prebuilt binary/tarball

Tracks:
  stable  Current stable track (in-place codex replacement)
  main    Main/dev track (temporary codex-main by default)

Options:
  --mode <source|binary>
  --track <stable|main>
  --source <path-or-url>   Required for binary mode unless entered interactively.
  -h, --help               Show this help.

Examples:
  ./install.sh
  ./install.sh --mode source --track stable
  ./install.sh --mode source --track main -- --binary-name codex-main-test
  ./install.sh --mode binary --track stable --source ./dist/codex-v0.117.0-patched-linux-x64.tar.gz
  ./install.sh --mode binary --track main --source https://example.com/codex-main.tar.gz
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --track)
      TRACK="$2"
      shift 2
      ;;
    --source)
      BINARY_SOURCE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      PASSTHROUGH+=("$@")
      break
      ;;
    *)
      PASSTHROUGH+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  if [[ -t 0 ]]; then
    echo "Choose install mode:"
    echo "  1) install from source (30+ minutes)"
    echo "  2) install from binary"
    read -r -p "Enter choice [1/2]: " mode_choice
    case "$mode_choice" in
      1) MODE="source" ;;
      2) MODE="binary" ;;
      *)
        echo "Invalid choice: $mode_choice" >&2
        exit 1
        ;;
    esac
  else
    echo "Missing --mode in non-interactive context." >&2
    exit 1
  fi
fi

if [[ -z "$TRACK" ]]; then
  if [[ -t 0 ]]; then
    echo
    echo "Choose track:"
    echo "  a) stable version 0.117.0"
    echo "  b) main branch (experimental, may not be stable)"
    read -r -p "Enter choice [a/b]: " track_choice
    case "$track_choice" in
      a|A) TRACK="stable" ;;
      b|B) TRACK="main" ;;
      *)
        echo "Invalid choice: $track_choice" >&2
        exit 1
        ;;
    esac
  else
    echo "Missing --track in non-interactive context." >&2
    exit 1
  fi
fi

case "$MODE" in
  source|binary) ;;
  *)
    echo "Invalid --mode '$MODE' (expected source|binary)." >&2
    exit 1
    ;;
esac

case "$TRACK" in
  stable|main) ;;
  *)
    echo "Invalid --track '$TRACK' (expected stable|main)." >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "binary" && -z "$BINARY_SOURCE" ]]; then
  if [[ -t 0 ]]; then
    echo
    read -r -p "Enter binary source path or URL: " BINARY_SOURCE
    if [[ -z "$BINARY_SOURCE" ]]; then
      echo "Binary source is required for binary mode." >&2
      exit 1
    fi
  else
    echo "Missing --source for binary mode in non-interactive context." >&2
    exit 1
  fi
fi

TARGET_SCRIPT=""
case "$MODE:$TRACK" in
  source:stable)
    TARGET_SCRIPT="$SCRIPT_DIR/scripts/install-source-stable.sh"
    ;;
  source:main)
    TARGET_SCRIPT="$SCRIPT_DIR/scripts/install-source-main.sh"
    ;;
  binary:stable)
    TARGET_SCRIPT="$SCRIPT_DIR/scripts/install-release-stable.sh"
    ;;
  binary:main)
    TARGET_SCRIPT="$SCRIPT_DIR/scripts/install-release-main.sh"
    ;;
  *)
    echo "Unsupported mode/track combination: $MODE/$TRACK" >&2
    exit 1
    ;;
esac

if [[ ! -x "$TARGET_SCRIPT" ]]; then
  echo "Installer script not found or not executable: $TARGET_SCRIPT" >&2
  exit 1
fi

echo
printf 'Selected: mode=%s, track=%s\n' "$MODE" "$TRACK"

FORWARD_ARGS=()
if [[ "$MODE" == "binary" ]]; then
  FORWARD_ARGS+=(--source "$BINARY_SOURCE")
fi
FORWARD_ARGS+=("${PASSTHROUGH[@]}")

exec "$TARGET_SCRIPT" "${FORWARD_ARGS[@]}"
