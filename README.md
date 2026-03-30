# codex-full-tool-output-installer

<p align="center">
  <strong>One-command patch that fixes Codex TUI tool-output truncation.</strong><br/>
  No more <code>… +N lines</code> hiding the output you need.
</p>

<p align="center">
  Tracking: <a href="https://github.com/openai/codex/issues/4550">openai/codex#4550</a> — open since 2025, no upstream fix yet.
</p>

---

## The Problem

When Codex runs shell commands, the TUI collapses tool output behind `… +N lines` previews:

```text
Ran ssh YYY "duckdb -c \"DESCRIBE SELECT * FROM read_parquet('XXX') LIMIT 0;\""
  └ ┌───────────────────────────────────────────┐
    │                 Describe                  │
    … +36 lines                                     ← hidden
    └───────────────────────────────────────────┘

    … +126 lines                                    ← hidden
    └─────────────────────────────────────────┘
    │            Describe             │
    … +19 lines                                     ← hidden
    └────────────────────────────
```

The useful part — the actual output — is collapsed away. You can't read it, copy it, or act on it without expanding each block manually.

---

## What this repo changes

This repo patches **core Codex** so TUI tool output can be forced to full display via config:

```toml
[tui]
tool_output_display = "full"   # full | collapsed
```

When set to `full`, tool-output rendering stops collapsing into `… +N lines` previews.

---

## Before / After

### Before (default behavior in affected builds)

```text
│ output                                    │
… +41 lines
```

### After (`tool_output_display = "full"`)

```text
│ output                                    │
│ column_name  | column_type | null | key   │
│ id           | BIGINT      | YES  | NULL  │
│ name         | VARCHAR     | YES  | NULL  │
│ created_at   | TIMESTAMP   | YES  | NULL  │
│ ...all rows rendered, nothing collapsed   │
```

---

## Why this exists

There is an upstream tracking issue for this behavior:
[openai/codex#4550](https://github.com/openai/codex/issues/4550) (open since 2025)

Until upstream ships a native global fix, this repo provides a practical patch + installer.

---

## Install (Current Stable: 0.117.0 Patch Track)

```bash
git clone https://github.com/TheReaperJay/codex-full-tool-output-installer.git
cd codex-full-tool-output-installer
./install.sh
```

`install.sh` is the **current-build installer**. It targets `rust-v0.117.0` by default (the release-aligned Rust tag for the currently packaged Codex line), applies this repo's patch, builds, and replaces your existing Codex binary in-place.

Installer steps:

1. Chooses install target:
   - default: replace currently installed `codex` executable
   - npm installs: resolves through `codex.js` and replaces the underlying native vendor binary
   - `--no-in-place`: install to `~/.local/bin/codex` instead
   - `--install-dir <path>`: install to `<path>/codex`
2. Clones `openai/codex` at `rust-v0.117.0` by default
3. Applies the patch from this repo
4. Builds Codex from source (`cargo build --release`)
5. Copies the patched binary to the chosen target (requests `sudo` if needed)
6. Stops running processes using the target binary before replacement to avoid `Text file busy`

### Install options

```
./install.sh                              # replace existing codex executable (default)
./install.sh --no-in-place                # install to ~/.local/bin/codex
./install.sh --in-place                   # explicit in-place replace
./install.sh --install-dir ~/.local/bin   # install to a specific directory
./install.sh --codex-ref rust-v0.117.0    # pin explicit current-build ref
./install.sh --no-backup                  # skip backing up the old binary
./install.sh --no-config-edit             # do not edit ~/.codex/config.toml
./install.sh --keep-workdir               # keep the build directory after install
```

## Install (Main Dev Track: Temporary Binary)

```bash
./install-main.sh
```

`install-main.sh` is the **main-branch installer**. It clones upstream `main`, overlays `modifications-main/`, builds, and installs a separate test binary (`~/.local/bin/codex-main` by default).

Key behavior:

- Does **not** overwrite your system `codex` unless you explicitly choose a conflicting target.
- Intended for upstream PR prep and validating equivalent behavior on current `main`.
- Also stops running processes using the target binary before replacement to avoid `Text file busy`.

Examples:

```bash
./install-main.sh
./install-main.sh --binary-name codex-main-test
./install-main.sh --install-dir ~/.local/bin --binary-name codex-main
```

## Why Two Paths?

- `rust-v0.117.0` (current packaged line): patch in `patches/codex-full-tool-output.patch` and source copies in `modifications/`.
- `main` (active development branch): equivalent code lives in `modifications-main/`, because upstream file paths/layout differ from 0.117.0.

In short:
- **Current released build fix** -> `install.sh` + `modifications/`.
- **Upstream PR/main development fix** -> `install-main.sh` + `modifications-main/`.

## Source Trees

- `modifications/` tracks the working patch against `rust-v0.117.0` (installer default).
- `modifications-main/` tracks equivalent changes for current `main`, intended for upstream PR prep.

---

## Configure

By default, `install.sh` automatically sets this in `~/.codex/config.toml`:

```toml
[tui]
tool_output_display = "full"
```

If you do not want the installer to edit your config, run with `--no-config-edit`.

---

## Verify

```bash
codex --version
```

Run any tool-heavy command.
If you no longer see collapsed `… +N lines` blocks for tool output, the patch is active.

---

## How It Works

- Patches the **Codex CLI core TUI renderer** — the component responsible for drawing tool-output blocks.
- Not a plugin, wrapper, or hack. This modifies the source before compilation.
- If upstream changes the renderer internals, the patch file may need a rebase. Check [openai/codex#4550](https://github.com/openai/codex/issues/4550) for status.

---

## License

[MIT](LICENSE)
