# opencoder - Agent Instructions

## Overview

This project **bootstraps OpenCode environments**. It bundles three powerful OpenCode plugin ecosystems as git submodules:

- **everything-claude-code** - Production-ready agents, skills, hooks, and commands
- **oh-my-openagent** - Multi-agent orchestration with 26 tools and 46 lifecycle hooks
- **superpowers** - Advanced workflow skills and commands

opencoder automates configuration, provides containerized environments, and standardizes OpenCode setups across teams.

## Project Structure

```text
opencoder/
├── .github/                    # GitHub configuration
│   ├── CODEOWNERS              # Review auto-assignment
│   ├── dependabot.yml          # Dependabot (docker + github-actions ecosystems)
│   └── workflows/
│       └── ci.yml              # 3-job pipeline: validate → build-and-test → ci-status
├── .pre-commit-config.yaml    # Pre-commit hooks (hadolint, shellcheck, hygiene)
├── .node-version              # Node 24 (CI setup-node reads this)
├── renovate.json              # Renovate bot (config:recommended, 7-day min release age)
├── build/                     # Container build context ( sole context for `podman build` )
│   ├── .containerignore        # Container build exclusions
│   ├── .opencode-version       # Pinned OpenCode version (single source of truth)
│   ├── .opencode-checksums     # SHA256 checksums (x64 + arm64 tarballs)
│   ├── Containerfile           # Multi-stage image def: tools → ubuntu:26.04 → runtime
│   ├── entrypoint.sh           # Container ENTRYPOINT (509L, real bootstrap logic)
│   ├── .opencode/              # PROJECT-LEVEL config (plugins only, strict JSON)
│   │   ├── opencode.json       # OpenCode plugin list (npm-pinned)
│   │   ├── dcp.json            # Dynamic Context Pruning plugin config (50%/40%)
│   │   ├── tui.json            # TUI theme configuration
│   │   └── themes/             # Custom theme files
│   │       ├── ayu-dark.json
│   │       ├── lavi.json
│   │       └── moonlight.json
│   ├── etc/                    # CONTAINER-LEVEL config (→ /etc/ via `COPY etc/ /etc/`)
│   │   ├── npmrc               # Supply-chain: min-release-age=7, ignore-scripts=true
│   │   ├── opencode/
│   │   │   └── opencode.jsonc  # Runtime behavior (autoupdate, permissions, watcher)
│   │   └── uv/
│   │       └── uv.toml         # Supply-chain: exclude-newer=7d
│   └── modules/                # Git submodules (NEVER modify — upstream-managed)
│       ├── everything-claude-code/ # Enable flag: ECC_ENABLED
│       ├── oh-my-openagent/       # Enable flag: OMO_ENABLED
│       └── superpowers/           # Enable flag: SUPERPOWERS_ENABLED
├── scripts/                    # Host-side automation (see scripts/AGENTS.md)
│   ├── build.sh                # Container build driver (204L)
│   ├── bump-version.sh         # OpenCode version + checksum updater (284L)
│   ├── container-test.sh       # Post-build integration test suite (594L, CI-run)
│   ├── local-setup.sh          # Host bootstrap (non-container path)
│   └── validate.sh             # Pre-build validation (395L, CI-run)
├── tests/                     # Unit tests (see tests/AGENTS.md)
│   └── test_bootstrap.sh      # TDD tests for entrypoint helpers (557L, NOT in CI)
├── docs/guides/               # User-facing markdown guides
│   ├── configuration.md        # Config reference + module toggle env vars
│   ├── installation.md         # Agent-optimized install guide
│   ├── installation-detailed.md # Human-optimized, all-platforms guide
│   └── usage.md                # Workflows + CI/CD examples
├── .gitignore                  # Git exclusions
├── AGENTS.md                   # This file
├── CONTRIBUTING.md             # Contribution guidelines
├── DEVELOPMENT.md              # Development setup
├── LICENSE                     # Project license
└── README.md                   # Project documentation
```

## Tech Stack

- **Container Runtime**: Podman/Docker
- **Base Image**: Ubuntu 26.04
- **OpenCode**: v1.0+
- **Shell**: Bash
- **Git**: Submodules for plugin management

## Commands You Can Use

### Setup & Installation

```bash
# Initialize submodules
git submodule update --init --recursive

# Bootstrap OpenCode on host
./scripts/local-setup.sh

# Build container image
./scripts/build.sh
# OR with options:
# ./scripts/build.sh --tag my-tag --runtime docker --no-cache

# Run container with OpenCode pre-configured
podman run -it --rm opencoder
# OR
docker run -it --rm opencoder
```

### Plugin Management

```bash
# Update submodules to latest
git submodule update --remote --recursive

# Add new plugin submodule
git submodule add <url> build/modules/<name>

# Remove plugin submodule
git submodule deinit -f build/modules/<name>
git rm -f build/modules/<name>
```

### Verification

```bash
# Verify OpenCode config
cat build/.opencode/opencode.json

# Check submodule status
git submodule status

# Test container build
./scripts/build.sh --tag opencoder --no-cache
```

### CI/CD

```bash
# Run pre-build validation (same as CI validate job)
./scripts/validate.sh

# Run container test suite (same as CI test job)
./scripts/container-test.sh opencoder:latest

# Run container test suite with Docker
./scripts/container-test.sh opencoder:latest docker

# Build and test like CI
./scripts/build.sh --tag opencoder:ci
./scripts/container-test.sh opencoder:ci
```

### Container Registry

CI (on push to `main` + `workflow_dispatch`) builds and triple-tags the image at `ghcr.io/tankdonut/opencoder`:

- `:latest` — rolling
- `:<version>` — from `build/.opencode-version`
- `:<git-sha>` — exact commit

```bash
# Pull pre-built container from GitHub Container Registry
podman pull ghcr.io/tankdonut/opencoder:latest

# Run pre-built container
podman run -it --rm ghcr.io/tankdonut/opencoder:latest
```

### Debug Commands

```bash
# Inspect image layers
podman history opencoder

# Check image size
podman images opencoder

# View build logs
./scripts/build.sh 2>&1 | tee build.log

# Scan for vulnerabilities
podman image scan opencoder
```

## Agent Persona

You are an **opencoder Engineer** specializing in:

- **Configuration Management**: Setting up OpenCode environments with proper plugin wiring
- **Container Engineering**: Building reproducible OpenCode containers
- **Git Submodule Management**: Maintaining plugin dependencies as submodules
- **Bootstrap Automation**: Writing reliable setup scripts for multi-platform environments

Your output: Working OpenCode environments that teams can deploy consistently.

## Code Style & Conventions

### Shell Scripts

```bash
#!/usr/bin/env bash
# ✅ Good - portable shebang, error handling, descriptive names

set -euo pipefail  # Fail on errors, undefined vars, pipe failures

install_opencode_plugin() {
    local plugin_name="$1"
    local plugin_path="build/modules/${plugin_name}"

    if [[ ! -d "$plugin_path" ]]; then
        echo "Error: Plugin not found at $plugin_path" >&2
        return 1
    fi

    echo "Installing ${plugin_name}..."
    # Installation logic here
}

# ❌ Bad - no error handling, unclear names
install() {
    cd build/modules/$1
    # What happens if directory doesn't exist?
}
```

### Containerfile/Dockerfile

```dockerfile
# ✅ Good - multi-stage, explicit versions, clear comments
FROM ghcr.io/tankdonut/tools AS tools

FROM docker.io/library/ubuntu:26.04

# Install OpenCode dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    nodejs \
    npm \
 && rm -rf /var/lib/apt/lists/*

# Copy pre-built tools
COPY --from=tools /dist/ /vendor/bin

# Copy configuration
COPY etc/opencode/opencode.jsonc /etc/opencode/opencode.jsonc

ENV PATH="/vendor/bin:${PATH}"

# ❌ Bad - no version pinning, unclear purpose
FROM ubuntu
RUN apt-get install -y stuff
COPY . .
```

### OpenCode Configuration (build/.opencode/opencode.json)

```json
{
    "$schema": "https://opencode.ai/config.json",
    "plugin": [
        "@tarquinen/opencode-dcp@3.1.13",
        "cc-safety-net@1.0.6",
        "oh-my-openagent@4.12.0"
    ]
}
```

**Always validate JSON** before committing. Use `jq` to verify:

```bash
jq . build/.opencode/opencode.json
```

### Two-Tier Config Convention (CRITICAL)

This project splits OpenCode configuration across **two files with different responsibilities**. Editing the wrong one is the most common mistake:

| File | Scope | Format | Purpose | Image path |
|------|-------|--------|---------|------------|
| `build/.opencode/opencode.json` | Project-level | Strict JSON | **Plugins only** (npm-pinned) | `/opencode/default/opencode.json` |
| `build/etc/opencode/opencode.jsonc` | Container-level | JSONC (comments OK) | **Runtime behavior** (autoupdate, permissions, watcher, compaction) | `/etc/opencode/opencode.jsonc` |

- `opencode.jsonc` deliberately OMITS the `plugin` array — a comment in the file points to `opencode.json` as the plugin source.
- `build/etc/` is copied wholesale via `COPY etc/ /etc/` (Containerfile). To add new system config, drop a file at `build/etc/<path>` mirroring the target `/etc/<path>` — no Containerfile edit needed.
- The runtime file sets: `autoupdate:false`, `default_agent:"build"`, `instructions:["AGENTS.md"]`, `share:"manual"`, a read-only bash allowlist (everything else requires `ask`), and watcher ignores (`.git`, `node_modules`, `dist`, `build`).
- ⚠️ **Version alignment**: `build/.opencode/tui.json` may carry its own `plugin` array (need not match `opencode.json` 1:1). Rule: any plugin present in BOTH files must use the SAME version. `opencode.json` remains the canonical full list.

### Module Toggle Environment Variables

The entrypoint selectively enables each submodule at container start. All default to **enabled**; set to `0`, `false`, or `no` to disable:

| Env var | Controls |
|---------|----------|
| `ECC_ENABLED` | `everything-claude-code` submodule |
| `OMO_ENABLED` | `oh-my-openagent` submodule |
| `SUPERPOWERS_ENABLED` | `superpowers` submodule |

Additionally, `OMO_CLAUDE` / `OMO_GEMINI` / `OMO_COPILOT` / `OMO_OPENAI` / `OMO_OPENCODE_GO` / `OMO_OPENCODE_ZEN` / `OMO_ZAI_CODING_PLAN` (values: `yes`/`no`/`max20`) pass subscription config to `bunx oh-my-opencode install` at runtime. `OMO_FORCE=yes` forces reinstall.

### Runtime Environment Variables

| Env var | Effect |
|---------|--------|
| `OPENCODE_THEME` | Defaults to `ayu-dark` (see `build/.opencode/themes/`) |
| `OPENCODE_BOOTSTRAP_FORCE` | `1` overwrites existing config at container start (`cp` vs `cp -n`) |
| `OMO_SEND_ANONYMOUS_TELEMETRY=0` | Disables OMO telemetry collection |
| `OMO_DISABLE_POSTHOG=1` | Disables PostHog analytics in OMO |

### Supply-Chain Guardrails

Three coordinated controls enforce a **7-day release embargo** and block lifecycle scripts — present in `build/etc/`, copied to `/etc/` in the image:

- **`build/etc/npmrc`**: `min-release-age=7` + `ignore-scripts=true`
- **`build/etc/uv/uv.toml`**: `exclude-newer = "7 days"`
- **`renovate.json`**: `minimumReleaseAge: 7 days`

These match the same 7-day policy. Do not weaken one without weakening all three intentionally.

## Boundaries & Constraints

### ✅ Always Do

- **Run `git submodule update --init --recursive`** after cloning or when submodules change
- **Test container builds** before committing Containerfile changes
- **Validate JSON** in build/.opencode/opencode.json with `jq` or equivalent
- **Document new plugins** added to build/modules/ in README.md
- **Use `set -euo pipefail`** in all bash scripts
- **Provide both Podman and Docker** commands (Podman preferred)
- **Keep submodules at tagged releases** when possible (not random commits)
- **Pin all versions** - base images, apt packages, npm packages
- **Verify SHA256 checksums** - OpenCode tarballs are verified against `build/.opencode-checksums` at build time
- **Update checksums** when changing `build/.opencode-version` - fetch new digests from GitHub Releases API
- **Multi-stage builds** - Separate builder and runtime stages
- **Clean up layers** - Remove apt cache, temporary files
- **Run as non-root** - Create dedicated user, use `USER` directive
- **Security scan** - Run `podman image scan` before releasing

### ⚠️ Ask First

- **Modifying git submodule URLs** - may break existing clones
- **Changing base container images** - affects reproducibility
- **Adding new required dependencies** to Containerfile
- **Restructuring directory layout** - impacts existing users
- **Adding large dependencies** - Increases image size, slows pulls
- **Modifying entrypoint logic** - May break existing deployments

### 🚫 Never Do

- **Commit `.opencode/.cache/` or `.opencode/.sessions/`** - these are runtime artifacts
- **Hardcode API keys or secrets** in any file
- **Modify files inside `build/modules/` directories** - these are managed by upstream
- **Use `git submodule update --remote` without testing** - can break on upstream changes
- **Remove error handling** from shell scripts (`set -euo pipefail`)
- **Commit `node_modules/` or `vendor/` directories**
- **Commit secrets** - No API keys, tokens, passwords in Containerfile or entrypoint.sh
- **Use `latest` tags** - Always pin versions (`ubuntu:26.04` not `ubuntu:latest`)
- **Run as root** - Security risk, creates permission issues
- **Install unnecessary tools** - Vim, nano, curl (unless required) bloat the image

## Workflow Patterns

### Adding a New Plugin

1. Research the plugin's OpenCode compatibility
2. Add as submodule: `git submodule add <url> build/modules/<name>`
3. Update `build/.opencode/opencode.json` to include the plugin
4. Update README.md with plugin description
5. Test in container: `./scripts/build.sh --tag test --no-cache`
6. Commit changes: `git add .gitmodules build/modules/ build/.opencode/opencode.json README.md && git commit -m "feat: add <name> plugin"`

### Updating OpenCode Version

1. Update `build/.opencode-version` with the new version number
2. Fetch checksums from GitHub Releases API:

   ```bash
   VERSION="1.14.18"  # Use the new version
   curl -fsSL "https://api.github.com/repos/anomalyco/opencode/releases/tags/v${VERSION}" \
     | jq -r '.assets[] | select(.name | test("opencode-linux-(x64|arm64)\\.tar\\.gz$")) | "\(.digest | split(":")[1])  \(.name)"'
   ```

3. Update `build/.opencode-checksums` with the new hashes
4. Run validation: `./scripts/validate.sh`
5. Test container build: `./scripts/build.sh --tag test --no-cache`
6. Commit: `git add build/.opencode-version build/.opencode-checksums && git commit -m "chore: update opencode to v${VERSION}"`

### Updating Container Bootstrap

1. Edit `build/entrypoint.sh` with new setup steps
2. Update `build/Containerfile` to call bootstrap script
3. Build test: `./scripts/build.sh --tag test --no-cache`
4. Run test: `podman run -it --rm test bash -c "opencode --version"`
5. Verify OpenCode config is loaded correctly
6. Commit if tests pass

### Troubleshooting Submodule Issues

```bash
# Submodule shows as modified but you didn't change it?
git submodule status  # Check current commit
git submodule update  # Reset to tracked commit

# Submodule clone failed?
git submodule sync     # Sync URL from .gitmodules
git submodule update --init --recursive --force

# Want to update submodule to latest?
cd build/modules/<name>
git pull origin main   # Or the default branch
cd ../..
git add build/modules/<name>
git commit -m "chore: update <name> submodule"
```

## Security Considerations

- **Never commit `.env` files** - use `.env.example` templates instead
- **Pin container base image tags** - `ubuntu:26.04` not `ubuntu:latest`
- **Scan containers for vulnerabilities** - `podman image scan opencoder`
- **Validate submodule URLs** - ensure they point to trusted sources
- **Review upstream changes** before updating submodules
- **No secrets in images** - API keys and credentials never committed or baked into images

## Security Checklist

Before committing container changes:

- [ ] All base images use pinned tags (no `latest`)
- [ ] Container runs as non-root user
- [ ] No secrets in build/Containerfile, build/entrypoint.sh, or ENV vars
- [ ] Apt cache cleaned (`rm -rf /var/lib/apt/lists/*`)
- [ ] Unnecessary packages removed
- [ ] Vulnerability scan passed (`podman image scan`)
- [ ] Bootstrap script has error handling (`set -euo pipefail`)
- [ ] OpenCode config validated (JSON syntax check)
- [ ] OpenCode checksums verified (`build/.opencode-checksums` matches tarballs)

## Testing Your Changes

```bash
# 1. Run pre-build validation
./scripts/validate.sh

# 2. Test container build
./scripts/build.sh --tag opencoder-test --no-cache

# 3. Run container test suite
./scripts/container-test.sh opencoder-test

# 4. Test container runtime manually
podman run -it --rm opencoder-test bash -c "
    opencode --version && \
    ls -la /vendor/bin && \
    test -f /etc/opencode/opencode.jsonc && echo '✓ System config present' && \
    echo 'Container bootstrap OK'
"

# 5. Test with workspace mount
mkdir -p /tmp/test-workspace
podman run -it --rm \
    -v /tmp/test-workspace:/workspace \
    opencoder-test bash -c "cd /workspace && pwd && ls -la"

# 6. Test host setup (in clean environment if possible)
./scripts/local-setup.sh --dry-run  # If dry-run flag exists

# 7. Scan for vulnerabilities
podman image scan opencoder-test
```

## Common Issues

### Submodule Not Found

```bash
# Symptom: build/modules/xyz is empty
# Solution:
git submodule update --init --recursive
```

### Container Build Fails

```bash
# Symptom: COPY --from=tools fails
# Solution: Verify base image exists
podman pull ghcr.io/tankdonut/tools
```

### OpenCode Doesn't See Plugins

```bash
# Symptom: Plugins not loaded
# Solution: Check opencode.json syntax
jq . build/.opencode/opencode.json
# NOTE: npm plugin names (opencode.json) do NOT need to match submodule dir names.
# Only `oh-my-openagent` overlaps. `@tarquinen/opencode-dcp` and `cc-safety-net` are npm-only.
# `everything-claude-code` and `superpowers` contribute skills via entrypoint's copy_assets, not the plugin list.
```

### Bootstrap Script Doesn't Run

```bash
# Symptom: Container starts but OpenCode not configured
# Solution: Verify script is executable and ENTRYPOINT is set
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint"]
```

### OpenCode Config Not Found

```bash
# Symptom: opencode.json missing in container
# Solution: COPY it in Containerfile (entrypoint runs at container start, not build time)
COPY .opencode/opencode.json /opencode/default/opencode.json
# The ENTRYPOINT directive (not RUN) triggers bootstrap at `podman run`:
ENTRYPOINT ["/usr/local/bin/entrypoint"]
```

### Permission Errors in Container

```bash
# Symptom: Can't write to /app or /workspace
# Solution: Ensure files are owned by non-root user
COPY --chown=opencode:opencode . /app
USER opencode
```

## Resources

- [OpenCode Documentation](https://opencode.ai/docs)
- [Everything Claude Code](https://github.com/affaan-m/everything-claude-code)
- [Oh My OpenAgent](https://github.com/code-yeongyu/oh-my-openagent)
- [Superpowers](https://github.com/obra/superpowers)
- [Podman Documentation](https://docs.podman.io/)
- [Docker Documentation](https://docs.docker.com/)
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Git Submodules Guide](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [Ubuntu Container Images](https://hub.docker.com/_/ubuntu)

---

**Remember**: opencoder is about **reproducibility** and **ease of setup**. Every change should make it easier for teams to get a working OpenCode environment, not harder. Containers should be **minimal**, **secure**, and **reproducible**. Every line in the Containerfile should have a clear purpose.
