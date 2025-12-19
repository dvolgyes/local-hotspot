# NetworkManager Dispatcher - Automatic Hotspot Installation Guide

This guide explains how to install and configure the NetworkManager dispatcher script for automatic WiFi/Ethernet management with optional hotspot creation.

## Overview

The dispatcher script automatically:
- **When ethernet connects** + hotspot mode enabled → Creates WiFi hotspot (shares ethernet internet)
- **When ethernet connects** + hotspot mode disabled → Disables WiFi radio (ethernet only)
- **When ethernet disconnects** → Stops hotspot (if running) and enables normal WiFi

## Prerequisites

1. **Hotspot script installed**:
   ```bash
   sudo cp create_hotspot.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/create_hotspot.sh
   ```

2. **dnsmasq installed** (required for hotspot DHCP):
   ```bash
   sudo apt install dnsmasq
   ```

## Installation Steps

### Step 1: Install Hotspot Configuration

Create the hotspot configuration file that the dispatcher will use:

```bash
sudo tee /etc/NetworkManager/dispatcher.d/hotspot.env > /dev/null << 'EOF'
# Hotspot configuration for NetworkManager Dispatcher
HOTSPOT_CON_NAME=auto-hotspot
HOTSPOT_SSID=AutoHotspot
HOTSPOT_PASSWORD=examplecomplicatedpassword
WIFI_INTERFACE=
WIRED_INTERFACE=
EOF
```

**Important**: Set secure permissions (file contains password):
```bash
sudo chmod 600 /etc/NetworkManager/dispatcher.d/hotspot.env
```

### Step 2: Install Dispatcher Script

Copy the dispatcher script to the NetworkManager dispatcher directory:

```bash
sudo cp 70-wifi-wired-exclusive.sh /etc/NetworkManager/dispatcher.d/
sudo chmod +x /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
```

### Step 3: Configure Hotspot Mode

Edit the dispatcher script to enable or disable hotspot mode:

```bash
sudo nano /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
```

Find the configuration section and set `HOTSPOT_MODE`:
```bash
# Hotspot mode: 1 = enable, 0 = disable
HOTSPOT_MODE=1
```

**Hotspot Mode Values**:
- `1`, `yes`, `true`, `on`, `enabled` → Hotspot mode **ON**
- `0`, `no`, `false`, `off`, `disabled` → Hotspot mode **OFF** (original WiFi-disabling behavior)

### Step 4: Verify Configuration

Check that the connection name matches between dispatcher and config:

```bash
# Check dispatcher script
grep HOTSPOT_CONNECTION_NAME /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh

# Check config file
grep HOTSPOT_CON_NAME /etc/NetworkManager/dispatcher.d/hotspot.env

# Both should show: auto-hotspot
```

## Testing

### Manual Testing

You can test the dispatcher script manually:

```bash
# Simulate ethernet up event
sudo /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh eth0 up

# Simulate ethernet down event
sudo /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh eth0 down
```

### Monitor Logs

Watch the dispatcher logs in real-time:

```bash
journalctl -f -t nm-dispatcher-hotspot
```

### Test Scenarios

**Scenario 1: Ethernet Connect with Hotspot Mode ON**
1. Start with WiFi only (ethernet unplugged)
2. Plug in ethernet cable
3. Expected: Hotspot "AutoHotspot" is created, WiFi stays on (AP mode)
4. Check: `nmcli connection show --active | grep auto-hotspot`
5. Connect a device to the hotspot and verify internet access

**Scenario 2: Ethernet Disconnect**
1. Start with ethernet connected and hotspot active
2. Unplug ethernet cable
3. Expected: Hotspot stops, WiFi enables for normal connections
4. Check: `nmcli radio wifi` should show "enabled"

**Scenario 3: Ethernet Connect with Hotspot Mode OFF**
1. Set `HOTSPOT_MODE=0` in dispatcher script
2. Plug in ethernet cable
3. Expected: WiFi radio is disabled
4. Check: `nmcli radio wifi` should show "disabled"

## Configuration

### Customizing the Hotspot

Edit `/etc/NetworkManager/dispatcher.d/hotspot.env`:

```bash
sudo nano /etc/NetworkManager/dispatcher.d/hotspot.env
```

Change these values as needed:
- `HOTSPOT_SSID` - WiFi network name visible to clients
- `HOTSPOT_PASSWORD` - WiFi password (minimum 8 characters)
- `HOTSPOT_CON_NAME` - Connection name (must match dispatcher script)

### Disabling Logging

If you don't want syslog logging, edit the dispatcher script:

```bash
sudo nano /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
```

Set:
```bash
LOG_TO_SYSLOG=0
```

## Troubleshooting

### Dispatcher Not Running

**Check NetworkManager service**:
```bash
systemctl status NetworkManager
```

**Check script permissions**:
```bash
ls -la /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
# Should be: -rwxr-xr-x (executable)
```

**Check script syntax**:
```bash
bash -n /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
```

### Hotspot Not Creating

**Check logs**:
```bash
journalctl -t nm-dispatcher-hotspot -n 50
```

**Verify hotspot script exists**:
```bash
ls -la /usr/local/bin/create_hotspot.sh
```

**Test hotspot script directly**:
```bash
/usr/local/bin/create_hotspot.sh -c /etc/NetworkManager/dispatcher.d/hotspot.env start
```

**Check config file exists**:
```bash
ls -la /etc/NetworkManager/dispatcher.d/hotspot.env
```

### WiFi Stays Disabled

**Manually enable WiFi**:
```bash
nmcli radio wifi on
```

**Check hotspot mode setting**:
```bash
grep HOTSPOT_MODE /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
```

**Check if hotspot is active**:
```bash
nmcli connection show --active | grep auto-hotspot
```

### Permission Errors

If you see permission errors in logs:

**Add user to netdev group** (if not already):
```bash
sudo usermod -aG netdev $USER
# Then log out and log back in
```

### Multiple Ethernet Interfaces

The script activates hotspot when **ANY** ethernet interface connects. If you have multiple ethernet interfaces and want specific behavior, you can modify the `is_ethernet_connected()` function in the dispatcher script.

## Uninstallation

To remove the dispatcher script:

```bash
# Remove dispatcher script
sudo rm /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh

# Remove hotspot config
sudo rm /etc/NetworkManager/dispatcher.d/hotspot.env

# Optionally remove hotspot script
sudo rm /usr/local/bin/create_hotspot.sh
```

Then manually enable WiFi if needed:
```bash
nmcli radio wifi on
```

## Advanced Configuration

### Custom Paths

If you installed the hotspot script elsewhere, edit the dispatcher script:

```bash
sudo nano /etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh
```

Change:
```bash
HOTSPOT_SCRIPT="/path/to/your/create_hotspot.sh"
HOTSPOT_CONFIG="/path/to/your/hotspot.env"
```

### Different Connection Names

To use multiple hotspot configurations:

1. Create different config files:
   ```bash
   sudo cp /etc/NetworkManager/dispatcher.d/hotspot.env \
           /etc/NetworkManager/dispatcher.d/hotspot-travel.env
   ```

2. Edit the dispatcher script to use the alternate config:
   ```bash
   HOTSPOT_CONFIG="/etc/NetworkManager/dispatcher.d/hotspot-travel.env"
   ```

3. Ensure the connection name matches in both files

## How It Works

### Dispatcher Mechanism

NetworkManager calls scripts in `/etc/NetworkManager/dispatcher.d/` when network events occur:
- Scripts are called with arguments: `$1` = interface name, `$2` = action
- Actions include: `up`, `down`, `connectivity-change`, etc.
- Scripts run as root

### Script Logic

```
Connection Event
     ↓
Is ethernet connected?
     ↓
YES → Hotspot mode enabled?
     ↓              ↓
    YES            NO
     ↓              ↓
Create hotspot  Disable WiFi
     ↓
NO (ethernet disconnected)
     ↓
Stop hotspot (if active)
     ↓
Enable WiFi
```

### State Queries (No State Files)

The script doesn't maintain state files. Instead, it queries the actual system state:
- `nmcli device status` - Check ethernet connection
- `nmcli connection show --active` - Check hotspot status

This makes the script robust against restarts and race conditions.

## Security Considerations

1. **Config file permissions**: The hotspot.env file contains passwords and should be readable only by root (chmod 600)

2. **Logging**: The dispatcher logs to syslog but does NOT log passwords

3. **Script execution**: Dispatcher scripts run as root, so be careful about modifications

4. **WiFi password**: Use a strong password (10+ characters) in hotspot.env

## Files

- `/etc/NetworkManager/dispatcher.d/70-wifi-wired-exclusive.sh` - Dispatcher script
- `/etc/NetworkManager/dispatcher.d/hotspot.env` - Hotspot configuration
- `/usr/local/bin/create_hotspot.sh` - Main hotspot management script
- `/home/dvolgyes/workspace/hotspot.sh/dispatcher-hotspot.env` - Config template

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs: `journalctl -t nm-dispatcher-hotspot -n 100`
3. Test manually with the commands in the Testing section
4. Verify all files exist and have correct permissions

---

**Automatic hotspot management is now configured!** When you connect ethernet, the hotspot will start automatically (if enabled). When you disconnect ethernet, normal WiFi will be restored.
