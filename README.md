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

## One-command install

```bash
git clone https://github.com/TheReaperJay/codex-full-tool-output-installer.git
cd codex-full-tool-output-installer
./install.sh
```

Installer does exactly this:

1. Clones the latest `openai/codex`
2. Applies the patch from this repo
3. Builds Codex from source
4. Installs the patched binary globally (or user-local)

---

## Configure

Add to `~/.codex/config.toml`:

```toml
[tui]
tool_output_display = "full"
```

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
