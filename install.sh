#!/bin/bash

# Ubuntu Stale Session Manager Installer
# Version: 1.0
# License: MIT

# Configuration
SCRIPT_URL="https://raw.githubusercontent.com/lpolish/linux-stale-session-manager/main/linux-stale-session-manager.sh"
CONFIG_FILE="/etc/stale_session_manager.conf"
BIN_PATH="/usr/local/bin/stale-session-manager"
LOG_FILE="/var/log/stale_session_manager.log"
SERVICE_FILE="/etc/systemd/system/stale-session-cleaner.service"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo $ID
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

# Secure download function
secure_download() {
    if command -v curl &> /dev/null; then
        curl -sSL "$1" -o "$2"
    elif command -v wget &> /dev/null; then
        wget -qO "$2" "$1"
    else
        echo -e "${RED}Error: Neither curl nor wget found. Please install one.${NC}"
        exit 1
    fi

    if [[ ! -s "$2" ]]; then
        echo -e "${RED}Error: Download failed or empty file${NC}"
        exit 1
    fi
}

# Verify script checksum (placeholder - replace with actual verification)
verify_checksum() {
    local file_path=$1
    local expected_sha

    # Get the expected SHA256 from GitHub
    if ! expected_sha=$(fetch_checksum); then
        echo -e "${RED}Error: Failed to fetch checksum${NC}"
        return 1
    fi

    # Calculate actual SHA256
    actual_sha=$(sha256sum "$file_path" | awk '{print $1}')

    if [[ "$expected_sha" != "$actual_sha" ]]; then
        echo -e "${RED}Error: Checksum verification failed${NC}"
        echo -e "Expected: $expected_sha"
        echo -e "Actual:   $actual_sha"
        return 1
    fi

    return 0
}

fetch_checksum() {
    local checksum_url="https://raw.githubusercontent.com/lpolish/linux-stale-session-manager/main/checksums.txt"

    if command -v curl &> /dev/null; then
        curl -sSL "$checksum_url" | grep "linux-stale-session-manager.sh" | awk '{print $1}'
    elif command -v wget &> /dev/null; then
        wget -qO - "$checksum_url" | grep "linux-stale-session-manager.sh" | awk '{print $1}'
    else
        echo -e "${RED}Error: Need curl or wget to fetch checksum${NC}"
        return 1
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing required dependencies...${NC}"
    case $(detect_distro) in
        ubuntu|debian)
            apt-get update
            apt-get install -y mailutils
            ;;
        rhel|centos|fedora)
            yum install -y mailx
            ;;
        *)
            echo "Please install mail utilities manually"
            ;;
    esac
}

# Install the script
install() {
    echo -e "${YELLOW}Installing Ubuntu Stale Session Manager...${NC}"

    # Download the script
    echo "Downloading latest version..."
    secure_download "$SCRIPT_URL" "$BIN_PATH"

    # Verify checksum
    if ! verify_checksum; then
        echo -e "${RED}Error: Checksum verification failed${NC}"
        exit 1
    fi

    # Make executable
    chmod +x "$BIN_PATH"

    # Create default config if not exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "MAX_IDLE_MINUTES=120" > "$CONFIG_FILE"
        echo "WHITELIST=(root admin)" >> "$CONFIG_FILE"
        echo "NOTIFY_ADMIN=false" >> "$CONFIG_FILE"
        echo "ADMIN_EMAIL=\"admin@example.com\"" >> "$CONFIG_FILE"
    fi

    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"

    # Create systemd service for automated cleaning
    cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Stale Session Cleaner
After=network.target

[Service]
Type=oneshot
ExecStart=$BIN_PATH --idle 120 --notify

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reload

    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "You can now run: ${YELLOW}sudo stale-session-manager${NC}"
}

# Uninstall the script
uninstall() {
    echo -e "${YELLOW}Uninstalling Ubuntu Stale Session Manager...${NC}"

    # Remove main script
    rm -f "$BIN_PATH"

    # Remove config file
    read -p "Remove configuration file at $CONFIG_FILE? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$CONFIG_FILE"
    fi

    # Remove log file
    read -p "Remove log file at $LOG_FILE? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$LOG_FILE"
    fi

    # Remove systemd service
    if [[ -f "$SERVICE_FILE" ]]; then
        systemctl stop stale-session-cleaner 2>/dev/null
        systemctl disable stale-session-cleaner 2>/dev/null
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    fi

    echo -e "${GREEN}Uninstallation completed!${NC}"
}

# Show usage
usage() {
    echo "Ubuntu Stale Session Manager Installer"
    echo "Usage:"
    echo "  ./install.sh               - Install the script"
    echo "  ./install.sh --uninstall   - Remove the script"
    echo "  curl -sSL [url] | bash     - Install directly from web"
    echo ""
    echo "Options:"
    echo "  --uninstall  - Remove the script and related files"
    echo "  --help       - Show this help message"
}

# Main function
main() {
    case "$1" in
        --uninstall)
            check_root
            uninstall
            ;;
        --help|-h)
            usage
            ;;
        *)
            check_root
            install_dependencies
            install
            ;;
    esac
}

# Check if we're being piped into bash
if [[ -t 0 ]] && [[ $# -eq 0 ]]; then
    # Interactive mode
    main "$@"
else
    # Piped mode - install directly
    check_root
    install_dependencies
    secure_download "$SCRIPT_URL" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    echo -e "${GREEN}Direct installation completed!${NC}"
fi
