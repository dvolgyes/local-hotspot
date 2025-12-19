#!/bin/bash

#=============================================================================
# WiFi Hotspot Script - Share ethernet internet via WiFi access point
#=============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

#-----------------------------------------------------------------------------
# Argument Parsing (extract -c/--config before command)
#-----------------------------------------------------------------------------

CUSTOM_CONFIG_FILE=""
COMMAND_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CUSTOM_CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            COMMAND_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters for command handling
set -- "${COMMAND_ARGS[@]}"

#-----------------------------------------------------------------------------
# Configuration Loading (Priority: custom config > .env file > environment vars > defaults)
#-----------------------------------------------------------------------------

# Get script directory to find .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Load custom config file if specified (highest priority)
if [ -n "$CUSTOM_CONFIG_FILE" ]; then
    if [ -f "$CUSTOM_CONFIG_FILE" ]; then
        echo "Loading configuration from: $CUSTOM_CONFIG_FILE"
        # Export variables from custom config file (skip comments and empty lines)
        set -a
        # shellcheck disable=SC1090
        source <(grep -v '^#' "$CUSTOM_CONFIG_FILE" | grep -v '^[[:space:]]*$' | sed 's/\r$//')
        set +a
    else
        echo "ERROR: Config file not found: $CUSTOM_CONFIG_FILE" >&2
        exit 1
    fi
# Otherwise, load .env file if it exists
elif [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from: $ENV_FILE"
    # Export variables from .env file (skip comments and empty lines)
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$ENV_FILE" | grep -v '^[[:space:]]*$' | sed 's/\r$//')
    set +a
fi

# Configuration Variables (with priority: .env > environment > defaults)
HOTSPOT_CON_NAME="${HOTSPOT_CON_NAME:-home-hotspot}"
HOTSPOT_SSID="${HOTSPOT_SSID:-home-hotspot}"
HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD:-examplecomplicatedpassword}"  # Minimum 8 characters required
WIFI_INTERFACE="${WIFI_INTERFACE:-}"   # Auto-detect if empty
WIRED_INTERFACE="${WIRED_INTERFACE:-}"  # Auto-detect if empty

#-----------------------------------------------------------------------------
# Interface Auto-Detection Functions
#-----------------------------------------------------------------------------

# Auto-detect wireless interface
detect_wifi_interface() {
    local wifi_iface
    wifi_iface=$(nmcli -t -f DEVICE,TYPE device status | grep ':wifi$' | grep -v 'p2p-dev' | cut -d: -f1 | head -1)
    if [ -z "$wifi_iface" ]; then
        echo "ERROR: No WiFi interface found" >&2
        return 1
    fi
    echo "$wifi_iface"
}

# Auto-detect wired ethernet interface (preferably connected)
detect_wired_interface() {
    local wired_iface
    # Try to find a connected ethernet interface first
    wired_iface=$(nmcli -t -f DEVICE,TYPE,STATE device status | grep 'ethernet:connected' | cut -d: -f1 | head -1)

    # If no connected interface, just find any ethernet interface
    if [ -z "$wired_iface" ]; then
        wired_iface=$(nmcli -t -f DEVICE,TYPE device status | grep ':ethernet$' | cut -d: -f1 | head -1)
    fi

    if [ -z "$wired_iface" ]; then
        echo "WARNING: No ethernet interface found" >&2
        echo "Internet sharing may not work without wired connection" >&2
    fi
    echo "$wired_iface"
}

#-----------------------------------------------------------------------------
# Connection Management Functions
#-----------------------------------------------------------------------------

# Check if connection already exists
connection_exists() {
    local con_name="$1"
    nmcli -t -f NAME connection show | grep -q "^${con_name}$"
    return $?
}

# Get connection state (returns "activated" if active, empty if not)
connection_state() {
    local con_name="$1"
    nmcli -t -f NAME,STATE connection show --active | grep "^${con_name}:" | cut -d: -f2
}

#-----------------------------------------------------------------------------
# Requirements Check
#-----------------------------------------------------------------------------

check_requirements() {
    local missing=()

    # Check for dnsmasq (required for ipv4.method shared)
    if ! command -v dnsmasq &> /dev/null; then
        missing+=("dnsmasq")
    fi

    # Check for nmcli
    if ! command -v nmcli &> /dev/null; then
        missing+=("network-manager")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Missing required packages: ${missing[*]}" >&2
        echo "Install with: sudo apt install ${missing[*]}" >&2
        return 1
    fi

    return 0
}

#-----------------------------------------------------------------------------
# Hotspot Creation
#-----------------------------------------------------------------------------

create_hotspot() {
    echo "Creating hotspot on interface: $WIFI_INTERFACE"
    echo "SSID: $HOTSPOT_SSID"

    # Create connection with all settings in one command (more reliable)
    nmcli con add type wifi \
        ifname "$WIFI_INTERFACE" \
        con-name "$HOTSPOT_CON_NAME" \
        autoconnect yes \
        ssid "$HOTSPOT_SSID" \
        802-11-wireless.mode ap \
        802-11-wireless.band bg \
        ipv4.method shared \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$HOTSPOT_PASSWORD"

    # Add PMF for better security (optional but recommended)
    nmcli con modify "$HOTSPOT_CON_NAME" 802-11-wireless-security.pmf 1

    echo "Hotspot connection created successfully"
}

activate_hotspot() {
    local con_name="$1"
    echo "Activating hotspot '$con_name'..."
    nmcli con up "$con_name"
}

#-----------------------------------------------------------------------------
# Verification Functions
#-----------------------------------------------------------------------------

verify_ip_forwarding() {
    local ip_forward
    ip_forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")

    if [ "$ip_forward" != "1" ]; then
        echo "WARNING: IP forwarding is disabled"
        echo "Internet sharing may not work. To enable:"
        echo "  sudo sysctl -w net.ipv4.ip_forward=1"
        echo "To make permanent, add to /etc/sysctl.conf:"
        echo "  net.ipv4.ip_forward=1"
        return 1
    else
        echo "IP forwarding is enabled ✓"
        return 0
    fi
}

verify_hotspot() {
    local con_name="$1"
    local wifi_iface="$2"

    echo ""
    echo "=== Verifying Hotspot Configuration ==="

    # Check if connection is active
    if ! nmcli -t -f NAME connection show --active | grep -q "^${con_name}$"; then
        echo "ERROR: Hotspot connection is not active" >&2
        return 1
    fi
    echo "Connection is active ✓"

    # Check if interface has IP in shared range (10.42.0.0/24 default for NM)
    local ip_addr
    ip_addr=$(ip -4 addr show dev "$wifi_iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "")

    if [ -z "$ip_addr" ]; then
        echo "ERROR: WiFi interface has no IP address" >&2
        return 1
    fi
    echo "WiFi interface IP: $ip_addr ✓"

    # Check if dnsmasq is running for this connection
    if pgrep -f "dnsmasq.*$wifi_iface" > /dev/null 2>&1; then
        echo "DHCP server (dnsmasq) is running ✓"
    else
        echo "WARNING: DHCP server (dnsmasq) may not be running" >&2
        echo "Check with: ps aux | grep dnsmasq"
    fi

    # Check IP forwarding
    verify_ip_forwarding || true

    echo "=== Verification Complete ==="
    return 0
}

#-----------------------------------------------------------------------------
# Management Functions
#-----------------------------------------------------------------------------

stop_hotspot() {
    local con_name="$1"

    if ! connection_exists "$con_name"; then
        echo "ERROR: Connection '$con_name' does not exist" >&2
        return 1
    fi

    echo "Stopping hotspot '$con_name'..."
    nmcli con down "$con_name"
    echo "Hotspot stopped"
}

delete_hotspot() {
    local con_name="$1"

    if ! connection_exists "$con_name"; then
        echo "ERROR: Connection '$con_name' does not exist" >&2
        return 1
    fi

    # Stop if active
    nmcli con down "$con_name" 2>/dev/null || true

    echo "Deleting hotspot '$con_name'..."
    nmcli con delete "$con_name"
    echo "Hotspot deleted"
}

show_status() {
    local con_name="$1"

    echo "=== Hotspot Status ==="
    echo "Connection name: $con_name"

    if ! connection_exists "$con_name"; then
        echo "Status: NOT CONFIGURED"
        echo ""
        echo "Run '$0 start' to create the hotspot"
        return 0
    fi

    # Get connection details
    STATE=$(connection_state "$con_name")
    if [ "$STATE" = "activated" ]; then
        echo "Status: ACTIVE"

        # Get interface and IP
        local iface
        iface=$(nmcli -t -f NAME,DEVICE connection show --active | grep "^${con_name}:" | cut -d: -f2)
        if [ -n "$iface" ]; then
            echo "Interface: $iface"
            local ip_addr
            ip_addr=$(ip -4 addr show dev "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+' || echo "N/A")
            echo "IP Address: $ip_addr"
        fi

        # Show SSID
        local ssid
        ssid=$(nmcli -t -f 802-11-wireless.ssid connection show "$con_name" | cut -d: -f2)
        echo "SSID: $ssid"

        echo ""
        echo "Clients can connect to SSID: $ssid"
    else
        echo "Status: CONFIGURED but INACTIVE"
        echo ""
        echo "Run '$0 start' to activate the hotspot"
    fi
}

print_usage() {
    cat << EOF
Usage: $0 [-c|--config FILE] [COMMAND]

Commands:
    start       Create and start the hotspot (default)
    stop        Stop the hotspot
    delete      Delete the hotspot connection
    status      Show hotspot status
    help        Show this help message

Options:
    -c, --config FILE    Use custom config file instead of .env

Configuration (priority: -c config > .env file > environment vars > defaults):
    HOTSPOT_CON_NAME    Connection name (default: $HOTSPOT_CON_NAME)
    HOTSPOT_SSID        WiFi SSID (default: $HOTSPOT_SSID)
    HOTSPOT_PASSWORD    WiFi password (default: [hidden])
    WIFI_INTERFACE      WiFi interface (auto-detect if empty)
    WIRED_INTERFACE     Ethernet interface (auto-detect if empty)

Configuration methods:
    1. Use custom config file: -c/--config option
    2. Create a .env file (copy from .env.example)
    3. Export environment variables before running
    4. Edit defaults at top of script

Examples:
    $0              # Start hotspot (default action)
    $0 start        # Start hotspot
    $0 status       # Show status
    $0 stop         # Stop hotspot
    $0 delete       # Delete hotspot connection

    # Using custom config file
    $0 -c hotspot.env start
    $0 --config /path/to/config.env start

    # Using environment variables
    HOTSPOT_SSID=MyNetwork HOTSPOT_PASSWORD=MyPass123 $0 start

Note: Usually works without sudo on modern systems. If you get permission errors,
      your user may need to be added to the 'netdev' group or similar, or prefix
      individual commands with sudo (sudo will remember credentials for ~15 min).
EOF
}

#-----------------------------------------------------------------------------
# Main Function
#-----------------------------------------------------------------------------

main() {
    local command="${1:-start}"

    # Handle help first
    if [ "$command" = "help" ] || [ "$command" = "-h" ] || [ "$command" = "--help" ]; then
        print_usage
        exit 0
    fi

    # Handle status command (doesn't need interface detection)
    if [ "$command" = "status" ]; then
        show_status "$HOTSPOT_CON_NAME"
        exit 0
    fi

    # Handle stop command
    if [ "$command" = "stop" ]; then
        stop_hotspot "$HOTSPOT_CON_NAME"
        exit 0
    fi

    # Handle delete command
    if [ "$command" = "delete" ]; then
        delete_hotspot "$HOTSPOT_CON_NAME"
        exit 0
    fi

    # Handle start command (default)
    if [ "$command" != "start" ]; then
        echo "ERROR: Unknown command: $command" >&2
        echo ""
        print_usage
        exit 1
    fi

    # START command logic below
    echo "=== WiFi Hotspot Setup ==="

    # Check requirements first
    check_requirements || exit 1

    # Auto-detect interfaces if not set
    if [ -z "$WIFI_INTERFACE" ]; then
        WIFI_INTERFACE=$(detect_wifi_interface) || exit 1
        echo "Auto-detected WiFi interface: $WIFI_INTERFACE"
    else
        echo "Using configured WiFi interface: $WIFI_INTERFACE"
    fi

    if [ -z "$WIRED_INTERFACE" ]; then
        WIRED_INTERFACE=$(detect_wired_interface)
        if [ -n "$WIRED_INTERFACE" ]; then
            echo "Auto-detected wired interface: $WIRED_INTERFACE"
        fi
    else
        echo "Using configured wired interface: $WIRED_INTERFACE"
    fi

    # Check if connection exists
    if connection_exists "$HOTSPOT_CON_NAME"; then
        echo "Connection '$HOTSPOT_CON_NAME' already exists"

        # Check if active
        STATE=$(connection_state "$HOTSPOT_CON_NAME")
        if [ "$STATE" = "activated" ]; then
            echo "Hotspot is already active"
            verify_hotspot "$HOTSPOT_CON_NAME" "$WIFI_INTERFACE" || true
            echo ""
            echo "You can connect to SSID: $HOTSPOT_SSID"
            exit 0
        else
            echo "Hotspot exists but is not active"
            activate_hotspot "$HOTSPOT_CON_NAME"
            echo "Hotspot activated successfully"
            verify_hotspot "$HOTSPOT_CON_NAME" "$WIFI_INTERFACE" || true
            echo ""
            echo "You can connect to SSID: $HOTSPOT_SSID"
            exit 0
        fi
    fi

    # Create new connection
    echo "Creating new hotspot connection..."
    create_hotspot

    # Activate the hotspot
    activate_hotspot "$HOTSPOT_CON_NAME"

    # Verify the hotspot is working
    verify_hotspot "$HOTSPOT_CON_NAME" "$WIFI_INTERFACE" || true

    echo ""
    echo "=== Hotspot Setup Complete ==="
    echo "SSID: $HOTSPOT_SSID"
    echo "Password: $HOTSPOT_PASSWORD"
    echo "WiFi Interface: $WIFI_INTERFACE"
    echo ""
    echo "You can now connect devices to this hotspot"
    echo ""
    echo "If clients can't access the internet, check:"
    echo "  1. Ethernet cable is connected"
    echo "  2. IP forwarding is enabled (see warning above)"
    echo "  3. dnsmasq is installed: sudo apt install dnsmasq"
}

# Run main function
main "$@"
