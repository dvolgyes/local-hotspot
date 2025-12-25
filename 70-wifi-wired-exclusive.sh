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

# Path to hotspot configuration file (REQUIRED for hotspot mode)
HOTSPOT_CONFIG="/etc/NetworkManager/dispatcher.d/hotspot.env"

# Load hotspot connection name from config file
if [ -f "$HOTSPOT_CONFIG" ]; then
    source "$HOTSPOT_CONFIG" 2>/dev/null
    HOTSPOT_CONNECTION_NAME="$HOTSPOT_CON_NAME"
else
    HOTSPOT_CONNECTION_NAME=""  # Will be detected in validation
fi

# Logging to syslog: 1 = enabled, 0 = disabled
LOG_TO_SYSLOG=1

# Debug logging: 1 = enabled (verbose), 0 = disabled
DEBUG_LOG=1

#-----------------------------------------------------------------------------
# Helper Functions
#-----------------------------------------------------------------------------

# Log message to syslog
log() {
    if [ "$LOG_TO_SYSLOG" = "1" ]; then
        logger -t "nm-dispatcher-hotspot" "$@"
    fi
}

# Debug log message (only if DEBUG_LOG=1)
debug_log() {
    if [ "$DEBUG_LOG" = "1" ]; then
        log "DEBUG: $@"
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
    local result
    result=$(nmcli -t -f DEVICE,TYPE,STATE device status | grep ':ethernet:connected')
    local ret=$?
    debug_log "is_ethernet_connected check: result='$result' ret=$ret"
    return $ret
}

# Check if the hotspot connection is currently active
is_hotspot_active() {
    local result
    result=$(nmcli -t -f NAME,STATE connection show --active | grep "^${HOTSPOT_CONNECTION_NAME}:")
    local ret=$?
    debug_log "is_hotspot_active check for '$HOTSPOT_CONNECTION_NAME': result='$result' ret=$ret"
    return $ret
}

# Start the hotspot using direct nmcli activation
start_hotspot() {
    log "Starting hotspot: $HOTSPOT_CONNECTION_NAME"

    # First check if the connection exists (we already verified this, but double-check)
    if ! nmcli -t -f NAME connection show | grep -q "^${HOTSPOT_CONNECTION_NAME}$"; then
        log "ERROR: Connection '$HOTSPOT_CONNECTION_NAME' does not exist"
        return 1
    fi

    # Try to activate the connection directly
    debug_log "Activating connection with nmcli..."
    if nmcli connection up "$HOTSPOT_CONNECTION_NAME" &>/dev/null; then
        log "Hotspot activated successfully"
        return 0
    else
        local nmcli_exit=$?
        log "ERROR: Failed to activate hotspot with nmcli (exit code: $nmcli_exit)"

        # Fallback: Try using the external script if nmcli fails
        if [ -f "$HOTSPOT_SCRIPT" ] && [ -f "$HOTSPOT_CONFIG" ]; then
            debug_log "Trying fallback: external hotspot script"
            local temp_log=$(mktemp)
            "$HOTSPOT_SCRIPT" -c "$HOTSPOT_CONFIG" start &>"$temp_log"
            local exit_code=$?

            if [ $exit_code -eq 0 ]; then
                log "Hotspot started successfully via script"
                rm -f "$temp_log"
                return 0
            else
                log "ERROR: External script also failed (exit code: $exit_code)"
                if [ -s "$temp_log" ]; then
                    log "Script output: $(cat "$temp_log" | tr '\n' ' ')"
                fi
                rm -f "$temp_log"
            fi
        fi

        return 1
    fi
}

# Stop the hotspot
stop_hotspot() {
    log "Stopping hotspot: $HOTSPOT_CONNECTION_NAME"

    if [ -f "$HOTSPOT_SCRIPT" ] && [ -f "$HOTSPOT_CONFIG" ]; then
        "$HOTSPOT_SCRIPT" -c "$HOTSPOT_CONFIG" stop &>/dev/null
    else
        # Fallback: use nmcli directly
        log "WARNING: Using nmcli fallback to stop hotspot"
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
    debug_log "Environment: DEVICE_IFACE=$DEVICE_IFACE IP4_ADDRESS_0=$IP4_ADDRESS_0 CONNECTION_ID=$CONNECTION_ID"
    debug_log "Using hotspot connection name: $HOTSPOT_CONNECTION_NAME"

    # Log all ethernet devices state
    if [ "$DEBUG_LOG" = "1" ]; then
        local eth_devices=$(nmcli -t -f DEVICE,TYPE,STATE device status | grep ':ethernet:')
        debug_log "Ethernet devices: $eth_devices"
    fi

    # Only act on connection up/down/connectivity-change events
    case "$2" in
        up|down|connectivity-change)
            # Continue processing
            debug_log "Processing event type: $2"
            ;;
        *)
            # Ignore other events (pre-up, pre-down, dhcp4-change, etc.)
            debug_log "Ignoring event type: $2"
            exit 0
            ;;
    esac

    # Check if ethernet is connected
    if is_ethernet_connected; then
        log "Ethernet is connected"
        debug_log "HOTSPOT_MODE=$HOTSPOT_MODE"

        # Check if hotspot mode is enabled
        if is_hotspot_mode_enabled; then
            log "Hotspot mode is enabled"

            # Validate configuration is present
            if [ -z "$HOTSPOT_CONNECTION_NAME" ]; then
                log "ERROR: Hotspot mode enabled but config file missing or invalid: $HOTSPOT_CONFIG"
                exit 1
            fi

            debug_log "Checking if hotspot connection '$HOTSPOT_CONNECTION_NAME' exists..."

            # Verify hotspot connection exists
            if ! nmcli -t -f NAME connection show | grep -q "^${HOTSPOT_CONNECTION_NAME}$"; then
                log "ERROR: Hotspot connection '$HOTSPOT_CONNECTION_NAME' does not exist!"
                debug_log "Available connections: $(nmcli -t -f NAME connection show)"
                exit 1
            fi
            debug_log "Hotspot connection '$HOTSPOT_CONNECTION_NAME' exists"

            # Check if hotspot is already active
            if ! is_hotspot_active; then
                log "Hotspot not active, starting..."
                start_hotspot
            else
                log "Hotspot already active, nothing to do"
            fi
        else
            log "Hotspot mode is disabled"
            debug_log "Hotspot mode value: $HOTSPOT_MODE"

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
