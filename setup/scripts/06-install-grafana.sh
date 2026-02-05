#!/bin/bash
# Install Grafana

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

# Load credentials from config file (if exists)
CREDENTIALS_FILE="$CONFIG_DIR/credentials.env"
if [ -f "$CREDENTIALS_FILE" ]; then
    source "$CREDENTIALS_FILE"
fi

# Set defaults if not defined in credentials file
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
INFLUXDB_ORG="${INFLUXDB_ORG:-meshtastic}"
INFLUXDB_BUCKET="${INFLUXDB_BUCKET:-meshtastic}"

echo "=========================================="
echo "Install Grafana"
echo "=========================================="

# Install dependencies
echo "Installing dependencies..."
sudo apt-get install -y apt-transport-https software-properties-common wget

# Check if repository is already configured
if [ ! -f /etc/apt/sources.list.d/grafana.list ]; then
    echo "Adding Grafana repository..."
    
    # Add GPG key
    sudo mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
    
    # Add repository
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    
    echo "✓ Grafana repository added"
else
    echo "Grafana repository already configured"
fi

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install Grafana using package defaults (non-interactive, use new configs from package)
echo "Installing Grafana..."
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y \
    -o Dpkg::Options::="--force-confnew" \
    grafana

# Enable and start service
echo "Starting Grafana service..."
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Wait for service to start
echo "Waiting for Grafana to start..."
sleep 5

# Verify service status
if systemctl is-active --quiet grafana-server; then
    echo "✓ Grafana service is running"
else
    echo "✗ Grafana service failed to start"
    sudo systemctl status grafana-server
    exit 1
fi

echo ""
echo "=========================================="
echo "Configure Grafana Data Source"
echo "=========================================="

# Create data source configuration directory
sudo mkdir -p /etc/grafana/provisioning/datasources
sudo mkdir -p /etc/grafana/provisioning/dashboards
sudo mkdir -p /var/lib/grafana/dashboards

GRAFANA_DIR="$(dirname "$SCRIPT_DIR")/grafana"

# Get InfluxDB token
echo "Getting InfluxDB API Token..."

TOKEN_FILE="/etc/meshtastic/influxdb_token"
INFLUXDB_TOKEN=""

# Method 1: Read from token file (created by 04-install-influxdb.sh)
if [ -f "$TOKEN_FILE" ]; then
    INFLUXDB_TOKEN=$(cat "$TOKEN_FILE")
    echo "✓ Token loaded from $TOKEN_FILE"
fi

# Method 2: Try to extract from influx auth list
if [ -z "$INFLUXDB_TOKEN" ]; then
    echo "Token file not found, trying to extract from InfluxDB..."
    # Look for meshtastic-token first
    INFLUXDB_TOKEN=$(influx auth list 2>/dev/null | grep "meshtastic-token" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[A-Za-z0-9_-]{20,}==?$/) print $i}')
fi

# Method 3: Use any available token as fallback
if [ -z "$INFLUXDB_TOKEN" ]; then
    echo "Meshtastic token not found, trying any available token..."
    INFLUXDB_TOKEN=$(influx auth list 2>/dev/null | tail -n +2 | head -1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[A-Za-z0-9_-]{20,}==?$/) print $i}')
fi

if [ -z "$INFLUXDB_TOKEN" ]; then
    echo "✗ Warning: Could not retrieve InfluxDB token"
    echo "  Please run 04-install-influxdb.sh first, or manually configure the data source"
    echo ""
    read -p "Enter InfluxDB token manually (or press Enter to skip): " INFLUXDB_TOKEN
fi

if [ -n "$INFLUXDB_TOKEN" ]; then
    echo "✓ Token retrieved: ${INFLUXDB_TOKEN:0:30}..."
fi

# Create InfluxDB data source configuration
cat << EOF | sudo tee /etc/grafana/provisioning/datasources/influxdb.yaml
apiVersion: 1

datasources:
  - name: InfluxDB
    uid: DS_INFLUXDB
    type: influxdb
    access: proxy
    url: http://localhost:8086
    jsonData:
      version: Flux
      organization: ${INFLUXDB_ORG}
      defaultBucket: ${INFLUXDB_BUCKET}
      tlsSkipVerify: true
    secureJsonData:
      token: ${INFLUXDB_TOKEN}
EOF

# Create Dashboard configuration
cat << 'EOF' | sudo tee /etc/grafana/provisioning/dashboards/meshtastic.yaml
apiVersion: 1

providers:
  - name: 'Meshtastic'
    orgId: 1
    folder: 'Meshtastic'
    folderUid: 'meshtastic'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 300
    options:
      path: /var/lib/grafana/dashboards
EOF

# Copy Dashboard JSON
if [ -f "$GRAFANA_DIR/dashboard.json" ]; then
    sudo cp "$GRAFANA_DIR/dashboard.json" /var/lib/grafana/dashboards/meshtastic-environment.json
    sudo chown grafana:grafana /var/lib/grafana/dashboards/meshtastic-environment.json
    echo "✓ Dashboard copied"
fi

# Set admin password if custom password is configured (not default "admin")
if [ "$GRAFANA_ADMIN_PASSWORD" != "admin" ]; then
    echo ""
    echo "Setting custom admin password..."
    sudo grafana-cli admin reset-admin-password "$GRAFANA_ADMIN_PASSWORD" 2>/dev/null || true
fi

# Restart Grafana to load configuration
echo "Restarting Grafana..."
sudo systemctl restart grafana-server
sleep 3

echo ""
echo "=========================================="
echo "Grafana installation complete!"
echo "=========================================="
echo ""
echo "Grafana URL: http://localhost:3000"
echo ""
echo "Login credentials:"
echo "  Username: $GRAFANA_ADMIN_USER"
if [ "$GRAFANA_ADMIN_PASSWORD" = "admin" ]; then
    echo "  Password: admin (you'll be asked to change on first login)"
else
    echo "  Password: $GRAFANA_ADMIN_PASSWORD"
fi
echo ""
if [ -n "$INFLUXDB_TOKEN" ]; then
    echo "✓ InfluxDB data source has been auto-configured"
    echo "✓ Dashboard has been auto-imported to Meshtastic folder"
    echo ""
    echo "Everything is ready! Just login and view the dashboard."
else
    echo "Note: InfluxDB token was not configured automatically."
    echo "Please configure manually:"
    echo "  1. Go to Configuration -> Data Sources"
    echo "  2. Edit InfluxDB data source"
    echo "  3. Enter InfluxDB API Token"
    echo "  4. Click Save & Test"
fi

echo ""
echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./check-services.sh"
echo ""
echo "  Then open Grafana at http://localhost:3000"
echo ""
