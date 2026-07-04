# build/ — Container Build Context

## Purpose

The **sole container build context** for `podman/docker build`. Everything needed to produce the reproducible OCI image lives here: Containerfile, runtime entrypoint, OpenCode version pinning, system config, and the three plugin submodules.

**This directory IS the build context.** `podman build -f build/Containerfile build/` — all `COPY` paths are relative to `build/`.

## File Inventory

| Path | Role |
|------|------|
| `Containerfile` (121L) | Multi-stage image definition: `tools` stage → `ubuntu:26.04` runtime |
| `entrypoint.sh` (509L) | Container ENTRYPOINT — the real bootstrap logic (runs at `podman run`, NOT build time) |
| `.opencode-version` | Single source of truth for OpenCode release (currently `1.17.6`) |
| `.opencode-checksums` | SHA256 for `opencode-linux-{x64,arm64}.tar.gz` — integrity gate |
| `.containerignore` | Excludes `.opencode/{node_modules,bun.lock,package.json}` from build context |
| `.opencode/opencode.json` | **Plugins** (project-level, strict JSON) |
| `.opencode/dcp.json` | Dynamic Context Pruning config (compress at 50%, floor 40%) |
| `.opencode/tui.json` + `themes/` | TUI theming (ayu-dark default) |
| `etc/opencode/opencode.jsonc` | **Runtime behavior** (container-level, JSONC with comments) |
| `etc/npmrc` | Supply-chain: `min-release-age=7`, `ignore-scripts=true` |
| `etc/uv/uv.toml` | Supply-chain: `exclude-newer = "7 days"` |
| `modules/` | 3 git submodules (NEVER modify — see below) |

## Two-Tier Config (CRITICAL)

| File | Scope | Format | Purpose | Image path |
|------|-------|--------|---------|------------|
| `.opencode/opencode.json` | Project | Strict JSON | **Plugins** (npm-pinned) | `/opencode/default/opencode.json` |
| `etc/opencode/opencode.jsonc` | Container | JSONC | **Runtime** (autoupdate, perms, watcher) | `/etc/opencode/opencode.jsonc` |

**Editing the wrong file is the #1 mistake.** Plugins go in `opencode.json`. Runtime behavior goes in `opencode.jsonc`. The jsonc file has a comment pointing to opencode.json for plugins.

## The `COPY etc/ /etc/` Convention

Containerfile L107 copies the **entire** `etc/` tree to `/etc/` wholesale:
- `etc/opencode/opencode.jsonc` → `/etc/opencode/opencode.jsonc`
- `etc/npmrc` → `/etc/npmrc`
- `etc/uv/uv.toml` → `/etc/uv/uv.toml`

**To add new system config**: drop a file at `build/etc/<path>` mirroring the target `/etc/<path>`. No Containerfile edit needed.

## Containerfile Structure

```dockerfile
# Stage 1: pre-built tools (pinned by SHA digest)
FROM ghcr.io/tankdonut/tools:latest@sha256:... AS tools

# Stage 2: runtime
FROM docker.io/library/ubuntu:26.04
# apt deps, bun@1.3.11 global install
# COPY .opencode-version + .opencode-checksums → /etc/
# RUN: curl opencode tarball, sha256sum -c verify, extract → /vendor/bin
# Create non-root user opencode (uid 1001, HOME=/workspace)
# COPY config, entrypoint, modules
USER opencode
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
```

**Key**: entrypoint.sh is COPIED (`--chmod=755`) but **NOT executed** at build time. It runs at every `podman run`.

## entrypoint.sh — Dual-Mode Bootstrap (509L)

### Sourceable + Executable
Line 507 guard: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`
- **Executed** as container ENTRYPOINT → runs `main()`
- **Sourced** by `tests/test_bootstrap.sh` → imports helper functions only

### Bootstrap Flow (main)
```
validate_environment  → check git/node/npm/curl/jq/python3/pip3/yq, PATH
init_submodules       → git submodule update --init --recursive (|| true — optional)
verify_opencode       → opencode --version vs /etc/opencode-version
bootstrap_config      → for each enabled module: copy_config + copy_assets + copy_theme_config
                       ALSO mirrors to /workspace/.config/opencode/
validate_config       → jq empty + plugin count > 0
install_oh_my_opencode → bunx oh-my-opencode install (7 subscription flags) (|| true — optional)
verify_installation   → final checks
print_summary
exec "$@"             → hand off to CMD (/bin/bash) or user args
```

### Helper Functions
- `derive_config_dir` — resolves config destination based on workspace state
- `create_config_dir` — mkdir -p with ownership
- `copy_config` — `cp -n` (no-clobber) unless `OPENCODE_BOOTSTRAP_FORCE=1`
- `copy_assets` — copies **`skills/` only** from each module (asset_dirs array hardcoded to `("skills")`)
- `copy_theme_config` — TUI theme setup
- `is_module_enabled` — checks ECC_ENABLED/OMO_ENABLED/SUPERPOWERS_ENABLED (default: enabled)

### Force Flag
`OPENCODE_BOOTSTRAP_FORCE=1` overwrites existing config. Absent or `0` preserves (uses `cp -n`).

### Known Tricky Logic
1. **Line 425**: `cd "$(dirname "$MODULES_PATH")"` changes CWD globally (no subshell) — side-effect leakage
2. **Line 328**: `${install_cmd} 2>&2 >&2` — unusual redirect, sends all output to stderr (keeps stdout clean)
3. **Lines 227-261**: `bootstrap_config` iterates modules **twice** (once for `/opencode/default`, once for `/workspace`) — duplicated logic, refactor candidate
4. **Line 149/187**: `cp -n` / `cp -rn` — GNU cp extensions; won't work on macOS bash 3.2
5. **Line 79/77**: `${flag_value,,}` (lowercase) and `${!flag_name:-1}` (indirect expansion) — bash 4+ required

## Submodule Wiring (3 Distinct Mechanisms)

**Do not conflate these:**

| Mechanism | What it does | Source |
|-----------|-------------|--------|
| **OpenCode plugin loader** | Fetches npm packages at runtime | `.opencode/opencode.json` plugin[] |
| **Submodule skills copy** | Bakes `skills/` dirs into config at startup | `entrypoint.sh:copy_assets` from `/vendor/modules/` |
| **`bunx oh-my-opencode install`** | Installs multi-agent orchestrator | npm package `oh-my-opencode` (NOT `oh-my-openagent`) |

### Plugin ↔ Submodule Mapping (LOOSE)
| npm package | Submodule | Relationship |
|-------------|-----------|--------------|
| `@tarquinen/opencode-dcp@3.1.13` | — | npm-only |
| `cc-safety-net@1.0.6` | — | npm-only |
| `oh-my-openagent@4.12.0` | `modules/oh-my-openagent` | Name overlaps; submodule supplies skills, npm is the plugin |
| — | `modules/everything-claude-code` | Submodule skills only (not an npm plugin) |
| — | `modules/superpowers` | Submodule skills only (not an npm plugin) |

**No mechanism verifies submodule SHA matches npm package version.** They can drift independently.

## Anti-Patterns (build-specific)

- **Don't** modify anything under `modules/` — upstream-managed, never edit
- **Don't** put plugins in `opencode.jsonc` — use `opencode.json`
- **Don't** run entrypoint.sh at build time (RUN) — it's the ENTRYPOINT, runs at container start
- **Don't** use `:latest` on final FROM — validate.sh hard-fails this (builder stage `:latest` OK)
- **Don't** change base image without updating validate.sh:197 pattern AND AGENTS.md
- **Don't** bump `.opencode-version` without updating `.opencode-checksums` — use `scripts/bump-version.sh`
- **Don't** extend `copy_assets` array to `("skills" "agents" "commands")` without also updating container-test.sh assertions

## Version Pinning Flow

```
.opencode-version (1.17.6) ─┐
.opencode-checksums (2x)   ─┤
                            ├─→ Containerfile COPY → /etc/opencode-{version,checksums}
                            │   → RUN: curl github.com/anomalyco/opencode v1.17.6
                            │         → sha256sum -c → extract → /vendor/bin
scripts/bump-version.sh ────┘   atomic updater (GitHub Releases API)
```

## Quick Reference

```bash
# Verify entrypoint is sourceable (for tests)
bash -c 'source build/entrypoint.sh && type derive_config_dir'

# Check which modules will be enabled
ECC_ENABLED=0 OMO_ENABLED=1 SUPERPOWERS_ENABLED=no \
  podman run --rm opencode-harness -c 'echo enabled modules listed in summary'

# Force re-bootstrap (overwrite existing config)
podman run -e OPENCODE_BOOTSTRAP_FORCE=1 --rm opencode-harness
```
