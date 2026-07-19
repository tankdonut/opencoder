#!/usr/bin/env bash

set -euo pipefail

# opencode-sandbox.sh — Run OpenCode (or any command) inside a Linux sandbox.
#
# Modes:
#   bwrap   bubblewrap namespaces — lightweight, no daemon, no image
#   gvisor  gVisor (runsc) syscall interception via Podman/Docker — strong boundary
#   nspawn  systemd-nspawn system container — cgroup-backed resource limits
#
# Production precedent for gvisor: Tencent runs millions of gVisor agent
# sandboxes per day for Agentic-RL with a 0.13% correctness gap vs runc.
#   https://gvisor.dev/blog/2026/04/23/scaling-agentic-rl-sandboxes-to-the-millions-with-gvisor-at-tencent/

readonly DEFAULT_IMAGE="ghcr.io/tankdonut/opencoder:latest"
readonly DEFAULT_MODE="bwrap"
readonly DEFAULT_NSPAWN_ROOT="${HOME}/.local/share/opencode-sandbox/rootfs"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log()         { echo -e "${BLUE}[SANDBOX]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[FAIL]${NC} $*" >&2; }

command_exists() { command -v "$1" &>/dev/null; }

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [OPTIONS] [-- COMMAND [ARGS...]]

Run OpenCode inside a Linux sandbox. Default command is "opencode".

Options:
    -m, --mode MODE       Sandbox mode: bwrap, gvisor, nspawn (default: ${DEFAULT_MODE})
        --image IMAGE     Container image for gvisor mode (default: ${DEFAULT_IMAGE})
        --root PATH       rootfs directory for nspawn mode (default: \$HOME/.local/share/opencode-sandbox/rootfs)
        --persist         bwrap: bind project dir read-write so edits persist on the host
        --ephemeral       bwrap: tmpfs overlay over project so edits are discarded on exit
                          (this is the default)
        --home            bwrap/nspawn: also bind \$HOME read-write (warning: exposes SSH
                          keys, ~/.aws, ~/.config, etc. to the sandboxed agent)
        --no-net          Block network access (default: allow, needed for LLM API calls)
    -h, --help            Show this help message

Modes:
    bwrap     bubblewrap namespace sandbox — fastest, no daemon, no image required.
              Best for day-to-day dev workflow. Project dir is mounted in place.
    gvisor    gVisor (runsc) syscall interception via Podman/Docker — strongest
              practical boundary. User-space kernel intercepts every syscall.
              Requires: podman OR docker, plus runsc installed and in PATH.
    nspawn    systemd-nspawn system container — cgroup-backed resource limits,
              full distro env. Requires: systemd-nspawn + a prepared rootfs
              (see --root). Often needs root or CAP_SYS_ADMIN.

Any arguments after -- are passed to the sandboxed command.

Examples:
    $(basename "${BASH_SOURCE[0]}")                              # bwrap + opencode, ephemeral
    $(basename "${BASH_SOURCE[0]}") --mode gvisor                # gVisor via container runtime
    $(basename "${BASH_SOURCE[0]}") --mode bwrap --persist       # bwrap, keep agent edits
    $(basename "${BASH_SOURCE[0]}") -- bash                      # drop into sandboxed shell
    $(basename "${BASH_SOURCE[0]}") --mode gvisor --image alpine:latest -- sh
EOF
}

# ============================================================================
# Dependency checks
# ============================================================================

check_bwrap_deps() {
    if ! command_exists bwrap; then
        log_error "bwrap not found. Install:"
        log_error "  Debian/Ubuntu: sudo apt-get install -y bubblewrap"
        log_error "  Fedora/RHEL:   sudo dnf install -y bubblewrap"
        log_error "  Arch:          sudo pacman -S --noconfirm bubblewrap"
        return 1
    fi
}

check_gvisor_deps() {
    local runtime=""
    if command_exists podman; then
        runtime="podman"
    elif command_exists docker; then
        runtime="docker"
    else
        log_error "gvisor mode requires podman or docker (neither found in PATH)"
        log_error "  podman: https://podman.io/getting-started/installation"
        log_error "  docker: https://docs.docker.com/engine/install/"
        return 1
    fi

    if ! command_exists runsc; then
        log_error "gvisor mode requires the runsc OCI runtime"
        log_error "  Install: https://gvisor.dev/docs/user_guide/install/"
        log_error "  Register with ${runtime}: https://gvisor.dev/docs/user_guide/containerd/"
        return 1
    fi

    GVISOR_RUNTIME="$runtime"
}

check_nspawn_deps() {
    if ! command_exists systemd-nspawn; then
        log_error "systemd-nspawn not found. Install:"
        log_error "  Debian/Ubuntu: sudo apt-get install -y systemd-container"
        log_error "  Fedora/RHEL:   sudo dnf install -y systemd-container"
        return 1
    fi
}

# ============================================================================
# Mode: bubblewrap
# ============================================================================

run_bwrap() {
    check_bwrap_deps || return 1

    local project_dir
    project_dir="$(pwd)"

    local project_args=()
    if [[ "$PERSIST" == true ]]; then
        project_args+=(--bind "$project_dir" "$project_dir")
        log "bwrap: project bound read-write (edits persist on host)"
    else
        # bwrap 0.11.0+ overlay semantics: declare host path as a lower layer
        # with --overlay-src, then mount the overlay target with --tmp-overlay.
        # Writes inside the sandbox land in an invisible tmpfs and are discarded
        # on exit; reads fall through to the host project dir.
        project_args+=(--overlay-src "$project_dir" --tmp-overlay "$project_dir")
        log "bwrap: project mounted with tmpfs overlay (edits discarded on exit)"
    fi

    # Read-only host skeleton: /usr, /etc, /opt, /srv + /lib, /lib64, /bin, /sbin
    # (handle both merged-usr symlinks and real dirs).
    local root_args=()
    local path
    for path in /usr /etc /opt /srv; do
        [[ -e "$path" ]] && root_args+=(--ro-bind "$path" "$path")
    done
    local sl target
    for sl in /lib /lib64 /bin /sbin; do
        if [[ -L "$sl" ]]; then
            target="$(readlink "$sl")"
            root_args+=(--symlink "$target" "$sl")
        elif [[ -d "$sl" ]]; then
            root_args+=(--ro-bind "$sl" "$sl")
        fi
    done

    local home_args=()
    if [[ "$SHARE_HOME" == true ]]; then
        home_args+=(--bind "$HOME" "$HOME")
        log_warn "bwrap: \$HOME shared read-write — agent can read SSH keys, ~/.aws, etc."
    fi

    local net_args=()
    if [[ "$NO_NET" == true ]]; then
        net_args+=(--unshare-net)
        log "bwrap: network unshared (no outbound access)"
    fi

    # --new-session calls setsid() which mitigates TIOCSTI (CVE-2017-5226).
    # PTY still works for interactive TUIs (opencode).
    local namespace_args=(--unshare-pid --unshare-uts --unshare-ipc --new-session)

    local cmd=()
    if [[ ${#SANDBOX_CMD[@]} -gt 0 ]]; then
        cmd=("${SANDBOX_CMD[@]}")
    else
        cmd=("opencode")
    fi

    log "bwrap: project=${project_dir}"
    log "bwrap: command=${cmd[*]}"

    exec bwrap \
        "${root_args[@]}" \
        --proc /proc --dev /dev \
        --tmpfs /tmp --tmpfs /run \
        "${home_args[@]+"${home_args[@]}"}" \
        "${project_args[@]}" \
        "${namespace_args[@]}" \
        "${net_args[@]+"${net_args[@]}"}" \
        --chdir "$project_dir" \
        "${cmd[@]}"
}

# ============================================================================
# Mode: gVisor via Podman/Docker
# ============================================================================

run_gvisor() {
    check_gvisor_deps || return 1

    local project_dir
    project_dir="$(pwd)"

    local net_args=()
    if [[ "$NO_NET" == true ]]; then
        net_args+=(--network=none)
        log "gvisor: network disabled"
    fi

    local cmd=()
    if [[ ${#SANDBOX_CMD[@]} -gt 0 ]]; then
        cmd=("${SANDBOX_CMD[@]}")
    else
        cmd=("opencode")
    fi

    log "gvisor: runtime=${GVISOR_RUNTIME} (runsc)"
    log "gvisor: image=${IMAGE}"
    log "gvisor: project=${project_dir} -> /work"
    log "gvisor: command=${cmd[*]}"

    # :Z relabels for SELinux (no-op elsewhere); required on Fedora/RHEL.
    exec "${GVISOR_RUNTIME}" run \
        --runtime=runsc \
        -it --rm \
        -v "${project_dir}:/work:Z" \
        -w /work \
        "${net_args[@]+"${net_args[@]}"}" \
        "${IMAGE}" \
        "${cmd[@]}"
}

# ============================================================================
# Mode: systemd-nspawn
# ============================================================================

run_nspawn() {
    check_nspawn_deps || return 1

    if [[ ! -d "$NSPAWN_ROOT" ]]; then
        log_error "nspawn rootfs not found: ${NSPAWN_ROOT}"
        log_error "Prepare one (Ubuntu example):"
        log_error "  sudo debootstrap noble ${NSPAWN_ROOT} http://archive.ubuntu.com/ubuntu/"
        log_error "Or (Fedora):"
        log_error "  sudo dnf install -y --installroot=${NSPAWN_ROOT} @core"
        log_error "Then install opencode inside the rootfs before running this mode."
        return 1
    fi

    local project_dir
    project_dir="$(pwd)"

    local home_args=()
    if [[ "$SHARE_HOME" == true ]]; then
        home_args+=(--bind="${HOME}:${HOME}")
        log_warn "nspawn: \$HOME shared — agent can read SSH keys, ~/.aws, etc."
    fi

    local net_args=()
    if [[ "$NO_NET" == true ]]; then
        net_args+=(--private-network)
        log "nspawn: private network (no outbound)"
    fi

    local cmd=()
    if [[ ${#SANDBOX_CMD[@]} -gt 0 ]]; then
        cmd=("${SANDBOX_CMD[@]}")
    else
        cmd=("opencode")
    fi

    log "nspawn: rootfs=${NSPAWN_ROOT}"
    log "nspawn: project=${project_dir} -> /work"
    log "nspawn: command=${cmd[*]}"
    log_warn "nspawn: if this fails with EPERM, retry with sudo (or use systemd-nspawn -U manually)"

    # --as-pid2: a minimal init runs as PID 1, the user command as PID 2
    # (proper signal handling/reaping).
    exec systemd-nspawn \
        --quiet \
        --as-pid2 \
        --root="$NSPAWN_ROOT" \
        --bind="${project_dir}:/work" \
        "${home_args[@]+"${home_args[@]}"}" \
        "${net_args[@]+"${net_args[@]}"}" \
        --chdir=/work \
        "${cmd[@]}"
}

# ============================================================================
# Argument parsing
# ============================================================================

parse_args() {
    MODE="$DEFAULT_MODE"
    IMAGE="$DEFAULT_IMAGE"
    NSPAWN_ROOT="$DEFAULT_NSPAWN_ROOT"
    PERSIST=false
    SHARE_HOME=false
    NO_NET=false
    SANDBOX_CMD=()

    local parse_passthrough=false
    while [[ $# -gt 0 ]]; do
        if [[ "$parse_passthrough" == true ]]; then
            SANDBOX_CMD+=("$1")
            shift
            continue
        fi

        case "$1" in
            -m|--mode)
                MODE="${2:-}"
                [[ -z "$MODE" ]] && { log_error "--mode requires a value"; exit 2; }
                shift 2
                ;;
            --image)
                IMAGE="${2:-}"
                [[ -z "$IMAGE" ]] && { log_error "--image requires a value"; exit 2; }
                shift 2
                ;;
            --root)
                NSPAWN_ROOT="${2:-}"
                [[ -z "$NSPAWN_ROOT" ]] && { log_error "--root requires a value"; exit 2; }
                shift 2
                ;;
            --persist)
                PERSIST=true
                shift
                ;;
            --ephemeral)
                PERSIST=false
                shift
                ;;
            --home)
                SHARE_HOME=true
                shift
                ;;
            --no-net)
                NO_NET=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                parse_passthrough=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 2
                ;;
        esac
    done

    case "$MODE" in
        bwrap|gvisor|nspawn) ;;
        *)
            log_error "Invalid mode: ${MODE} (use bwrap, gvisor, or nspawn)"
            exit 2
            ;;
    esac

    if [[ "$PERSIST" == true ]] && [[ "$MODE" != "bwrap" ]]; then
        log_warn "--persist only applies to bwrap mode (ignored for ${MODE})"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    parse_args "$@"

    case "$MODE" in
        bwrap)   run_bwrap  || exit 1 ;;
        gvisor)  run_gvisor || exit 1 ;;
        nspawn)  run_nspawn || exit 1 ;;
    esac
}

main "$@"
