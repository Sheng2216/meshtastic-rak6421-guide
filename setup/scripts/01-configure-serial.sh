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

echo "✓ Serial port configured for Meshtastic GPS"
echo ""
echo "  - UART hardware: Enabled (enable_uart=1)"
echo "  - Serial console: Disabled"
echo ""
echo "⚠ Note: A reboot is required for the serial port changes to take effect."
echo ""

echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./02-configure-telemetry.sh"
echo ""
