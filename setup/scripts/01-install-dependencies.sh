#!/bin/bash
# Install System Dependencies and Configure Hardware
# This script installs all system dependencies required by the setup scripts
# and configures serial port for Meshtastic GPS module

set -e

echo "=========================================="
echo "Install System Dependencies"
echo "=========================================="

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install core dependencies required by various setup scripts:
# - curl: Used by InfluxDB and Node-RED installation
# - wget: Used by Grafana installation
# - gnupg: Used for GPG key verification (InfluxDB, Grafana)
# - apt-transport-https: Required for HTTPS APT repositories (InfluxDB, Grafana)
echo ""
echo "Installing dependencies..."
sudo apt-get install -y \
    curl \
    wget \
    gnupg \
    apt-transport-https

echo "✓ System dependencies installed successfully"

echo ""
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

echo "✓ Serial port configured for Meshtastic GPS"
echo ""
echo "  - UART hardware: Enabled (enable_uart=1)"
echo "  - Serial console: Disabled"
echo ""
echo "⚠ Note: A reboot will be required after completing all setup steps"
echo "  for the serial port changes to take effect."

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "System is ready for Meshtastic setup."
echo ""
echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./02-configure-telemetry.sh"
echo ""
