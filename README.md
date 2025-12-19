# WiFi Hotspot Script

A robust bash script to create and manage a WiFi hotspot on Ubuntu 24.04 (and similar Linux distributions) using NetworkManager. Share your ethernet internet connection with WiFi-enabled devices.

## Features

- **Auto-detection** of WiFi and ethernet interfaces
- **Rerunnable** - detects existing connections and reuses them
- **Multiple configuration methods** - .env file, environment variables, or script defaults
- **Management commands** - start, stop, delete, status
- **Verification** - checks IP forwarding, dnsmasq, and connectivity
- **Clean output** with helpful diagnostic messages

## Quick Start

1. **Copy the example configuration:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your preferences:**
   ```bash
   nano .env
   ```
   Set your desired SSID and password (minimum 8 characters).

3. **Install requirements:**
   ```bash
   sudo apt install network-manager dnsmasq
   ```

4. **Start the hotspot:**
   ```bash
   ./create_hotspot.sh start
   ```
   (Note: Usually works without sudo on modern Ubuntu systems)

5. **Connect your devices** to the WiFi network and enjoy internet access!

## Configuration

Configuration is loaded in this priority order:
1. **Custom config file** via `-c`/`--config` option (highest priority, for testing/multiple configs)
2. **`.env` file** (recommended) - in the same directory as the script
3. **Environment variables** - exported in your shell
4. **Script defaults** - hardcoded in the script (lowest priority)

### Configuration Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `HOTSPOT_CON_NAME` | NetworkManager connection name | `home-hotspot` |
| `HOTSPOT_SSID` | WiFi network name (visible to clients) | `home-hotspot` |
| `HOTSPOT_PASSWORD` | WiFi password (min 8 chars, 10+ recommended) | `examplecomplicatedpassword` |
| `WIFI_INTERFACE` | WiFi adapter name (empty = auto-detect) | _(auto)_ |
| `WIRED_INTERFACE` | Ethernet adapter name (empty = auto-detect) | _(auto)_ |

### Configuration Methods

#### Method 1: Using Custom Config File (Best for Testing/Multiple Configs)

```bash
# Create a custom config file
cp .env.example hotspot.env

# Edit your settings
nano hotspot.env

# Use it with -c or --config option
sudo ./create_hotspot.sh -c hotspot.env start
sudo ./create_hotspot.sh --config /path/to/config.env start
```

Example `hotspot.env`:
```bash
HOTSPOT_SSID=TestNetwork
HOTSPOT_PASSWORD=examplecomplicatedpassword
HOTSPOT_CON_NAME=test-hotspot
```

This is ideal for:
- Testing different configurations without modifying `.env`
- Maintaining multiple hotspot profiles (home, travel, guest)
- Temporary configurations that override your default `.env`

#### Method 2: Using .env file (Recommended for Daily Use)

```bash
# Copy example file
cp .env.example .env

# Edit your settings
nano .env

# Run without -c option to use .env automatically
sudo ./create_hotspot.sh start
```

Example `.env`:
```bash
HOTSPOT_SSID=MyHomeNetwork
HOTSPOT_PASSWORD=examplecomplicatedpassword
```

#### Method 4: Using Environment Variables

```bash
export HOTSPOT_SSID="MyNetwork"
export HOTSPOT_PASSWORD="examplecomplicatedpassword"
./create_hotspot.sh start
```

Or inline:
```bash
HOTSPOT_SSID=MyNetwork HOTSPOT_PASSWORD=examplecomplicatedpassword ./create_hotspot.sh start
```

#### Method 5: Edit Script Defaults

Edit lines 62-64 in `create_hotspot.sh` to change the fallback defaults.

## Commands

### Start Hotspot
```bash
./create_hotspot.sh start
# or simply:
./create_hotspot.sh
```

Creates the hotspot connection (if it doesn't exist) and activates it. Safe to run multiple times.

### Stop Hotspot
```bash
./create_hotspot.sh stop
```

Temporarily deactivates the hotspot while keeping the configuration. Useful when disconnecting ethernet.

### Check Status
```bash
./create_hotspot.sh status
```

Shows whether the hotspot is configured and active.

### Delete Hotspot
```bash
./create_hotspot.sh delete
```

Permanently removes the hotspot connection from NetworkManager.

### Show Help
```bash
./create_hotspot.sh help
```

Displays usage information and examples.

## Use Cases

### 1. **Home Office Setup**
Share your wired ethernet connection with mobile devices (phones, tablets) without needing a separate router.

```bash
# One-time setup
cp .env.example .env
nano .env  # Set SSID and password
./create_hotspot.sh start

# Your phone and tablet can now access the internet via WiFi
```

### 2. **Hotel/Conference Room Internet Sharing**
Connect your laptop via ethernet and share the connection with multiple devices (phones, colleagues' laptops).

```bash
# At the hotel
./create_hotspot.sh start

# Before checkout
./create_hotspot.sh stop
```

### 3. **Development/Testing Environment**
Create a controlled WiFi network for testing mobile apps or IoT devices.

```bash
# Create test network
HOTSPOT_SSID=TestNetwork HOTSPOT_PASSWORD=examplecomplicatedpassword ./create_hotspot.sh start

# Test your mobile app...

# Clean up
./create_hotspot.sh delete
```

### 4. **Temporary WiFi for Guests**
Provide internet access to visitors without sharing your main WiFi password.

```bash
# Start guest network
./create_hotspot.sh start

# When guests leave
./create_hotspot.sh stop
```

### 5. **IoT Device Setup**
Some IoT devices only support WiFi. Use this to provide internet during initial setup.

```bash
# Start hotspot
./create_hotspot.sh start

# Configure your smart device to connect
# Device gets internet via your ethernet connection

# After setup, stop if not needed
./create_hotspot.sh stop
```

### 6. **Portable Router Replacement**
Use your laptop as a WiFi access point when traveling or in remote locations.

```bash
# Connect laptop to ethernet
# Start hotspot
./create_hotspot.sh start

# Multiple devices can now connect through your laptop
```

### 7. **Before Disconnecting Ethernet**
If you know you'll be disconnecting from ethernet (e.g., moving to another room), stop the hotspot first:

```bash
# Before unplugging ethernet cable
./create_hotspot.sh stop

# Unplug and move...

# After reconnecting ethernet elsewhere
./create_hotspot.sh start
```

## Requirements

- **Ubuntu 24.04** (or similar Linux distribution)
- **NetworkManager** - Usually pre-installed on Ubuntu Desktop
- **dnsmasq** - Required for DHCP server
  ```bash
  sudo apt install dnsmasq
  ```

### About Permissions

On modern Ubuntu systems (24.04 and recent versions), **sudo is usually NOT required** for nmcli connection operations. The script works directly without root privileges because:
- Your user is likely in the appropriate groups (`netdev` or similar)
- PolicyKit/polkit rules allow NetworkManager operations for logged-in users

**If you get permission errors:**
1. First, try adding your user to the netdev group:
   ```bash
   sudo usermod -aG netdev $USER
   # Then log out and log back in
   ```

2. Alternatively, run individual commands with sudo:
   ```bash
   sudo ./create_hotspot.sh start
   ```
   (sudo remembers credentials for ~15 minutes by default)

## Troubleshooting

### Issue: Clients can connect but have no internet

**Solution 1:** Enable IP forwarding
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

To make permanent, add to `/etc/sysctl.conf`:
```bash
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

**Solution 2:** Install dnsmasq
```bash
sudo apt install dnsmasq
```

**Solution 3:** Ensure ethernet is connected
```bash
nmcli device status | grep ethernet
```

### Issue: "No WiFi interface found"

Your WiFi adapter may not support AP (Access Point) mode. Check with:
```bash
iw list | grep -A 10 "Supported interface modes"
```

Look for "AP" in the output.

### Issue: "Connection activation failed: Secrets were required"

Password must be at least 8 characters long. Update your `.env` file or script defaults.

### Issue: Script fails when run without sudo

Most commands (start, stop, delete) require root privileges. Use:
```bash
sudo ./create_hotspot.sh start
```

Only `status` and `help` work without sudo.

## How It Works

1. **Interface Detection** - Automatically finds your WiFi and ethernet interfaces using `nmcli`
2. **Connection Creation** - Creates a NetworkManager WiFi connection in AP mode with WPA-PSK security
3. **Internet Sharing** - Uses `ipv4.method shared` which:
   - Assigns IP to WiFi interface (default: 10.42.0.1)
   - Runs dnsmasq for DHCP (assigns IPs to clients)
   - Sets up NAT (Network Address Translation) for internet sharing
4. **Verification** - Checks that IP forwarding is enabled and dnsmasq is running

## Advanced Usage

### Custom Interface Selection

If auto-detection picks the wrong interface:

```bash
# In .env file
WIFI_INTERFACE=wlp4s0
WIRED_INTERFACE=enp3s0
```

### Multiple Hotspot Configurations

#### Option 1: Using -c flag (Recommended - Simpler)

```bash
# Create different config files
cp .env.example hotspot-home.env
cp .env.example hotspot-travel.env
cp .env.example hotspot-guest.env

# Edit each with different settings
nano hotspot-home.env    # SSID=HomeNetwork, CON_NAME=home-hotspot
nano hotspot-travel.env  # SSID=TravelNetwork, CON_NAME=travel-hotspot
nano hotspot-guest.env   # SSID=GuestNetwork, CON_NAME=guest-hotspot

# Use home config
./create_hotspot.sh -c hotspot-home.env start

# Switch to travel config (different connection name, so no need to delete)
./create_hotspot.sh -c hotspot-travel.env start

# Or use guest config
./create_hotspot.sh -c hotspot-guest.env start

# Check status of specific config
./create_hotspot.sh -c hotspot-home.env status

# Stop specific config
./create_hotspot.sh -c hotspot-travel.env stop
```

#### Option 2: Using .env symlinks (Alternative)

```bash
# Create configs
cp .env.example .env.home
cp .env.example .env.travel

# Edit each with different settings
nano .env.home    # SSID=HomeNetwork
nano .env.travel  # SSID=TravelNetwork

# Use home config
ln -sf .env.home .env
./create_hotspot.sh start

# Switch to travel config
ln -sf .env.travel .env
./create_hotspot.sh delete  # Remove old
./create_hotspot.sh start   # Create new
```

### Running on Boot

Add to crontab to start hotspot on boot:

```bash
sudo crontab -e

# Add this line:
@reboot sleep 30 && /path/to/create_hotspot.sh start
```

## Security Considerations

- Use a **strong password** (10+ characters, mix of letters, numbers, symbols)
- Change the default SSID and password in your `.env` file
- Use `stop` or `delete` when not actively using the hotspot
- Keep your `.env` file secure (it contains your WiFi password):
  ```bash
  chmod 600 .env
  ```

## Files

- `create_hotspot.sh` - Main script
- `.env` - Your default configuration (create from `.env.example`)
- `.env.example` - Example configuration template
- `hotspot.env` - Sample custom config for testing `-c` option
- `README.md` - This file

## License

Free to use and modify as needed.

## Contributing

Feel free to submit issues or improvements!

---

**Enjoy your WiFi hotspot!** 📶
