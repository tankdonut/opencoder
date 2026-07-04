#!/usr/bin/env bash
#
# opencoder - Container Bootstrap Script
#
# This script runs inside the container to set up OpenCode with all plugins.
# It validates configurations, installs dependencies, and verifies the installation.

set -euo pipefail

# Configuration
OPENCODE_VERSION="$(cat /etc/opencode-version 2>/dev/null | tr -d '[:space:]')" || true
readonly OPENCODE_VERSION
readonly OPENCODE_THEME="${OPENCODE_THEME:-ayu-dark}"
readonly CONFIG_PATH="${OPENCODE_CONFIG:-/opencode/default/opencode.json}"
readonly VENDOR_BIN="/vendor/bin"
readonly DEFAULT_CONFIG_SOURCE="/opencode/default/opencode.json"
readonly DEFAULT_TUI_SOURCE="/opencode/default/tui.json"
readonly DEFAULT_THEMES_SOURCE="/opencode/default/themes"
readonly DEFAULT_SKILLS_SOURCE="/opencode/default/.agents/skills"
readonly SKILLS_CLI_VERSION="1.5.13"

# Optional skill sets (installed at runtime, require network)
# ECC_ENABLED=1:           install everything-claude-code skills
# SUPERPOWERS_ENABLED=1:   install superpowers skills
# Both default to disabled. oh-my-openagent skills are always baked in.

# Oh-My-OpenCode (OMO) Installation Options
# OMO_FORCE: Force reinstallation even if config exists
# Subscription flags (passed to bunx oh-my-opencode install):
# OMO_CLAUDE: Claude subscription (yes|no|max20)
# OMO_GEMINI: Gemini subscription (yes|no)
# OMO_COPILOT: GitHub Copilot subscription (yes|no)
# OMO_OPENAI: OpenAI subscription (yes|no)
# OMO_OPENCODE_GO: OpenCode Go subscription (yes|no)
# OMO_OPENCODE_ZEN: OpenCode Zen subscription (yes|no)
# OMO_ZAI_CODING_PLAN: Z.ai Coding Plan subscription (yes|no)

# Colors for output
if [[ -z "${RED:-}" ]]; then readonly RED='\033[0;31m'; fi
if [[ -z "${GREEN:-}" ]]; then readonly GREEN='\033[0;32m'; fi
if [[ -z "${YELLOW:-}" ]]; then readonly YELLOW='\033[1;33m'; fi
if [[ -z "${NC:-}" ]]; then readonly NC='\033[0m'; fi

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" >&2
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $*${NC}" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" >&2
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# =============================================================================
# Bootstrap Helper Functions
# =============================================================================

# Derive config directory from CONFIG_PATH
# Given "/opencode/default/opencode.json", returns "/opencode/default"
derive_config_dir() {
    local config_path="${1:-$CONFIG_PATH}"

    if [[ -z "$config_path" ]]; then
        log_error "derive_config_dir: config_path is required"
        return 1
    fi

    dirname "$config_path"
}

# Create config directory if missing
create_config_dir() {
    local config_dir="${1:-}"

    if [[ -z "$config_dir" ]]; then
        log_error "create_config_dir: config_dir is required"
        return 1
    fi

    if [[ -d "$config_dir" ]]; then
        return 0
    fi

    mkdir -p "$config_dir"
}

# Copy config file from source to target
# Uses cp -n (no overwrite) unless OPENCODE_BOOTSTRAP_FORCE=1
copy_config() {
    local source="${1:-}"
    local target="${2:-}"
    local force="${OPENCODE_BOOTSTRAP_FORCE:-0}"

    if [[ -z "$source" ]] || [[ -z "$target" ]]; then
        log_error "copy_config: source and target are required"
        return 1
    fi

    if [[ ! -f "$source" ]]; then
        log_error "copy_config: source file not found: $source"
        return 1
    fi

    # Ensure target directory exists
    local target_dir
    target_dir=$(dirname "$target")
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir"
    fi

    if [[ "$force" == "1" ]]; then
        cp "$source" "$target"
    elif [[ -f "$target" ]]; then
        # Target exists, skip without force
        log_warn "Config exists at $target, skipping (set OPENCODE_BOOTSTRAP_FORCE=1 to overwrite)"
    else
        # Target missing, use cp -n (no overwrite)
        cp -n "$source" "$target"
    fi
}

copy_theme_config() {
    local config_dir="${1:-}"

    if [[ -z "$config_dir" ]]; then
        log_error "copy_theme_config: config_dir is required"
        return 1
    fi

    if [[ -f "$DEFAULT_TUI_SOURCE" ]]; then
        copy_config "$DEFAULT_TUI_SOURCE" "${config_dir}/tui.json"
    fi

    if [[ -d "$DEFAULT_THEMES_SOURCE" ]]; then
        local themes_dest="${config_dir}/themes"
        if [[ ! -d "$themes_dest" ]]; then
            mkdir -p "$themes_dest"
        fi
        cp -rn "${DEFAULT_THEMES_SOURCE}/." "${themes_dest}/"
        log_success "Theme files copied (${DEFAULT_THEMES_SOURCE})"
    fi
}

# Main bootstrap orchestration - calls all helpers
bootstrap_config() {
    log "Bootstrapping OpenCode configuration..."

    local config_dir
    config_dir=$(derive_config_dir "$CONFIG_PATH")

    create_config_dir "$config_dir"

    copy_config "$DEFAULT_CONFIG_SOURCE" "$CONFIG_PATH"
    copy_theme_config "$config_dir"

    # Sync config to workspace directory for runtime use
    # Ensures /workspace/.config/opencode/opencode.json is managed by
    # the bootstrap process, respecting OPENCODE_BOOTSTRAP_FORCE
    local workspace_config_dir="/workspace/.config/opencode"
    if [[ -d "/workspace" ]]; then
        create_config_dir "$workspace_config_dir"
        copy_config "$DEFAULT_CONFIG_SOURCE" "${workspace_config_dir}/opencode.json"
        copy_theme_config "$workspace_config_dir"
    fi

    log_success "Configuration bootstrap complete"
}

# =============================================================================
# Oh-My-OpenCode Installation
# =============================================================================

install_oh_my_opencode() {
    log "Oh-My-OpenCode installation enabled"

    # Derive config directory from CONFIG_PATH
    local config_dir
    config_dir=$(derive_config_dir "$CONFIG_PATH")

    # Path to oh-my-opencode config
    local omo_config="${config_dir}/oh-my-opencode.json"

    # Check if we need to install
    local should_install=false

    if [[ -f "$omo_config" ]]; then
        if [[ -n "${OMO_FORCE:-}" ]]; then
            log "OMO_FORCE set, will reinstall"
            should_install=true
        else
            log "oh-my-opencode.json exists, skipping (set OMO_FORCE to reinstall)"
            return 0
        fi
    else
        log "oh-my-opencode.json not found, will install"
        should_install=true
    fi

    if [[ "$should_install" != "true" ]]; then
        return 0
    fi

    # Build subscription flags
    local claude_flag="${OMO_CLAUDE:-no}"
    local gemini_flag="${OMO_GEMINI:-no}"
    local copilot_flag="${OMO_COPILOT:-no}"
    local openai_flag="${OMO_OPENAI:-no}"
    local opencode_go_flag="${OMO_OPENCODE_GO:-no}"
    local opencode_zen_flag="${OMO_OPENCODE_ZEN:-no}"
    local zai_coding_plan_flag="${OMO_ZAI_CODING_PLAN:-no}"

    # Build the install command
    local install_cmd="bunx oh-my-opencode install --no-tui"
    install_cmd+=" --claude=${claude_flag}"
    install_cmd+=" --gemini=${gemini_flag}"
    install_cmd+=" --copilot=${copilot_flag}"
    install_cmd+=" --openai=${openai_flag}"
    install_cmd+=" --opencode-go=${opencode_go_flag}"
    install_cmd+=" --opencode-zen=${opencode_zen_flag}"
    install_cmd+=" --zai-coding-plan=${zai_coding_plan_flag}"

    log "Running: ${install_cmd}"

    # Execute installation (redirect output to stderr so it doesn't
    # contaminate stdout when container is used programmatically)
    if ${install_cmd} 2>&2 >&2; then
        log_success "Oh-My-OpenCode installed successfully"

        # Verify config was created
        if [[ -f "$omo_config" ]]; then
            log "Config created at: ${omo_config}"
        else
            log_warn "Config file not found at ${omo_config}"
        fi
    else
        log_error "Oh-My-OpenCode installation failed"
        return 1
    fi
}

# Validate environment
validate_environment() {
    log "Validating environment..."

    # Check required commands
    local required_cmds=("git" "node" "npm" "curl" "jq" "python3" "pip3" "yq")
    for cmd in "${required_cmds[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done

    # Check PATH includes vendor bin
    if [[ ":$PATH:" != *":$VENDOR_BIN:"* ]]; then
        log_warn "Vendor bin not in PATH, adding..."
        export PATH="$VENDOR_BIN:$PATH"
    fi

    log_success "Environment validation passed"
}

# Verify OpenCode installation (pre-installed in container image)
verify_opencode() {
    log "Verifying OpenCode installation..."

    if ! command_exists opencode; then
        log_error "OpenCode not found - this should be pre-installed in the container image"
        return 1
    fi

    local installed_version
    installed_version=$(opencode --version 2>/dev/null | head -n1 || echo "unknown")

    log_success "OpenCode ${installed_version} found"

    # Verify version matches expected (if OPENCODE_VERSION is set)
    if [[ -n "${OPENCODE_VERSION:-}" ]]; then
        if [[ "$installed_version" != *"${OPENCODE_VERSION}"* ]]; then
            log_warn "Installed version (${installed_version}) differs from expected (${OPENCODE_VERSION})"
        fi
    fi
}

# Validate OpenCode configuration
validate_config() {
    log "Validating OpenCode configuration..."

    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Config file not found at $CONFIG_PATH"
        return 1
    fi

    # Validate JSON syntax
    if ! jq empty "$CONFIG_PATH" 2>/dev/null; then
        log_error "Invalid JSON syntax in $CONFIG_PATH"
        return 1
    fi

    # Check for required fields
    local schema_url
    schema_url=$(jq -r '."$schema" // empty' "$CONFIG_PATH")
    if [[ -z "$schema_url" ]]; then
        log_warn "No \$schema field in config (recommended: https://opencode.ai/config.json)"
    fi

    local plugin_count
    plugin_count=$(jq '.plugin | length' "$CONFIG_PATH")
    log "Found ${plugin_count} plugins configured"

    log_success "Configuration validation passed"
}

sync_skills() {
    if [[ ! -d "$DEFAULT_SKILLS_SOURCE" ]]; then
        log_warn "Baseline skills not found at $DEFAULT_SKILLS_SOURCE, skipping sync"
        return 0
    fi

    local workspace_skills="/workspace/.agents/skills"
    mkdir -p "$workspace_skills"

    local force="${OPENCODE_BOOTSTRAP_FORCE:-0}"
    if [[ "$force" == "1" ]]; then
        cp -r "${DEFAULT_SKILLS_SOURCE}/." "${workspace_skills}/"
    else
        cp -rn "${DEFAULT_SKILLS_SOURCE}/." "${workspace_skills}/"
    fi

    local skill_count
    skill_count=$(find "$workspace_skills" -name 'SKILL.md' | wc -l)
    log_success "Synced ${skill_count} skills to workspace"
}

install_optional_skills() {
    local skills_cli="npx --yes skills@${SKILLS_CLI_VERSION}"
    local installed=0

    local ecc_enabled="${ECC_ENABLED:-0}"
    case "${ecc_enabled,,}" in
        1|true|yes)
            log "Installing everything-claude-code skills..."
            if (cd /opencode/default && $skills_cli add affaan-m/everything-claude-code --agent opencode --skill '*' --copy -y) >&2; then
                log_success "everything-claude-code skills installed"
                installed=1
            else
                log_warn "Failed to install everything-claude-code skills (continuing)"
            fi
            ;;
    esac

    local sp_enabled="${SUPERPOWERS_ENABLED:-0}"
    case "${sp_enabled,,}" in
        1|true|yes)
            log "Installing superpowers skills..."
            if (cd /opencode/default && $skills_cli add obra/superpowers --agent opencode --skill '*' --copy -y) >&2; then
                log_success "superpowers skills installed"
                installed=1
            else
                log_warn "Failed to install superpowers skills (continuing)"
            fi
            ;;
    esac

    if [[ "$installed" -eq 1 ]]; then
        sync_skills
    fi
}

# Verify installation
verify_installation() {
    log "Verifying OpenCode installation..."

    # Check OpenCode command
    if ! opencode --version &>/dev/null; then
        log_error "OpenCode command not working"
        return 1
    fi

    # Check config is readable
    if [[ ! -r "$CONFIG_PATH" ]]; then
        log_error "Config file not readable at $CONFIG_PATH"
        return 1
    fi

    # List configured plugins
    log "Configured plugins:"
    jq -r '.plugin[]' "$CONFIG_PATH" | while read -r plugin; do
        log "  - ${plugin}"
    done

    log_success "Installation verification passed"
}

# Print summary
print_summary() {
    log ""
    log "========================================="
    log "  opencoder Bootstrap Complete"
    log "========================================="
    log ""
    log "OpenCode Version: $(opencode --version 2>/dev/null | head -n1 || echo 'unknown')"
    log "Config Path: ${CONFIG_PATH}"
    log "Theme: ${OPENCODE_THEME}"
    log "Plugin Count: $(jq '.plugin | length' "$CONFIG_PATH")"
    log ""
    log "To start using OpenCode:"
    log "  opencode"
    log ""
    log "========================================="
}

# Main execution
main() {
    log "Starting opencoder bootstrap..."
    log ""

    validate_environment || exit 1
    verify_opencode || exit 1
    bootstrap_config || exit 1
    sync_skills || true
    validate_config || exit 1
    if ! install_oh_my_opencode; then
        log_warn "Oh-My-OpenCode installation failed (orchestrator features unavailable; container continues)"
    fi
    install_optional_skills || true
    verify_installation || exit 1

    print_summary

    log_success "Bootstrap completed successfully!"

    if [[ $# -gt 0 ]]; then
        log "Executing: $*"
        exec "$@"
    fi
}

# Run main function (only if executed directly, not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
