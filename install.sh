#!/bin/bash

# Ubuntu Stale Session Manager Installer with Checksum Verification
# Version: 2.0
# License: MIT

# Configuration
REPO_OWNER="your-github-username"
REPO_NAME="your-repo-name"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

# Paths
BIN_PATH="/usr/local/bin/stale-session-manager"
CONFIG_FILE="/etc/stale_session_manager.conf"
LOG_FILE="/var/log/stale_session_manager.log"
SERVICE_FILE="/etc/systemd/system/stale-session-cleaner.service"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Temp directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

secure_download() {
    local url=$1
    local output=$2
    
    if command -v curl &> /dev/null; then
        if ! curl -fsSL "$url" -o "$output"; then
            echo -e "${RED}Error: Failed to download ${url}${NC}"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if ! wget -qO "$output" "$url"; then
            echo -e "${RED}Error: Failed to download ${url}${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Need curl or wget to download files${NC}"
        exit 1
    fi
}

verify_checksums() {
    echo -e "${YELLOW}Verifying checksums...${NC}"
    
    # Download checksum file
    secure_download "${BASE_URL}/checksums.sha256" "${TMP_DIR}/checksums.sha256"
    
    # Verify all files
    if ! (cd "$TMP_DIR" && sha256sum -c checksums.sha256 --quiet); then
        echo -e "${RED}ERROR: Checksum verification failed!${NC}"
        echo -e "${YELLOW}Possible causes:"
        echo "- File corruption during download"
        echo "- Security breach (files modified on server)"
        echo "- Outdated checksums (contact maintainer)${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y mailutils
    elif command -v yum &> /dev/null; then
        yum install -y mailx
    elif command -v dnf &> /dev/null; then
        dnf install -y mailx
    else
        echo -e "${YELLOW}Please install mail utilities manually if needed${NC}"
    fi
}

setup_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}Creating default config...${NC}"
        cat > "$CONFIG_FILE" <<EOL
# Stale Session Manager Configuration
MAX_IDLE_MINUTES=120
WHITELIST=(root admin)
NOTIFY_ADMIN=false
ADMIN_EMAIL="admin@example.com"
EOL
        chmod 644 "$CONFIG_FILE"
    fi
}

setup_logging() {
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

setup_service() {
    echo -e "${YELLOW}Configuring systemd service...${NC}"
    
    cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Stale Session Cleaner
After=network.target

[Service]
Type=oneshot
ExecStart=${BIN_PATH} --idle 120 --notify

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload
}

install() {
    check_root

    # Download all necessary files
    secure_download "${BASE_URL}/linux-stale-session-manager.sh" "${TMP_DIR}/linux-stale-session-manager.sh"
    secure_download "${BASE_URL}/install.sh" "${TMP_DIR}/install.sh"

    # Verify checksums
    verify_checksums

    # Install main script
    echo -e "${YELLOW}Installing main script...${NC}"
    install -m 755 "${TMP_DIR}/linux-stale-session-manager.sh" "$BIN_PATH"

    # Setup environment
    install_dependencies
    setup_config
    setup_logging
    setup_service

    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "Run with: ${YELLOW}sudo stale-session-manager${NC}"
}

uninstall() {
    check_root

    echo -e "${YELLOW}Uninstalling...${NC}"

    rm -f "$BIN_PATH"
    systemctl stop stale-session-cleaner 2>/dev/null
    systemctl disable stale-session-cleaner 2>/dev/null
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload

    echo -e "${GREEN}Uninstallation complete!${NC}"
    echo -e "${YELLOW}Note: Config ($CONFIG_FILE) and logs ($LOG_FILE) were kept.${NC}"
}

# Main execution
if [[ "$*" == *"--uninstall"* ]]; then
    uninstall
elif [[ "$*" == *"--verify"* ]]; then
    install
else
    echo -e "${RED}WARNING: Unverified installation${NC}"
    echo "For secure installation with checksum verification, run:"
    echo -e "${YELLOW}curl -fsSL ${BASE_URL}/install.sh | sudo bash -s -- --verify${NC}"
    echo ""
    read -p "Continue without verification? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install
    else
        echo -e "${RED}Installation aborted${NC}"
        exit 1
    fi
fi
