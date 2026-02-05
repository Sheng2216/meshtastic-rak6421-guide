#!/bin/bash
# Install InfluxDB 2.x on Raspberry Pi (64-bit OS)
#
# This script installs InfluxDB 2.x and creates a token that can be used
# by both Node-RED and Grafana.

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"

# Token storage location
TOKEN_DIR="/etc/meshtastic"
TOKEN_FILE="$TOKEN_DIR/influxdb_token"

# Load credentials from config file (if exists)
CREDENTIALS_FILE="$CONFIG_DIR/credentials.env"
if [ -f "$CREDENTIALS_FILE" ]; then
    source "$CREDENTIALS_FILE"
fi

# Set defaults if not defined in credentials file
INFLUXDB_USERNAME="${INFLUXDB_USERNAME:-admin}"
INFLUXDB_PASSWORD="${INFLUXDB_PASSWORD:-meshtastic}"
INFLUXDB_ORG="${INFLUXDB_ORG:-meshtastic}"
INFLUXDB_BUCKET="${INFLUXDB_BUCKET:-meshtastic}"
INFLUXDB_RETENTION="${INFLUXDB_RETENTION:-30d}"

echo "=========================================="
echo "Install InfluxDB 2.x"
echo "=========================================="

# Detect system architecture
ARCH=$(dpkg --print-architecture)
echo "System architecture: $ARCH"

# Check if repository is already configured
if [ ! -f /etc/apt/sources.list.d/influxdata.list ]; then
    echo "Adding InfluxDB repository..."
    
    # Download and verify the GPG key
    curl --silent --location -O https://repos.influxdata.com/influxdata-archive.key
    
    # Verify the key fingerprint
    echo "Verifying GPG key fingerprint..."
    if gpg --show-keys --with-fingerprint --with-colons ./influxdata-archive.key 2>&1 | grep -q '^fpr:\+24C975CBA61A024EE1B631787C3D57159FC2F927:$'; then
        echo "✓ GPG key verification successful"
        
        # Import the key to system
        sudo mkdir -p /etc/apt/keyrings
        cat influxdata-archive.key | gpg --dearmor | sudo tee /etc/apt/keyrings/influxdata-archive.gpg > /dev/null
        
        # Add repository
        echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
        
        rm influxdata-archive.key
        echo "✓ InfluxDB repository added"
    else
        echo "✗ GPG key verification failed"
        rm influxdata-archive.key
        exit 1
    fi
else
    echo "InfluxDB repository already configured"
fi

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install InfluxDB using package defaults (non-interactive, use new configs from package)
echo "Installing InfluxDB..."
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y \
    -o Dpkg::Options::="--force-confnew" \
    influxdb2

# Enable and start service
echo "Starting InfluxDB service..."
sudo systemctl enable influxdb
sudo systemctl start influxdb

# Wait for service to start
echo "Waiting for InfluxDB to start..."
sleep 5

# Verify service status
if systemctl is-active --quiet influxdb; then
    echo "✓ InfluxDB service is running"
else
    echo "✗ InfluxDB service failed to start"
    sudo systemctl status influxdb
    exit 1
fi

echo ""
echo "=========================================="
echo "Initialize InfluxDB"
echo "=========================================="

# Check if already initialized by checking if we can ping
if influx ping &>/dev/null; then
    echo "InfluxDB is running"
    
    # Try to initialize (if not already initialized)
    echo ""
    echo "Setting up InfluxDB..."
    echo "  Username: $INFLUXDB_USERNAME"
    echo "  Organization: $INFLUXDB_ORG"
    echo "  Bucket: $INFLUXDB_BUCKET"
    echo ""
    
    # Initialize InfluxDB
    # If already initialized, this command will fail but won't affect usage
    influx setup \
        --username "$INFLUXDB_USERNAME" \
        --password "$INFLUXDB_PASSWORD" \
        --org "$INFLUXDB_ORG" \
        --bucket "$INFLUXDB_BUCKET" \
        --retention "$INFLUXDB_RETENTION" \
        --force 2>/dev/null || echo "InfluxDB may already be initialized"
fi

echo ""
echo "=========================================="
echo "Create API Token"
echo "=========================================="

# Create token directory
sudo mkdir -p "$TOKEN_DIR"

# Wait for InfluxDB CLI configuration to be fully ready after setup
# This is critical - the CLI needs time to write its config to ~/.influxdbv2/configs
echo "Waiting for InfluxDB CLI configuration to be ready..."
sleep 5

# Verify CLI can communicate with InfluxDB before creating token
MAX_RETRIES=10
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if influx auth list &>/dev/null; then
        echo "✓ InfluxDB CLI is ready"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "  Waiting for CLI... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "⚠ CLI not responding, continuing anyway..."
fi

# Create a token with read/write permissions for both Node-RED and Grafana
echo "Creating API token for Node-RED and Grafana..."

# Function to extract token from output
extract_token() {
    local output="$1"
    local token=""
    
    # Method 1: Look for 86-char base64 token ending with ==
    token=$(echo "$output" | grep -oE '[A-Za-z0-9_-]{86}==')
    
    # Method 2: Look for any token-like string (20+ chars ending with = or ==)
    if [ -z "$token" ]; then
        token=$(echo "$output" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[A-Za-z0-9_-]{20,}==?$/) print $i}')
    fi
    
    echo "$token"
}

# Check if meshtastic-token already exists
EXISTING_TOKEN=$(influx auth list 2>/dev/null | grep "meshtastic-token" | head -1)
API_TOKEN=$(extract_token "$EXISTING_TOKEN")

if [ -n "$API_TOKEN" ]; then
    echo "✓ Token already exists, using existing token"
else
    # Create new token with retry logic
    echo "Creating new token..."
    
    MAX_CREATE_RETRIES=3
    CREATE_RETRY=0
    
    while [ $CREATE_RETRY -lt $MAX_CREATE_RETRIES ] && [ -z "$API_TOKEN" ]; do
        CREATE_RETRY=$((CREATE_RETRY + 1))
        
        if [ $CREATE_RETRY -gt 1 ]; then
            echo "  Retry $CREATE_RETRY/$MAX_CREATE_RETRIES..."
            sleep 3
        fi
        
        # Create token
        CREATE_OUTPUT=$(influx auth create \
            --org "$INFLUXDB_ORG" \
            --description "meshtastic-token" \
            --read-buckets \
            --write-buckets \
            --read-orgs 2>&1)
        
        # Extract token from create output
        API_TOKEN=$(extract_token "$CREATE_OUTPUT")
        
        # If extraction failed, try listing tokens to find it
        if [ -z "$API_TOKEN" ]; then
            sleep 1
            LIST_OUTPUT=$(influx auth list 2>/dev/null | grep "meshtastic-token" | head -1)
            API_TOKEN=$(extract_token "$LIST_OUTPUT")
        fi
    done
fi

# Save token to file
if [ -n "$API_TOKEN" ] && [ ${#API_TOKEN} -gt 20 ]; then
    echo "$API_TOKEN" | sudo tee "$TOKEN_FILE" > /dev/null
    sudo chmod 644 "$TOKEN_FILE"
    echo "✓ Token created and saved to $TOKEN_FILE"
    echo ""
    echo "Token: ${API_TOKEN:0:30}..."
else
    echo "✗ Warning: Could not create token automatically"
    echo ""
    echo "  You may need to create it manually in InfluxDB UI"
    echo "  Then save it to: $TOKEN_FILE"
fi

echo ""
echo "=========================================="
echo "InfluxDB installation complete!"
echo "=========================================="
echo ""
echo "InfluxDB UI: http://localhost:8086"
echo ""
echo "Configuration:"
echo "  Username: $INFLUXDB_USERNAME"
echo "  Password: $INFLUXDB_PASSWORD"
echo "  Organization: $INFLUXDB_ORG"
echo "  Bucket: $INFLUXDB_BUCKET"
echo "  Data retention: $INFLUXDB_RETENTION"
echo ""
echo "Token file: $TOKEN_FILE"
echo "  - Use this token for Node-RED InfluxDB node"
echo "  - Use this token for Grafana data source"
echo ""
echo "=========================================="
echo "Next Step"
echo "=========================================="
echo ""
echo "  Run: ./05-install-nodered.sh"
echo ""
