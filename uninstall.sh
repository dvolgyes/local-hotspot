#!/bin/bash

#=============================================================================
# Hotspot Dispatcher Uninstaller
#=============================================================================
# This script removes the WiFi hotspot system and NetworkManager dispatcher
# integration that was installed by install.sh
#
# What it does:
# - Reads the dispatcher config to find the hotspot connection name
# - Stops and deletes the hotspot connection from NetworkManager
# - Removes the dispatcher script from /etc/NetworkManager/dispatcher.d/
# - Removes the configuration file
# - Removes the hotspot management script from /usr/local/bin/
# - Restarts NetworkManager
#
# Usage: ./uninstall.sh
# (Script will use sudo where needed for system file operations)
#=============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installed file paths
HOTSPOT_SCRIPT_TARGET="/usr/local/bin/create_hotspot.sh"
DISPATCHER_SCRIPT_TARGET="/etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh"
CONFIG_FILE_TARGET="/etc/NetworkManager/dispatcher.d/hotspot.env"

# Connection name (will be read from config or dispatcher script)
HOTSPOT_CONNECTION_NAME=""

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

# Find the connection name from config file or dispatcher script
find_connection_name() {
    local HOTSPOT_CON_NAME=""

    # Try to read from config file first
    if [ -f "$CONFIG_FILE_TARGET" ]; then
        # shellcheck disable=SC1090
        source <(grep '^HOTSPOT_CON_NAME=' "$CONFIG_FILE_TARGET" 2>/dev/null || true)
        if [ -n "${HOTSPOT_CON_NAME:-}" ]; then
            HOTSPOT_CONNECTION_NAME=$(echo "$HOTSPOT_CON_NAME" | xargs)
            print_info "Found connection name from config: $HOTSPOT_CONNECTION_NAME"
            return 0
        fi
    fi

    # Try to read from dispatcher script
    if [ -f "$DISPATCHER_SCRIPT_TARGET" ]; then
        HOTSPOT_CONNECTION_NAME=$(grep '^HOTSPOT_CONNECTION_NAME=' "$DISPATCHER_SCRIPT_TARGET" 2>/dev/null | cut -d= -f2 | tr -d '"' | xargs || true)
        if [ -n "${HOTSPOT_CONNECTION_NAME:-}" ]; then
            print_info "Found connection name from dispatcher: $HOTSPOT_CONNECTION_NAME"
            return 0
        fi
    fi

    print_warning "Could not find connection name from installed files"
    return 1
}

# Check if hotspot connection exists
connection_exists() {
    local con_name="$1"
    nmcli -t -f NAME connection show 2>/dev/null | grep -q "^${con_name}$"
    return $?
}

# Show what will be removed
show_removal_summary() {
    print_header "Uninstallation Summary"

    echo "The following will be removed:"
    echo

    # Check for hotspot connection
    if [ -n "$HOTSPOT_CONNECTION_NAME" ]; then
        if connection_exists "$HOTSPOT_CONNECTION_NAME"; then
            echo "  NetworkManager Connection:"
            echo "    - $HOTSPOT_CONNECTION_NAME (will be stopped and deleted)"
            echo
        else
            echo "  NetworkManager Connection:"
            echo "    - $HOTSPOT_CONNECTION_NAME (not found, skipping)"
            echo
        fi
    else
        echo "  NetworkManager Connection:"
        echo "    - Unknown (could not determine connection name)"
        echo
    fi

    # Check for installed files
    echo "  Installed Files:"
    local files_found=0

    if [ -f "$HOTSPOT_SCRIPT_TARGET" ]; then
        echo "    - $HOTSPOT_SCRIPT_TARGET"
        files_found=$((files_found + 1))
    fi

    if [ -f "$DISPATCHER_SCRIPT_TARGET" ]; then
        echo "    - $DISPATCHER_SCRIPT_TARGET"
        files_found=$((files_found + 1))
    fi

    if [ -f "$CONFIG_FILE_TARGET" ]; then
        echo "    - $CONFIG_FILE_TARGET"
        files_found=$((files_found + 1))
    fi

    if [ $files_found -eq 0 ]; then
        echo "    (none found)"
    fi

    echo
    echo "Actions:"
    echo "  - Stop and delete hotspot connection (if active)"
    echo "  - Remove dispatcher script"
    echo "  - Remove configuration file"
    echo "  - Remove hotspot management script"
    echo "  - Restart NetworkManager service"
    echo
}

# Confirm uninstallation
confirm_uninstallation() {
    local CONFIRM
    echo -n "Proceed with uninstallation? (y/n): "
    read -r CONFIRM

    case "${CONFIRM,,}" in
        y|yes)
            return 0
            ;;
        *)
            print_warning "Uninstallation cancelled by user"
            exit 0
            ;;
    esac
}

# Perform uninstallation
perform_uninstallation() {
    print_header "Uninstalling Hotspot System"

    local something_removed=false

    # Remove NetworkManager connection
    if [ -n "$HOTSPOT_CONNECTION_NAME" ]; then
        if connection_exists "$HOTSPOT_CONNECTION_NAME"; then
            echo "Removing NetworkManager connection: $HOTSPOT_CONNECTION_NAME"

            # Stop if active
            if nmcli -t -f NAME connection show --active 2>/dev/null | grep -q "^${HOTSPOT_CONNECTION_NAME}$"; then
                echo "  Stopping active connection..."
                nmcli connection down "$HOTSPOT_CONNECTION_NAME" 2>/dev/null || true
            fi

            # Delete connection
            echo "  Deleting connection..."
            nmcli connection delete "$HOTSPOT_CONNECTION_NAME" 2>/dev/null || true
            print_success "Removed connection: $HOTSPOT_CONNECTION_NAME"
            something_removed=true
        else
            print_info "Connection not found: $HOTSPOT_CONNECTION_NAME (skipping)"
        fi
    else
        print_warning "Could not determine connection name (skipping connection removal)"
    fi

    # Remove hotspot script
    if [ -f "$HOTSPOT_SCRIPT_TARGET" ]; then
        echo "Removing hotspot management script..."
        sudo rm -f "$HOTSPOT_SCRIPT_TARGET"
        print_success "Removed $HOTSPOT_SCRIPT_TARGET"
        something_removed=true
    else
        print_info "Hotspot script not found (skipping)"
    fi

    # Remove dispatcher script
    if [ -f "$DISPATCHER_SCRIPT_TARGET" ]; then
        echo "Removing dispatcher script..."
        sudo rm -f "$DISPATCHER_SCRIPT_TARGET"
        print_success "Removed $DISPATCHER_SCRIPT_TARGET"
        something_removed=true
    else
        print_info "Dispatcher script not found (skipping)"
    fi

    # Remove config file
    if [ -f "$CONFIG_FILE_TARGET" ]; then
        echo "Removing configuration file..."
        sudo rm -f "$CONFIG_FILE_TARGET"
        print_success "Removed $CONFIG_FILE_TARGET"
        something_removed=true
    else
        print_info "Config file not found (skipping)"
    fi

    # Restart NetworkManager
    if [ "$something_removed" = true ]; then
        echo "Restarting NetworkManager..."
        sudo systemctl restart NetworkManager
        print_success "NetworkManager restarted"
    fi

    echo
}

# Show post-uninstallation info
show_post_uninstall() {
    print_header "Uninstallation Complete"

    print_success "Hotspot system has been removed from your system"
    echo

    echo "What was removed:"
    if [ -n "$HOTSPOT_CONNECTION_NAME" ]; then
        echo "  ✓ NetworkManager hotspot connection: $HOTSPOT_CONNECTION_NAME"
    fi
    echo "  ✓ Hotspot management script"
    echo "  ✓ NetworkManager dispatcher script"
    echo "  ✓ Configuration file"
    echo

    echo "Your WiFi will now behave normally:"
    echo "  • WiFi stays on when ethernet is connected"
    echo "  • No automatic hotspot creation"
    echo

    print_info "To reinstall, run: ./install.sh"
}

#-----------------------------------------------------------------------------
# Main Uninstallation Flow
#-----------------------------------------------------------------------------

main() {
    clear
    print_header "WiFi Hotspot Dispatcher Uninstallation"
    echo

    # Find connection name
    find_connection_name || true

    # Show what will be removed
    show_removal_summary

    # Confirm
    confirm_uninstallation

    # Uninstall
    perform_uninstallation

    # Post-uninstall info
    show_post_uninstall
}

# Run uninstaller
main "$@"
