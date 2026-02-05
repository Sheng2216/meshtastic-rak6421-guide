#!/bin/bash
# Install and configure Mosquitto MQTT Broker

set -e

echo "=========================================="
echo "Install Mosquitto MQTT Broker"
echo "=========================================="

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install Mosquitto broker only (no client tools; use Node-RED or other clients for testing)
echo "Installing Mosquitto..."
sudo apt-get install -y mosquitto

# Create configuration directory
sudo mkdir -p /etc/mosquitto/conf.d

# Copy configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

echo "Configuring Mosquitto..."
sudo cp "$CONFIG_DIR/mosquitto.conf" /etc/mosquitto/conf.d/meshtastic.conf

# Enable and start service
echo "Starting Mosquitto service..."
sudo systemctl enable mosquitto
sudo systemctl restart mosquitto

# Wait for service to start
sleep 2

# Verify installation
echo ""
echo "Verifying Mosquitto installation..."
if systemctl is-active --quiet mosquitto; then
    echo "✓ Mosquitto service is running"
else
    echo "✗ Mosquitto service failed to start"
    sudo systemctl status mosquitto
    exit 1
fi

echo ""
echo "=========================================="
echo "Mosquitto MQTT Broker installation complete!"
echo "=========================================="
echo ""
echo "MQTT Broker address: localhost:1883"
echo "Configuration file: /etc/mosquitto/conf.d/meshtastic.conf"
echo ""
echo "MQTT Topic format:"
echo "  msh/2/json/{channelId}/{nodeId}"
echo ""
echo "To test MQTT (optional):"
echo "  sudo apt-get install mosquitto-clients"
echo "  mosquitto_sub -h localhost -t 'msh/#' -v"
echo ""
echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./04-install-influxdb.sh"
echo ""

