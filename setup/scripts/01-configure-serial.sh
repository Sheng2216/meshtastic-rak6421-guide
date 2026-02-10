#!/bin/bash
# Configure Serial Port for Meshtastic GPS Module
#
# This script enables UART hardware and disables the serial console so that
# the GPS module (e.g. RAK12500/RAK12501) can use the serial port.
# Can be run standalone or as part of install-all.sh.

set -e

echo "=========================================="
echo "Configure Serial Port for Meshtastic"
echo "=========================================="
echo ""
echo "Enabling UART hardware for GPS module..."
echo "Reference: https://meshtastic.org/docs/hardware/devices/linux-native-hardware/?os=debian"
echo ""

# Enable Serial Port hardware (enable_uart=1 in /boot/config.txt)
# This allows communication with GPS module via UART
sudo raspi-config nonint do_serial_hw 0

# Disable Serial Console (removes console=serial0,115200 from cmdline.txt)
# This prevents the Linux console from using the serial port
sudo raspi-config nonint do_serial_cons 1

# Uncomment meshtasticd config lines if currently commented (only touch commented lines)
# Format: we match lines starting with "#  Key: value" and replace with "  Key: value"
# so indentation is preserved and we never change lines that are already uncommented.
CONFIG_YAML="/etc/meshtasticd/config.yaml"
if [ -f "$CONFIG_YAML" ]; then
  changed_items=()
  CONFIG_YAML_RESULT="no changes"
  # I2C device for sensors (e.g. RAK1906)
  if grep -q '^#  I2CDevice: /dev/i2c-1' "$CONFIG_YAML"; then
    sudo sed -i 's/^#  I2CDevice: \/dev\/i2c-1/  I2CDevice: \/dev\/i2c-1/' "$CONFIG_YAML"
    changed_items+=( "I2CDevice" )
  fi
  # GPS serial path (ttyS0 = primary UART on Pi)
  if grep -q '^#  SerialPath: /dev/ttyS0' "$CONFIG_YAML"; then
    sudo sed -i 's/^#  SerialPath: \/dev\/ttyS0/  SerialPath: \/dev\/ttyS0/' "$CONFIG_YAML"
    changed_items+=( "SerialPath" )
  fi
  # Webserver port
  if grep -q '^#  Port: 9443' "$CONFIG_YAML"; then
    sudo sed -i 's/^#  Port: 9443/  Port: 9443/' "$CONFIG_YAML"
    changed_items+=( "Webserver Port" )
  fi
  if [ ${#changed_items[@]} -gt 0 ]; then
    changed_list=$(IFS=', '; echo "${changed_items[*]}")
    echo "✓ Uncommented in $CONFIG_YAML: $changed_list"
    CONFIG_YAML_RESULT="updated (uncommented: ${changed_list})"
  else
    echo "Config entries (I2CDevice, SerialPath, Webserver Port) already enabled or not present, skipping"
  fi
else
  echo "⚠ $CONFIG_YAML not found, skipping config uncomment"
  CONFIG_YAML_RESULT="not found (skipped)"
fi

echo "✓ Serial port configured for Meshtastic GPS"
echo ""
echo "  - UART hardware: Enabled (enable_uart=1)"
echo "  - Serial console: Disabled"
echo "  - meshtasticd config: $CONFIG_YAML_RESULT ($CONFIG_YAML)"
echo ""
echo "⚠ Note: A reboot is required for the serial port changes to take effect."
echo ""

echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./02-install-mosquitto.sh"
echo ""
