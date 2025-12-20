#!/bin/bash

#=============================================================================
# Hotspot Dispatcher Installer
#=============================================================================
# This script installs the WiFi hotspot system with NetworkManager dispatcher
# integration for automatic hotspot management.
#
# What it does:
# - Asks for your hotspot configuration (SSID, password, connection name)
# - Installs the hotspot management script to /usr/local/bin/
# - Installs the NetworkManager dispatcher script for automation
# - Creates configuration file with your settings
# - Restarts NetworkManager to activate the dispatcher
#=============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target paths
HOTSPOT_SCRIPT_TARGET="/usr/local/bin/create_hotspot.sh"
DISPATCHER_SCRIPT_TARGET="/etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh"
CONFIG_FILE_TARGET="/etc/NetworkManager/dispatcher.d/hotspot.env"

# Source files
HOTSPOT_SCRIPT_SOURCE="${SCRIPT_DIR}/create_hotspot.sh"
DISPATCHER_SCRIPT_SOURCE="${SCRIPT_DIR}/70-wifi-wired-exclusive.sh"

#-----------------------------------------------------------------------------
# Helper Functions
#-----------------------------------------------------------------------------

print_header() {
    echo -e "${BLUE}===============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if running as root (we need sudo for installation)
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This installer must be run with sudo"
        echo "Usage: sudo ./install.sh"
        exit 1
    fi
}

# Check if source files exist
check_source_files() {
    local missing=()

    if [ ! -f "$HOTSPOT_SCRIPT_SOURCE" ]; then
        missing+=("create_hotspot.sh")
    fi

    if [ ! -f "$DISPATCHER_SCRIPT_SOURCE" ]; then
        missing+=("70-wifi-wired-exclusive.sh")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required source files: ${missing[*]}"
        echo "Please run this installer from the hotspot.sh directory"
        exit 1
    fi
}

# Read password securely
read_password() {
    local password1
    local password2

    while true; do
        read -s -p "Enter WiFi password (min 8 characters): " password1 </dev/tty
        echo

        if [ ${#password1} -lt 8 ]; then
            print_error "Password must be at least 8 characters long"
            continue
        fi

        echo
        read -s -p "Confirm password: " password2 </dev/tty
        echo

        if [ "$password1" != "$password2" ]; then
            print_error "Passwords do not match. Please try again."
            continue
        fi

        echo "$password1"
        return 0
    done
}

# Ask for configuration
ask_configuration() {
    print_header "Hotspot Configuration"

    echo "This installer will set up automatic WiFi hotspot management."
    echo "Please provide your desired hotspot configuration:"
    echo

    # Connection name (trim whitespace)
    read -p "Connection name [auto-hotspot]: " CON_NAME </dev/tty
    CON_NAME=$(echo "${CON_NAME:-auto-hotspot}" | xargs)

    # SSID (trim whitespace)
    read -p "WiFi SSID (network name) [AutoHotspot]: " SSID </dev/tty
    SSID=$(echo "${SSID:-AutoHotspot}" | xargs)

    # Password (secure input, trim whitespace)
    PASSWORD=$(read_password | xargs)

    # Hotspot mode
    echo
    read -p "Enable automatic hotspot mode? (y/n) [y]: " ENABLE_HOTSPOT </dev/tty
    ENABLE_HOTSPOT="${ENABLE_HOTSPOT:-y}"

    case "${ENABLE_HOTSPOT,,}" in
        y|yes)
            HOTSPOT_MODE=1
            ;;
        n|no)
            HOTSPOT_MODE=0
            ;;
        *)
            print_warning "Invalid input, defaulting to enabled"
            HOTSPOT_MODE=1
            ;;
    esac

    echo
}

# Show summary
show_summary() {
    print_header "Installation Summary"

    echo "Configuration:"
    echo "  Connection name:  $CON_NAME"
    echo "  WiFi SSID:        $SSID"
    echo "  Password:         $(echo "$PASSWORD" | sed 's/./*/g')"
    echo "  Hotspot mode:     $([ "$HOTSPOT_MODE" -eq 1 ] && echo "Enabled" || echo "Disabled")"
    echo

    echo "Files to be installed:"
    echo "  $HOTSPOT_SCRIPT_SOURCE"
    echo "    → $HOTSPOT_SCRIPT_TARGET"
    echo
    echo "  $DISPATCHER_SCRIPT_SOURCE"
    echo "    → $DISPATCHER_SCRIPT_TARGET"
    echo
    echo "  Config file will be created:"
    echo "    → $CONFIG_FILE_TARGET"
    echo

    echo "Actions:"
    echo "  - Copy hotspot management script to /usr/local/bin/"
    echo "  - Copy NetworkManager dispatcher script to /etc/NetworkManager/dispatcher.d/"
    echo "  - Create configuration file with your settings"
    echo "  - Set executable permissions on scripts"
    echo "  - Restart NetworkManager service"
    echo

    if [ "$HOTSPOT_MODE" -eq 1 ]; then
        print_info "When ethernet is connected, hotspot will start automatically"
        print_info "When ethernet is disconnected, hotspot will stop and WiFi will resume normal operation"
    else
        print_info "Hotspot mode is disabled - WiFi will be turned off when ethernet is connected"
    fi
    echo
}

# Confirm installation
confirm_installation() {
    local CONFIRM
    read -p "Proceed with installation? (y/n): " CONFIRM </dev/tty

    case "${CONFIRM,,}" in
        y|yes)
            return 0
            ;;
        *)
            print_warning "Installation cancelled by user"
            exit 0
            ;;
    esac
}

# Perform installation
perform_installation() {
    print_header "Installing Hotspot System"

    # Create config file content
    local config_content
    config_content=$(cat <<EOF
# Hotspot Configuration for NetworkManager Dispatcher
# Generated by install.sh on $(date)

HOTSPOT_CON_NAME=$CON_NAME
HOTSPOT_SSID=$SSID
HOTSPOT_PASSWORD=$PASSWORD
EOF
)

    # Install hotspot script
    echo "Installing hotspot management script..."
    cp "$HOTSPOT_SCRIPT_SOURCE" "$HOTSPOT_SCRIPT_TARGET"
    chmod +x "$HOTSPOT_SCRIPT_TARGET"
    print_success "Installed $HOTSPOT_SCRIPT_TARGET"

    # Install dispatcher script with updated configuration
    echo "Installing NetworkManager dispatcher script..."

    # Read dispatcher script and update HOTSPOT_MODE and HOTSPOT_CONNECTION_NAME
    sed -e "s/^HOTSPOT_MODE=.*/HOTSPOT_MODE=$HOTSPOT_MODE/" \
        -e "s/^HOTSPOT_CONNECTION_NAME=.*/HOTSPOT_CONNECTION_NAME=\"$CON_NAME\"/" \
        "$DISPATCHER_SCRIPT_SOURCE" > "$DISPATCHER_SCRIPT_TARGET"

    chmod +x "$DISPATCHER_SCRIPT_TARGET"
    print_success "Installed $DISPATCHER_SCRIPT_TARGET"

    # Create config file
    echo "Creating configuration file..."
    echo "$config_content" > "$CONFIG_FILE_TARGET"
    chmod 600 "$CONFIG_FILE_TARGET"  # Secure permissions (contains password)
    print_success "Created $CONFIG_FILE_TARGET"

    # Restart NetworkManager
    echo "Restarting NetworkManager..."
    systemctl restart NetworkManager
    print_success "NetworkManager restarted"

    echo
}

# Show post-installation info
show_post_install() {
    print_header "Installation Complete"

    print_success "Hotspot system installed successfully!"
    echo

    echo "What happens now:"
    if [ "$HOTSPOT_MODE" -eq 1 ]; then
        echo "  • When you plug in an ethernet cable, the WiFi hotspot will start automatically"
        echo "  • Devices can connect to SSID: $SSID"
        echo "  • When you unplug ethernet, the hotspot stops and WiFi resumes normal operation"
    else
        echo "  • When ethernet is connected, WiFi will be disabled"
        echo "  • When ethernet is disconnected, WiFi will be enabled"
    fi
    echo

    echo "Manual control:"
    echo "  Start hotspot:  $HOTSPOT_SCRIPT_TARGET start"
    echo "  Stop hotspot:   $HOTSPOT_SCRIPT_TARGET stop"
    echo "  Check status:   $HOTSPOT_SCRIPT_TARGET status"
    echo

    echo "Configuration files:"
    echo "  Hotspot script:   $HOTSPOT_SCRIPT_TARGET"
    echo "  Dispatcher:       $DISPATCHER_SCRIPT_TARGET"
    echo "  Config file:      $CONFIG_FILE_TARGET"
    echo

    echo "To view dispatcher logs:"
    echo "  sudo journalctl -t nm-dispatcher-hotspot -f"
    echo

    if [ "$HOTSPOT_MODE" -eq 1 ]; then
        print_info "Tip: Connect an ethernet cable to test automatic hotspot activation!"
    fi
    echo

    print_success "Setup complete. Enjoy your automatic hotspot!"
}

#-----------------------------------------------------------------------------
# Main Installation Flow
#-----------------------------------------------------------------------------

main() {
    clear
    print_header "WiFi Hotspot Dispatcher Installation"
    echo

    # Checks
    check_root
    check_source_files

    # Configuration
    ask_configuration

    # Summary and confirmation
    show_summary
    confirm_installation

    # Installation
    perform_installation

    # Post-install info
    show_post_install
}

# Run installer
main "$@"
