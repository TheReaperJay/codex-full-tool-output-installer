# codex-full-tool-output-installer

<p align="center">
  <strong>Fix Codex TUI tool-output truncation</strong><br/>
  <em>No more <code>… +N lines</code> when you need the full output.</em>
</p>

<p align="center">
  <a href="https://github.com/openai/codex/issues/4550">Upstream issue #4550 (open since 2025)</a>
</p>

---

## The issue (what users actually see)

```text
Ran ssh YYY "duckdb -c \"DESCRIBE SELECT * FROM read_parquet('XXX') LIMIT 0;\""
  └ ┌───────────────────────────────────────────┐
    │                 Describe                  │
    … +36 lines
    └───────────────────────────────────────────┘

    … +126 lines
    └─────────────────────────────────────────┘
    │            Describe             │
    … +19 lines
    └────────────────────────────
```

You run a command.
Codex shows previews.
The useful part is hidden behind `… +N lines`.

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
│ output │
… +41 lines
```

### After (`tool_output_display = "full"`)

```text
│ output │
<all lines rendered in the TUI block>
<no collapsed middle preview>
```

---

## Why this exists

There is an upstream tracking issue for this behavior:
`openai/codex#4550` (open since 2025)

Until upstream ships a native global fix, this repo provides a practical patch + installer.

---

## One-command install

```bash
git clone https://github.com/<YOUR_USER>/codex-full-tool-output-installer.git
cd codex-full-tool-output-installer
./install.sh
```

Installer does exactly this:

1. Fetch latest `openai/codex`
2. Apply patch from this repo
3. Build Codex
4. Install globally (or user-local mode)

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

## Notes

- This patches **Codex CLI core renderer**.
- This is not a plugin or wrapper hack.
- If upstream changes internal files, patch offsets may need refresh.
