#!/bin/bash
# ==========================================================================
# Meshtastic Monitoring System - Complete Installation Script
# ==========================================================================
#
# This script installs all components of the Meshtastic environment
# monitoring system in the correct order:
#
#   1. Meshtastic Python CLI
#   2. Telemetry & MQTT Configuration
#   3. Mosquitto MQTT Broker
#   4. InfluxDB Time-series Database
#   5. Node-RED Flow Engine
#   6. Grafana Visualization
#
# Prerequisites:
#   - Raspberry Pi with 64-bit Raspberry Pi OS
#   - meshtasticd installed and running
#   - RAK6421 Pi-Hat + RAK13300 + RAK1906 + RAK1901 hardware connected
#
# Usage:
#   ./install-all.sh          # Run all installations
#   ./install-all.sh --help   # Show this help
#
# Configuration:
#   Edit setup/config/credentials.env to customize passwords before running.
#
# ==========================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Meshtastic Monitoring System - Complete Installation"
    echo ""
    echo "Usage: ./install-all.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo "  --skip-cli     Skip Meshtastic Python CLI installation"
    echo "  --skip-config  Skip telemetry configuration"
    echo ""
    echo "This script installs all components in order:"
    echo "  1. Meshtastic Python CLI"
    echo "  2. Telemetry & MQTT Configuration"
    echo "  3. Mosquitto MQTT Broker"
    echo "  4. InfluxDB Time-series Database"
    echo "  5. Node-RED Flow Engine"
    echo "  6. Grafana Visualization"
    echo ""
    echo "Configuration:"
    echo "  Edit setup/config/credentials.env to customize passwords."
    exit 0
fi

# Parse arguments
SKIP_CLI=false
SKIP_CONFIG=false

for arg in "$@"; do
    case $arg in
        --skip-cli)
            SKIP_CLI=true
            ;;
        --skip-config)
            SKIP_CONFIG=true
            ;;
    esac
done

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Meshtastic Monitoring System - Complete Installation     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show configuration info
CONFIG_FILE="$SCRIPT_DIR/../config/credentials.env"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${GREEN}✓${NC} Using credentials from: config/credentials.env"
else
    echo -e "${YELLOW}!${NC} No credentials.env found, using default values"
fi
echo ""

# Estimated time
echo "Estimated installation time: 30-45 minutes"
echo "(Node-RED installation takes the longest on slower Pi models)"
echo ""
read -p "Press Enter to start installation, or Ctrl+C to cancel..."
echo ""

# Track start time
START_TIME=$(date +%s)

# Function to run a script with status display
run_step() {
    local step_num=$1
    local step_name=$2
    local script=$3
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Step $step_num: $step_name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ -x "$SCRIPT_DIR/$script" ]; then
        "$SCRIPT_DIR/$script"
        echo ""
        echo -e "${GREEN}✓ Step $step_num completed${NC}"
    else
        echo -e "${RED}✗ Script not found or not executable: $script${NC}"
        exit 1
    fi
}

# Step 1: Install Meshtastic Python CLI
if [ "$SKIP_CLI" = false ]; then
    run_step 1 "Install Meshtastic Python CLI" "01-install-meshtastic-python-cli.sh"
else
    echo -e "${YELLOW}Skipping Step 1: Meshtastic Python CLI${NC}"
fi

# Step 2: Configure Telemetry
if [ "$SKIP_CONFIG" = false ]; then
    run_step 2 "Configure Telemetry & MQTT" "02-configure-telemetry.sh"
else
    echo -e "${YELLOW}Skipping Step 2: Telemetry Configuration${NC}"
fi

# Step 3: Install Mosquitto
run_step 3 "Install Mosquitto MQTT Broker" "03-install-mosquitto.sh"

# Step 4: Install InfluxDB
run_step 4 "Install InfluxDB" "04-install-influxdb.sh"

# Step 5: Install Node-RED
run_step 5 "Install Node-RED" "05-install-nodered.sh"

# Step 6: Install Grafana
run_step 6 "Install Grafana" "06-install-grafana.sh"

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECONDS=$((ELAPSED % 60))

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Installation Complete!                          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Total installation time: ${GREEN}${MINUTES}m ${SECONDS}s${NC}"
echo ""

# Check services
echo "Checking service status..."
echo ""
"$SCRIPT_DIR/check-services.sh"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Manual Configuration Required${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Node-RED requires manual token configuration:"
echo ""
echo "  1. Get the token:"
echo "     ./show-token.sh"
echo ""
echo "  2. Configure Node-RED:"
echo "     - Open http://localhost:1880"
echo "     - Double-click 'Write to InfluxDB' node"
echo "     - Click pencil icon next to 'Local InfluxDB'"
echo "     - Paste the token into 'Token' field"
echo "     - Click 'Update', then 'Done'"
echo "     - Click 'Deploy'"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Access URLs${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
echo "  Node-RED:  http://$IP:1880"
echo "  InfluxDB:  http://$IP:8086"
echo "  Grafana:   http://$IP:3000"
echo ""
