# OpenCode Harness - Configuration Guide

OpenCode Harness uses two configuration files to control plugin loading and container behavior. This guide documents their structure and how to modify them.

## Configuration Files Overview

| File | Format | Purpose |
|------|--------|---------|
| `build/.opencode/opencode.json` | JSON | Project plugin list with pinned versions |
| `build/etc/opencode/opencode.jsonc` | JSONC | Container runtime config (compaction, permissions, plugins) |

## Plugin Configuration

**Location:** `build/.opencode/opencode.json`
**Format:** JSON (strict syntax)

```json
{
    "$schema": "https://opencode.ai/config.json",
    "plugin": [
        "@tarquinen/opencode-dcp@3.1.11",
        "cc-safety-net@0.9.0",
        "oh-my-openagent@4.0.0"
    ]
}
```

### Plugins

- `@tarquinen/opencode-dcp@3.1.11` — Distributed context protocol plugin. Pinned to 3.1.11 for reproducibility.
- `cc-safety-net@0.9.0` — Safety guardrails for agent operations. Pinned to 0.9.0.
- `oh-my-openagent@4.0.0` — Multi-agent orchestration with Sisyphus orchestrator. Pinned to 4.0.0.

All plugin versions are pinned. Do not use `@latest` in this file; update versions deliberately when submodules change.

### Validation

```bash
jq . build/.opencode/opencode.json
```

## Container Configuration

**Location:** `build/etc/opencode/opencode.jsonc`
**Format:** JSONC (supports comments)

This file is copied to `/etc/opencode/opencode.jsonc` inside the container and controls runtime behavior.

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    // Disable automatic self-updates inside the container
    "autoupdate": false,
    // Conversation compaction settings to manage context size
    "compaction": {
        // Automatically compact long conversations
        "auto": true,
        // Remove low-value messages during compaction
        "prune": true,
        // Tokens reserved to avoid exceeding model context limits
        "reserved": 10000
    },
    // Default agent profile to use when none is specified
    "default_agent": "build",
    // Additional instruction files loaded into the agent context
    "instructions": [
        "AGENTS.md"
    ],
    // Default permission policy for tool usage
    // "ask" prompts before executing the action
    "permission": {
        "edit": "ask",
        "write": "ask",
        "bash": {
            "*": "ask",
            "basename": "allow",
            "dirname": "allow",
            "file": "allow",
            "git branch *": "allow",
            "git diff *": "allow",
            "git log *": "allow",
            "git rev-parse *": "allow",
            "git show *": "allow",
            "git status *": "allow",
            "head *": "allow",
            "ls *": "allow",
            "pwd": "allow",
            "realpath": "allow",
            "stat": "allow",
            "tail *": "allow",
            "wc *": "allow",
            "which": "allow"
        }
    },
    // OpenCode plugins to load inside the container
    "plugin": [
        "opencode-beads",
        "@tarquinen/opencode-dcp@latest"
    ],
    // Sharing behavior for sessions (manual = explicit user action required)
    "share": "manual",
    // File watcher configuration for workspace awareness
    "watcher": {
        "ignore": [
            // Ignore VCS metadata
            ".git/**",
            // Ignore dependency directories
            "node_modules/**",
            // Ignore build outputs
            "dist/**",
            "build/**"
        ]
    }
}
```

### Key Settings

- **`autoupdate: false`** — Prevents OpenCode from updating itself inside the container. Version is pinned via `build/.opencode-version`.
- **`compaction`** — Manages context window usage. `reserved: 10000` keeps 10k tokens free to avoid truncation.
- **`default_agent: "build"`** — Uses the `build` agent profile by default in the container.
- **`instructions: ["AGENTS.md"]`** — Loads project instructions into every agent session.
- **`permission`** — All file edits and writes require confirmation (`"ask"`). Read-only bash commands (`ls`, `cat`, `git log`, etc.) are auto-allowed. Everything else prompts.
- **`plugin`** — Container uses a different plugin set than the project config. `opencode-beads` and `@tarquinen/opencode-dcp@latest` are loaded at runtime.
- **`share: "manual"`** — Sessions are never shared without explicit user action.
- **`watcher.ignore`** — Excludes `.git`, `node_modules`, `dist`, and `build` directories from file watching.

### Validation

```bash
jq . build/etc/opencode/opencode.jsonc
```

## Container Module Control

The entrypoint script (`build/entrypoint.sh`) supports environment variables to enable or disable submodule-based plugins at container startup. All default to enabled.

| Variable | Default | Controls |
|----------|---------|----------|
| `ECC_ENABLED` | `true` | everything-claude-code module assets |
| `OMO_ENABLED` | `true` | oh-my-openagent module assets and oh-my-opencode installation |
| `SUPERPOWERS_ENABLED` | `true` | superpowers module assets |

Set a variable to `0`, `false`, or `no` to disable the corresponding module.

### Examples

```bash
# Run without everything-claude-code
podman run -it --rm -e ECC_ENABLED=false opencode-harness

# Run with only superpowers
podman run -it --rm \
  -e ECC_ENABLED=false \
  -e OMO_ENABLED=false \
  opencode-harness

# Run with everything enabled (default)
podman run -it --rm opencode-harness
```

### OMO Subscription Flags

When `OMO_ENABLED=true`, the entrypoint passes subscription flags to `bunx oh-my-opencode install`. Set these to configure which LLM subscriptions to declare:

- `OMO_CLAUDE` — Claude subscription (`yes|no|max20`)
- `OMO_GEMINI` — Gemini subscription (`yes|no`)
- `OMO_COPILOT` — GitHub Copilot subscription (`yes|no`)
- `OMO_OPENAI` — OpenAI subscription (`yes|no`)

## Adding Plugins

1. Add the plugin as a git submodule:

```bash
git submodule add <plugin-url> build/modules/<plugin-name>
```

2. Add the plugin to `build/.opencode/opencode.json` with a pinned version:

```json
{
    "$schema": "https://opencode.ai/config.json",
    "plugin": [
        "@tarquinen/opencode-dcp@3.1.11",
        "cc-safety-net@0.9.0",
        "oh-my-openagent@4.0.0",
        "<new-plugin>@<version>"
    ]
}
```

3. Rebuild and test:

```bash
./scripts/build.sh --tag test --no-cache
./scripts/container-test.sh test
```

## Validating Configuration

```bash
# Validate JSON syntax for plugin config
jq . build/.opencode/opencode.json

# Validate JSONC syntax for container config
jq . build/etc/opencode/opencode.jsonc

# Run full pre-build validation
./scripts/validate.sh
```
