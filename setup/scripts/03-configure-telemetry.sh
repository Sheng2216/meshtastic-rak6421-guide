#!/bin/bash
# Configure Meshtastic Telemetry, Position, and MQTT Settings
# For RAK6421 Pi-Hat + RAK1906 sensor
#
# This script configures:
# - Environment telemetry (RAK1906 sensor data)
# - Device telemetry intervals
# - GPS/Position update and broadcast settings
# - MQTT module to publish data to local broker
# - Channel 0 uplink enabled (required for MQTT publishing)
#
# All settings are applied in a single chained command to avoid
# multiple device reboots (important for all devices including Linux)

set -e

echo "=============================================="
echo "Configure Meshtastic Telemetry, Position & MQTT"
echo "=============================================="

# Check if meshtastic CLI is installed (required for this script; run 01-configure-serial.sh first if using GPS)
if ! command -v meshtastic &> /dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "Meshtastic Python CLI is not installed or not in PATH."
    echo ""
    echo "Install the Meshtastic CLI (see README for setup order; 01-configure-serial.sh configures GPS serial):"
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

# ============================================
# Configuration Definition
# ============================================
# To add new config items, simply add entries to the arrays below.
# Format: "config_key|set_value|expected_verify_value"
#
# - config_key: The meshtastic configuration key (e.g., mqtt.enabled)
# - set_value: The value to set via --set (e.g., true, ENABLED, localhost)
# - expected_verify_value: The expected value from --get for verification
#   Note: Some values differ between set and get (e.g., ENABLED -> 1)

CONFIG_ITEMS=(
  "telemetry.environment_measurement_enabled|true|True"
  "telemetry.environment_update_interval|1800|1800"
  "position.gps_mode|ENABLED|1"
  "position.position_broadcast_smart_enabled|false|False"
  "mqtt.enabled|true|True"
  "mqtt.address|localhost|localhost"
  "mqtt.json_enabled|true|True"
  "mqtt.encryption_enabled|false|False"
)

# Channel-specific settings (format: "channel_index|setting_key|value")
# These use --ch-set syntax instead of --set
CHANNEL_CONFIGS=(
  "0|uplink_enabled|true"
)

# ============================================
# Helper Functions
# ============================================

apply_config() {
  local cmd_args=()
  
  # Build --set arguments for regular config items
  for item in "${CONFIG_ITEMS[@]}"; do
    IFS='|' read -r key set_val expected_val <<< "$item"
    cmd_args+=( "--set" "$key" "$set_val" )
  done
  
  # Build --ch-set arguments for channel configs
  for ch_item in "${CHANNEL_CONFIGS[@]}"; do
    IFS='|' read -r ch_idx ch_key ch_val <<< "$ch_item"
    cmd_args+=( "--ch-set" "$ch_key" "$ch_val" "--ch-index" "$ch_idx" )
  done
  
  # Execute meshtastic with all arguments
  meshtastic "${cmd_args[@]}"
}

verify_and_collect_failures() {
  local get_args=()
  local keys=()
  declare -A expected
  
  # Build --get arguments and expected values map
  for item in "${CONFIG_ITEMS[@]}"; do
    IFS='|' read -r key set_val expected_val <<< "$item"
    get_args+=( "--get" "$key" )
    keys+=( "$key" )
    expected[$key]="$expected_val"
  done
  
  # Get current values from device
  local output
  output=$(meshtastic "${get_args[@]}" 2>&1) || true
  
  # Compare actual vs expected values
  local failed_list=()
  for key in "${keys[@]}"; do
    want="${expected[$key]}"
    key_escaped=$(echo "$key" | sed 's/\./\\./g')
    got=$(echo "$output" | sed -n "s/^${key_escaped}: *//p" | head -1)
    if [ "$got" != "$want" ]; then
      failed_list+=( "$key (expected: $want, got: ${got:-<empty>})" )
    fi
  done
  
  printf '%s\n' "${failed_list[@]}"
}

verify_channel_configs() {
  # Verify channel configurations using --info output
  # Returns: list of failed channel settings
  local failed_list=()
  
  # Get device info (contains channel configuration)
  local info_output
  info_output=$(meshtastic --info 2>&1) || true
  
  # Verify each channel config
  for ch_item in "${CHANNEL_CONFIGS[@]}"; do
    IFS='|' read -r ch_idx ch_key ch_val <<< "$ch_item"
    
    # Convert setting key to JSON format (e.g., uplink_enabled -> uplinkEnabled)
    local json_key
    json_key=$(echo "$ch_key" | sed -r 's/_([a-z])/\U\1/g')
    
    # Check if the setting appears in the channel output
    # Looking for pattern like: "uplinkEnabled": true in the channel index section
    local channel_section
    channel_section=$(echo "$info_output" | grep -A 5 "Index $ch_idx:" || echo "")
    
    if [ -z "$channel_section" ]; then
      failed_list+=( "channel[$ch_idx].$ch_key (channel not found in output)" )
      continue
    fi
    
    # Check if the expected value is present
    if ! echo "$channel_section" | grep -q "\"$json_key\": $ch_val"; then
      failed_list+=( "channel[$ch_idx].$ch_key (expected: $ch_val)" )
    fi
  done
  
  printf '%s\n' "${failed_list[@]}"
}

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

# Apply all configuration in a single command to avoid multiple reboots
# This is critical for all devices (including Linux) as each --set causes a reboot
apply_config

echo ""
echo "Configuration applied. Device is rebooting..."
echo "Waiting 30 seconds for device to restart..."
sleep 30

echo ""
echo "----------------------------------------"
echo "Verify Configuration"
echo "----------------------------------------"
echo ""

# ============================================
# Verification Loop with Retry
# ============================================

MAX_RETRIES=3
attempt=1
failed_items=""

while true; do
  echo "Reading current settings from device (attempt $attempt)..."
  echo ""
  failed_items=$(verify_and_collect_failures)
  failed_channels=$(verify_channel_configs)
  
  # Combine all failures
  all_failures=""
  [ -n "$failed_items" ] && all_failures="$failed_items"
  [ -n "$failed_channels" ] && all_failures="${all_failures}${all_failures:+$'\n'}${failed_channels}"
  
  if [ -z "$all_failures" ]; then
    echo "✓ All settings verified successfully."
    break
  fi
  if [ "$attempt" -gt "$MAX_RETRIES" ]; then
    echo "✗ Verification failed after $MAX_RETRIES retries. The following settings could not be applied:"
    echo ""
    echo "$all_failures" | while read -r line; do echo "  - $line"; done
    echo ""
    exit 1
  fi
  echo "Some settings did not match. Failed items:"
  echo "$all_failures" | while read -r line; do echo "  - $line"; done
  echo ""
  echo "Re-applying configuration (retry $attempt/$MAX_RETRIES)..."
  echo ""
  set +e
  apply_config
  set -e
  echo "Waiting 30 seconds for device to restart..."
  sleep 30
  echo ""
  attempt=$((attempt + 1))
done

echo ""
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
echo "  Run: ./04-install-influxdb.sh"
echo ""
