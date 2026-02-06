#!/bin/bash
# Configure Meshtastic Telemetry, Position, and MQTT Settings
# For RAK6421 Pi-Hat + RAK1906 sensor
#
# This script configures:
# - Environment telemetry (RAK1906 sensor data)
# - Device telemetry intervals
# - GPS/Position update and broadcast settings
# - MQTT module to publish data to local broker
#
# All settings are applied in a single chained command to avoid
# multiple device reboots (important for all devices including Linux)

set -e

echo "=============================================="
echo "Configure Meshtastic Telemetry, Position & MQTT"
echo "=============================================="

# Check if meshtastic CLI is installed (required for this script; run 01-install-dependencies.sh first for system setup)
if ! command -v meshtastic &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "Meshtastic Python CLI is not installed or not in PATH."
    echo ""
    echo "Install the Meshtastic CLI (step 1 is 01-install-dependencies.sh for system deps):"
    echo "  python3 -m pip install --upgrade \"meshtastic[cli]\" --break-system-packages"
    echo ""
    echo "The path variables may or may not update for the current session when installing."
    echo "After installation, you may need to restart your terminal or run:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    exit 1
fi

echo ""
echo "Current device info:"
meshtastic --info || echo "Unable to get device info, please ensure meshtasticd is running"

echo ""
echo "----------------------------------------"
echo "Configure Telemetry, Position & MQTT Settings"
echo "----------------------------------------"
echo ""
echo "Configuring the following settings:"
echo "  - Environment telemetry: enabled"
echo "  - GPS mode: ENABLED"
echo "  - Position broadcast: smart disabled"
echo "  - MQTT: enabled, localhost broker, JSON enabled"
echo "  - Channel 0 uplink: enabled (for MQTT publishing)"
echo ""
echo "NOTE: All settings are applied in one command to avoid multiple device reboots"
echo ""

# Chain all configuration commands together to avoid multiple reboots
# This is critical for all devices (including Linux) as each --set causes a reboot
meshtastic \
  --set telemetry.environment_measurement_enabled true \
  --set position.gps_mode ENABLED \
  --set position.position_broadcast_smart_enabled false \
  --set mqtt.enabled true \
  --set mqtt.address localhost \
  --set mqtt.json_enabled true \
  --set mqtt.encryption_enabled false \
  --ch-set uplink_enabled true --ch-index 0

echo ""
echo "Configuration applied. Device is rebooting..."
echo "Waiting 10 seconds for device to restart..."
sleep 10

echo ""
echo "----------------------------------------"
echo "Verify Configuration"
echo "----------------------------------------"
echo ""
echo "Reading current settings from device (output may include connection messages):"
echo ""

# Get all configured settings in one call; output shows lines like:
#   position.gps_mode: 1
#   telemetry.environment_measurement_enabled: True
# (1 = ENABLED, 0 = DISABLED, 2 = NOT_PRESENT for gps_mode)

# meshtastic \
#   --get telemetry.environment_measurement_enabled \
#   --get position.gps_mode \
#   --get position.position_broadcast_smart_enabled \
#   || true

# echo ""
# echo "Expected values:"
# echo "  telemetry.environment_measurement_enabled: True"
# echo "  position.gps_mode: 1 (1=ENABLED, 0=DISABLED, 2=NOT_PRESENT)"
# echo "  position.position_broadcast_smart_enabled: False"
# echo ""

echo "=============================================="
echo "Telemetry, Position & MQTT Configuration Complete!"
echo "=============================================="
echo ""
echo "Telemetry Settings:"
echo "  - Environment telemetry: enabled"
echo "  - RAK1906 sensor provides:"
echo "    * Temperature"
echo "    * Relative Humidity"
echo "    * Barometric Pressure"
echo "    * Gas Resistance / IAQ (Air Quality Index)"
echo "  - RAK1901 sensor provides:"
echo "    * Temperature"
echo "    * Relative Humidity"
# echo "  - RAK12019 sensor provides:"
# echo "    * UV Light intensity"
echo ""
echo "Position Settings:"
echo "  - GPS mode: ENABLED"
echo "  - Smart broadcast: disabled (uses fixed interval)"
echo ""
echo "MQTT Settings:"
echo "  - MQTT module: enabled"
echo "  - Broker address: localhost:1883"
echo "  - JSON output: enabled (for Node-RED parsing)"
echo "  - Encryption: disabled (local network)"
echo "  - Channel 0 uplink: enabled"
echo ""
echo "Data will be published to MQTT topic: msh/..."
echo ""
echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./03-install-mosquitto.sh"
echo ""
