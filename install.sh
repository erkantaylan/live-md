#!/usr/bin/env bash
# install.sh — Install or update LiveMD system-wide
# Usage: curl -fsSL https://raw.githubusercontent.com/erkantaylan/livemd/master/install.sh | sudo bash
set -euo pipefail

REPO="erkantaylan/livemd"
INSTALL_DIR="/usr/local/bin"
BINARY="livemd"

# Optional: set LIVEMD_PORT to choose a port (persisted via `livemd port`).
PORT="${LIVEMD_PORT:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[✗]${NC} $*" >&2; }

# --- Detect platform ---
detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        linux)  os="linux" ;;
        darwin) os="darwin" ;;
        *)      err "Unsupported OS: $os"; exit 1 ;;
    esac

    case "$arch" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             err "Unsupported architecture: $arch"; exit 1 ;;
    esac

    echo "${os}-${arch}"
}

# --- Get latest version from GitHub ---
get_latest_version() {
    local url="https://api.github.com/repos/${REPO}/releases/latest"
    curl -fsSL "$url" | grep '"tag_name"' | head -1 | cut -d'"' -f4
}

# --- Main ---
main() {
    echo -e "${BOLD}LiveMD Installer${NC}"
    echo ""

    # Check for root/sudo
    if [[ $EUID -ne 0 ]]; then
        err "This script must be run as root (or with sudo)."
        echo "  Usage: curl -fsSL https://raw.githubusercontent.com/${REPO}/master/install.sh | sudo bash"
        exit 1
    fi

    # Check dependencies
    if ! command -v curl &>/dev/null; then
        err "curl is required but not installed."
        exit 1
    fi

    local platform
    platform="$(detect_platform)"
    info "Platform: ${platform}"

    # Get latest version
    local version
    version="$(get_latest_version)"
    if [[ -z "$version" ]]; then
        err "Could not determine latest version from GitHub."
        exit 1
    fi
    info "Latest version: ${version}"

    # Check existing installation
    local existing=""
    if command -v "$BINARY" &>/dev/null; then
        existing="$(command -v "$BINARY")"
        local current_version
        current_version="$("$existing" version 2>/dev/null | awk '{print $2}' || echo "unknown")"
        warn "Existing installation found: ${existing} (${current_version})"

        # Stop running server if any
        if "$existing" stop 2>/dev/null; then
            info "Stopped running LiveMD server."
        fi
    fi

    # Download
    local asset_name="${BINARY}-${platform}"
    local download_url="https://github.com/${REPO}/releases/download/${version}/${asset_name}"
    local tmp
    tmp="$(mktemp)"

    info "Downloading ${asset_name}..."
    if ! curl -fsSL "$download_url" -o "$tmp"; then
        rm -f "$tmp"
        err "Download failed. Asset '${asset_name}' may not exist for this platform."
        err "Check: https://github.com/${REPO}/releases/tag/${version}"
        exit 1
    fi

    # Install
    chmod 755 "$tmp"
    mv "$tmp" "${INSTALL_DIR}/${BINARY}"
    info "Installed to ${INSTALL_DIR}/${BINARY}"

    # Persist port if requested
    if [[ -n "$PORT" ]]; then
        if "${INSTALL_DIR}/${BINARY}" port "$PORT" >/dev/null 2>&1; then
            info "Default port set to ${PORT}"
        else
            warn "Failed to set port to ${PORT}; using default."
        fi
    fi

    # Confirm PATH (no-op printout on most systems since /usr/local/bin is standard).
    "${INSTALL_DIR}/${BINARY}" ensure-path || true

    # Start the daemon
    if "${INSTALL_DIR}/${BINARY}" start --detach; then
        :
    else
        warn "Daemon did not start cleanly; run 'livemd start --detach' manually."
    fi

    echo ""
    echo -e "${GREEN}${BOLD}LiveMD ${version} installed.${NC}"
    echo ""
    echo "  Watch a file:  livemd add README.md"
    echo "  List watched:  livemd list"
    echo "  Stop server:   livemd stop"
    echo "  Re-install:    re-run this command (idempotent — also updates)"
    echo ""
    if [[ -n "$existing" && "$existing" != "${INSTALL_DIR}/${BINARY}" ]]; then
        warn "Old binary still exists at ${existing} — you may want to remove it."
    fi
}

main "$@"
