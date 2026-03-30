# codex-full-tool-output-installer

<div align="center">

**One-command patch that fixes Codex TUI tool-output truncation.**

No more `… +N lines` hiding the output you need.

Tracking: [openai/codex#4550](https://github.com/openai/codex/issues/4550) — open since 2025, no upstream fix yet.

<a href="https://github.com/TheReaperJay"><img src="https://img.shields.io/badge/GitHub-TheReaperJay-181717?style=for-the-badge&logo=github" alt="GitHub"></a>
<a href="https://discord.gg/realjaybrew"><img src="https://img.shields.io/badge/Discord-realjaybrew-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord"></a>
<a href="https://t.me/realjaybrew"><img src="https://img.shields.io/badge/Telegram-realjaybrew-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram"></a>
<a href="https://github.com/TheReaperJay/codex-full-tool-output-installer/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=for-the-badge" alt="License"></a>

</div>

---

## The Problem

When Codex runs shell commands, the TUI truncates tool output behind collapsed `… +N lines` previews. The actual data — the part you need to read, copy, or act on — is hidden by default:

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

This isn't a minor cosmetic issue. If you're using Codex to run queries, inspect logs, grep output, or execute any command that produces more than a handful of lines, you're flying blind. The agent sees the full output, but *you* don't — so you can't verify what it's doing, catch errors in intermediate results, or copy output for your own use.

There is no built-in setting to disable this behavior. [openai/codex#4550](https://github.com/openai/codex/issues/4550) has been open since 2025 with no upstream fix.

This repo patches the Codex TUI renderer to give you that control.

---

## Before / After

### Before (stock Codex)

```text
│ output                                    │
… +41 lines
```

41 lines of query results, completely invisible.

### After (`tool_output_display = "full"`)

```text
│ output                                    │
│ column_name  | column_type | null | key   │
│ id           | BIGINT      | YES  | NULL  │
│ name         | VARCHAR     | YES  | NULL  │
│ created_at   | TIMESTAMP   | YES  | NULL  │
│ ...all rows rendered, nothing collapsed   │
```

Every line rendered. Nothing hidden.

---

## What the Patch Does

This is not a plugin, wrapper, or monkey-patch. It modifies the Codex TUI source code before compilation to add a proper `tool_output_display` setting:

```toml
# ~/.codex/config.toml
[tui]
tool_output_display = "full"   # full | collapsed
```

When set to `full`, the renderer stops truncating tool-output blocks entirely — no line limits, no collapsed previews.

### Runtime Toggle (`Ctrl+o`)

You don't have to commit to one mode. Press `Ctrl+o` during a session to flip between expanded and collapsed output on the fly. This is a live view toggle — it doesn't touch your config file, so your persistent preference stays intact.

Expanded output (full) now shows an inline hint:

```text
Ran rg -n "async fn handle_key_event\(|transcript_cells: Vec<Arc<dyn HistoryCell>>|KeyCode::Char\('t'\)|KeyCode::Char\('l'\)|KeyCode::Char\('g'\)" -S /tmp/codex-full-tool-output-build/codex/
  | codex-rs/*/src/app.rs /tmp/codex-full-tool-output-build/codex/codex-rs/*/src/chatwidget.rs 2>/dev/null
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui_app_server/src/app.rs:5434:                code: KeyCode::Char('t'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui_app_server/src/app.rs:5445:                code: KeyCode::Char('l'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui_app_server/src/app.rs:5464:                code: KeyCode::Char('g'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:914:    pub(crate) transcript_cells: Vec<Arc<dyn HistoryCell>>,
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:4580:    async fn handle_key_event(&mut self, tui: &mut tui::Tui, key_event: KeyEvent) {
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:4621:                code: KeyCode::Char('t'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:4632:                code: KeyCode::Char('l'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:4651:                code: KeyCode::Char('g'),
    [ctrl + o to collapse output]
```

Collapsed output shows the opposite hint so it is discoverable in both states:

```text
Ran rg -n "async fn handle_key_event\(|transcript_cells: Vec<Arc<dyn HistoryCell>>|KeyCode::Char\('t'\)|KeyCode::Char\('l'\)|KeyCode::Char\('g'\)" -S /tmp/codex-full-tool-output-build/codex/
  | codex-rs/*/src/app.rs /tmp/codex-full-tool-output-build/codex/codex-rs/*/src/chatwidget.rs 2>/dev/null
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui_app_server/src/app.rs:5434:                code: KeyCode::Char('t'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui_app_server/src/app.rs:5445:                code: KeyCode::Char('l'),
    ... +4 lines
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:4632:                code: KeyCode::Char('l'),
    /tmp/codex-full-tool-output-build/codex/codex-rs/tui/src/app.rs:4651:                code: KeyCode::Char('g'),
    [ctrl + o to expand output]
```

---

## Quick Start

```bash
git clone https://github.com/TheReaperJay/codex-full-tool-output-installer.git
cd codex-full-tool-output-installer
./install.sh
```

The launcher walks you through two choices:

1. **Mode** — `source` (build from upstream) or `binary` (install a prebuilt binary)
2. **Track** — `stable` (current release, v0.117.0) or `main` (upstream development branch)

That's it. The installer handles cloning, patching, building, binary replacement, backup, and config setup.

### Non-Interactive

For CI, scripts, or repeat installs:

```bash
# Build from source against the current stable release
./install.sh --mode source --track stable

# Build from source against upstream main
./install.sh --mode source --track main

# Install a prebuilt patched binary (local file)
./install.sh --mode binary --track stable --source ./dist/codex-v0.117.0-patched-linux-x64.tar.gz

# Install a prebuilt patched binary (URL)
./install.sh --mode binary --track main --source https://example.com/codex-main.tar.gz
```

---

## Why Two Tracks?

Upstream Codex reorganized its source tree between the `rust-v0.117.0` release tag and the current `main` branch. The module that was `codex-rs/tui_app_server/` in v0.117.0 became `codex-rs/tui/` in main. File paths, module boundaries, and internal APIs shifted.

A single patch file can't target both layouts. So the installer maintains two parallel sets of modifications — one for each upstream structure — and picks the right one based on which track you choose.

| | Stable | Main |
|---|---|---|
| **Upstream ref** | `rust-v0.117.0` (current packaged release) | `main` (active development) |
| **Install target** | Replaces your live `codex` binary in-place | Installs as `~/.local/bin/codex-main` (non-destructive) |
| **Risk level** | Production — this becomes your daily driver | Safe to test — your system `codex` is untouched |
| **Use case** | You want the fix now, on the version you already run | You want to test against bleeding-edge upstream or prep a PR |

## Why Two Modes?

**Source mode** clones the upstream repo, applies the patch, and compiles locally with `cargo build --release`. This is the canonical path — you get a binary built from auditable source on your own machine. The tradeoff is build time (~30+ minutes depending on hardware) and requiring a Rust toolchain.

**Binary mode** skips the build entirely. Point it at a prebuilt tarball (local path or URL) and it handles extraction, backup, and installation. This exists for people who don't want to install Rust, don't want to wait for a build, or are distributing patched binaries across machines.

---

## Script Architecture

The installer is split into five scripts. The reason for the split is that each combination of mode + track has genuinely different logic — different upstream refs, different patching strategies, different install targets — and cramming all four paths into one script would be an unreadable mess.

```
install.sh                              ← User-facing launcher (collects mode/track, delegates)
├── scripts/install-source-stable.sh    ← Clone v0.117.0 → git apply patch → cargo build → replace live codex
├── scripts/install-source-main.sh      ← Clone main → overlay modifications-main/ → cargo build → install as codex-main
├── scripts/install-release-stable.sh   ← Fetch prebuilt binary/tarball → replace live codex
└── scripts/install-release-main.sh     ← Fetch prebuilt binary/tarball → install as codex-main
```

**`install.sh`** is the only script users interact with. It collects mode/track selection (interactively or via flags), validates input, and delegates to the appropriate script. It never builds or installs anything itself.

**`install-source-stable.sh`** clones `openai/codex@rust-v0.117.0`, applies `patches/codex-full-tool-output.patch` via `git apply`, builds with Cargo, then installs the binary. By default it auto-detects your existing `codex` location (including npm-wrapped installations where `codex` is actually a Node.js wrapper around a native binary) and replaces it in-place with an atomic `mv`. It backs up the original binary first.

**`install-source-main.sh`** does the same thing for upstream `main`, but because `main`'s file layout differs from v0.117.0, it can't use a patch file. Instead it copies the pre-modified source files from `modifications-main/` directly over the cloned repo. It installs as `codex-main` by default — a separate binary — so you can test without touching your production install.

**`install-release-stable.sh`** and **`install-release-main.sh`** handle prebuilt binaries. They accept a `--source` path or URL, extract tarballs if needed, and run the same install/backup/config logic as the source scripts. The stable variant replaces in-place; the main variant installs as a test binary.

All four installers share the same safety behavior:
- Stop running `codex` processes before replacing the binary
- Atomic replacement via temp file + `mv -f` (no partial overwrites)
- Backup of the existing binary (skippable with `--no-backup`)
- Auto-configuration of `~/.codex/config.toml` (skippable with `--no-config-edit`)
- Cleanup of temp/build directories on exit

## Source Trees

```
modifications/          ← Patched source files for rust-v0.117.0 (stable track)
modifications-main/     ← Patched source files for main branch (main track)
patches/                ← Git patch file used by source-stable installer
```

`modifications/` and `modifications-main/` contain the same logical changes — the `ToolOutputDisplay` enum, config plumbing, renderer bypass, and `Ctrl+o` toggle — but targeting different file paths and module structures because upstream reorganized between releases.

`patches/codex-full-tool-output.patch` is the `git diff` representation of the stable modifications, applied by `install-source-stable.sh` via `git apply`. The `modifications/` directory is the human-readable reference for what the patch contains.

---

## Configuration

The installer automatically sets this in `~/.codex/config.toml`:

```toml
[tui]
tool_output_display = "full"
```

If the file doesn't exist, it creates it. If it exists, it adds or updates the setting without touching the rest of your config.

To skip config modification:

```bash
./install.sh --no-config-edit
```

---

## Verify

```bash
codex --version
```

Run any tool-heavy command. If tool output renders in full instead of collapsing behind `… +N lines`, the patch is active.

---

## How It Works (Technical)

The patch modifies seven files across the Codex Rust codebase:

1. **Config types** — adds a `ToolOutputDisplay` enum (`Full` | `Collapsed`) and a corresponding field on the `Tui` config struct
2. **Config parsing** — routes the `tool_output_display` TOML value through to the runtime config
3. **ChatWidget** — adds the `Ctrl+o` keybinding and `toggle_tool_output_display()` method
4. **ExecCell model** — carries the display setting per-cell so each tool-output block respects it
5. **ExecCell renderer** — the core change: when `Full`, sets the line limit to `usize::MAX` and skips all truncation logic, then appends the toggle hint
6. **Config tests** — updated to initialize the new field
7. **PagerOverlay tests** — updated to pass the new parameter

This is a source-level modification, not a runtime hook or overlay. If upstream changes the renderer internals, the patch will need a rebase — check [openai/codex#4550](https://github.com/openai/codex/issues/4550) for status.

---

## CLI Reference

| Flag | Applies to | Description |
|---|---|---|
| `--mode source\|binary` | `install.sh` | Skip the interactive mode prompt |
| `--track stable\|main` | `install.sh` | Skip the interactive track prompt |
| `--source <path-or-url>` | binary mode | Path or URL to prebuilt binary/tarball (required for binary mode) |
| `--install-dir <path>` | stable scripts | Explicit install directory instead of auto-detection |
| `--in-place` | stable scripts | Replace existing codex in-place (default) |
| `--no-in-place` | stable scripts | Install to `~/.local/bin/codex` instead |
| `--binary-name <name>` | main scripts | Custom binary name (default: `codex-main`) |
| `--codex-ref <ref>` | source-stable | Override upstream git ref (default: `rust-v0.117.0`) |
| `--workdir <path>` | source scripts | Custom build directory |
| `--keep-workdir` | source scripts | Don't delete build directory after install |
| `--no-backup` | all installers | Skip backing up the existing binary |
| `--no-config-edit` | all installers | Don't modify `~/.codex/config.toml` |

---

## License

[MIT](LICENSE)

---

<div align="center">

<a href="https://github.com/TheReaperJay"><img src="https://img.shields.io/badge/GitHub-TheReaperJay-181717?style=for-the-badge&logo=github" alt="GitHub"></a>
<a href="https://discord.gg/realjaybrew"><img src="https://img.shields.io/badge/Discord-realjaybrew-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord"></a>
<a href="https://t.me/realjaybrew"><img src="https://img.shields.io/badge/Telegram-realjaybrew-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram"></a>

</div>
