#!/bin/bash
export LC_ALL=C

#=============================================================================
# NetworkManager Dispatcher Script - Automatic Hotspot Management
#=============================================================================
# This script automatically manages WiFi/Ethernet switching and optionally
# creates a WiFi hotspot when ethernet is connected.
#
# Behavior:
# - Ethernet connected + HOTSPOT_MODE enabled  → Create/activate hotspot
# - Ethernet connected + HOTSPOT_MODE disabled → Disable WiFi radio
# - Ethernet disconnected                      → Stop hotspot (if active), enable WiFi
#
# Installation: Copy to /etc/NetworkManager/dispatcher.d/
# Permissions: chmod +x /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
#=============================================================================

#-----------------------------------------------------------------------------
# Configuration
#-----------------------------------------------------------------------------

# Hotspot mode: 1/yes/true/on/enabled = enable, 0/no/false/off/disabled = disable
HOTSPOT_MODE=1

# Path to hotspot management script
HOTSPOT_SCRIPT="/usr/local/bin/create_hotspot.sh"

# Path to hotspot configuration file
HOTSPOT_CONFIG="/etc/NetworkManager/dispatcher.d/hotspot.env"

# Hotspot connection name (must match HOTSPOT_CON_NAME in config file)
HOTSPOT_CONNECTION_NAME="auto-hotspot"

# Logging to syslog: 1 = enabled, 0 = disabled
LOG_TO_SYSLOG=1

#-----------------------------------------------------------------------------
# Helper Functions
#-----------------------------------------------------------------------------

# Log message to syslog
log() {
    if [ "$LOG_TO_SYSLOG" = "1" ]; then
        logger -t "nm-dispatcher-hotspot" "$@"
    fi
}

# Check if hotspot mode is enabled
is_hotspot_mode_enabled() {
    case "${HOTSPOT_MODE,,}" in  # Convert to lowercase
        1|yes|true|on|enabled)
            return 0  # Enabled
            ;;
        *)
            return 1  # Disabled
            ;;
    esac
}

# Check if ANY ethernet interface is connected
is_ethernet_connected() {
    nmcli -t -f DEVICE,TYPE,STATE device status | \
        grep ':ethernet:connected' &>/dev/null
    return $?
}

# Check if the hotspot connection is currently active
is_hotspot_active() {
    nmcli -t -f NAME,STATE connection show --active | \
        grep "^${HOTSPOT_CONNECTION_NAME}:activated" &>/dev/null
    return $?
}

# Start the hotspot using the external script
start_hotspot() {
    log "Starting hotspot: $HOTSPOT_CONNECTION_NAME"

    if [ ! -f "$HOTSPOT_SCRIPT" ]; then
        log "ERROR: Hotspot script not found: $HOTSPOT_SCRIPT"
        return 1
    fi

    if [ -f "$HOTSPOT_CONFIG" ]; then
        "$HOTSPOT_SCRIPT" -c "$HOTSPOT_CONFIG" start &>/dev/null
    else
        log "WARNING: Config file not found: $HOTSPOT_CONFIG (using defaults)"
        "$HOTSPOT_SCRIPT" start &>/dev/null
    fi

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log "Hotspot started successfully"
    else
        log "ERROR: Failed to start hotspot (exit code: $exit_code)"
    fi
    return $exit_code
}

# Stop the hotspot
stop_hotspot() {
    log "Stopping hotspot: $HOTSPOT_CONNECTION_NAME"

    if [ -f "$HOTSPOT_SCRIPT" ]; then
        if [ -f "$HOTSPOT_CONFIG" ]; then
            "$HOTSPOT_SCRIPT" -c "$HOTSPOT_CONFIG" stop &>/dev/null
        else
            "$HOTSPOT_SCRIPT" stop &>/dev/null
        fi
    else
        # Fallback: use nmcli directly
        log "WARNING: Hotspot script not found, using nmcli fallback"
        nmcli connection down "$HOTSPOT_CONNECTION_NAME" &>/dev/null || true
    fi

    log "Hotspot stopped"
}

# Enable WiFi radio for normal client connections
enable_normal_wifi() {
    log "Enabling WiFi for normal connections"
    nmcli radio wifi on
}

# Disable WiFi radio completely (original behavior when hotspot mode is off)
disable_wifi_radio() {
    log "Disabling WiFi radio (hotspot mode is off)"
    nmcli radio wifi off
}

#-----------------------------------------------------------------------------
# Main Logic
#-----------------------------------------------------------------------------

main() {
    # Log the event
    log "Event: interface=$1 action=$2"

    # Only act on connection up/down/connectivity-change events
    case "$2" in
        up|down|connectivity-change)
            # Continue processing
            ;;
        *)
            # Ignore other events (pre-up, pre-down, dhcp4-change, etc.)
            exit 0
            ;;
    esac

    # Check if ethernet is connected
    if is_ethernet_connected; then
        log "Ethernet is connected"

        # Check if hotspot mode is enabled
        if is_hotspot_mode_enabled; then
            log "Hotspot mode is enabled"

            # Check if hotspot is already active
            if ! is_hotspot_active; then
                log "Hotspot not active, starting..."
                start_hotspot
            else
                log "Hotspot already active, nothing to do"
            fi
        else
            log "Hotspot mode is disabled"

            # Stop hotspot if it's somehow active
            if is_hotspot_active; then
                log "Hotspot is active but mode is disabled, stopping..."
                stop_hotspot
            fi

            # Use original behavior: disable WiFi radio
            disable_wifi_radio
        fi
    else
        log "Ethernet is not connected"

        # Check if hotspot was running and stop it
        if is_hotspot_active; then
            log "Hotspot is active, stopping..."
            stop_hotspot
        fi

        # Enable normal WiFi for client connections
        enable_normal_wifi
    fi
}

#-----------------------------------------------------------------------------
# Script Invocation
#-----------------------------------------------------------------------------

# Run main logic with dispatcher arguments
main "$@"
