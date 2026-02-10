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
TOKEN_DIR="/etc/meshtasticd"
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

# Install dependencies required for adding InfluxDB repository (curl, gnupg, apt-transport-https)
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y curl gnupg apt-transport-https

# Detect system architecture
ARCH=$(dpkg --print-architecture)
echo "System architecture: $ARCH"

# Check if InfluxDB repository keyring is already installed
# Per https://docs.influxdata.com/influxdb/v2/install/#choose-the-influxdata-key-pair-for-your-os-version
# - Newer (Debian Buster+, Ubuntu 20.04+): influxdata-archive.key, fingerprint 24C975CBA61A024EE1B631787C3D57159FC2F927
# - Older (Debian Stretch, Ubuntu 18.04): influxdata-archive_compat.key, fingerprint 9D539D90D3328DC7D6C8D3B9D8FF8E1F7DF8B07E
if ! dpkg -l influxdata-archive-keyring &>/dev/null; then
    echo "Setting up InfluxDB repository..."
    
    # Use the key for newer OS (Debian Buster+ / Ubuntu 20.04+) which support subkey verification
    INFLUX_KEY_URL="https://repos.influxdata.com/influxdata-archive.key"
    INFLUX_KEY_FILE="influxdata-archive.key"
    INFLUX_KEY_FPR="24C975CBA61A024EE1B631787C3D57159FC2F927"
    
    echo "Downloading InfluxDB keyring package..."
    curl --silent --location -O "$INFLUX_KEY_URL"
    
    # Verify the key fingerprint
    echo "Verifying GPG key fingerprint..."
    if gpg --show-keys --with-fingerprint --with-colons "./$INFLUX_KEY_FILE" 2>&1 | grep -q '^fpr:\+24C975CBA61A024EE1B631787C3D57159FC2F927:$'; then
        echo "✓ GPG key verification successful"
        
        # Import the key to system
        sudo mkdir -p /etc/apt/keyrings
        cat "./$INFLUX_KEY_FILE" | gpg --dearmor | sudo tee /etc/apt/keyrings/influxdata-archive.gpg > /dev/null
        
        # Add repository (per official docs)
        echo 'deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
        
        rm "./$INFLUX_KEY_FILE"
        
        # Update package list and install keyring package
        echo "Installing InfluxDB keyring package..."
        sudo apt-get update
        # Use sudo -E to preserve DEBIAN_FRONTEND environment variable
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            -o Dpkg::Options::="--force-confnew" \
            -o Dpkg::Options::="--force-confdef" \
            influxdata-archive-keyring
        
        echo "✓ InfluxDB repository configured via keyring package"
    else
        echo "✗ GPG key verification failed"
        rm -f "./$INFLUX_KEY_FILE"
        exit 1
    fi
else
    echo "InfluxDB repository keyring already installed"
fi

# Update package list to use the official repository configuration
echo "Updating package list..."
sudo apt-get update

# Install InfluxDB using package defaults (non-interactive, use new configs from package)
echo "Installing InfluxDB and CLI tools..."
DEBIAN_FRONTEND=noninteractive sudo apt-get install -y \
    -o Dpkg::Options::="--force-confnew" \
    -o Dpkg::Options::="--force-confdef" \
    influxdb2 \
    influxdb2-cli

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

# Verify CLI tool is installed
echo "Verifying InfluxDB CLI installation..."
if ! command -v influx &>/dev/null; then
    echo "✗ Error: influx CLI tool not found"
    echo "  This should not happen after installing influxdb2-cli"
    exit 1
fi
echo "✓ InfluxDB CLI tool is available"

echo ""
echo "=========================================="
echo "Initialize InfluxDB"
echo "=========================================="

# Check if already initialized by checking if we can ping
echo "Testing InfluxDB connection..."
if influx ping &>/dev/null; then
    echo "✓ InfluxDB is responding"
    
    # Try to initialize (if not already initialized)
    echo ""
    echo "Setting up InfluxDB..."
    echo "  Username: $INFLUXDB_USERNAME"
    echo "  Organization: $INFLUXDB_ORG"
    echo "  Bucket: $INFLUXDB_BUCKET"
    echo ""
    
    # Initialize InfluxDB
    # If already initialized, this command will fail but won't affect usage
    SETUP_OUTPUT=$(influx setup \
        --username "$INFLUXDB_USERNAME" \
        --password "$INFLUXDB_PASSWORD" \
        --org "$INFLUXDB_ORG" \
        --bucket "$INFLUXDB_BUCKET" \
        --retention "$INFLUXDB_RETENTION" \
        --force 2>&1) || true
    
    if echo "$SETUP_OUTPUT" | grep -q "has already been set up"; then
        echo "✓ InfluxDB was already initialized"
    elif echo "$SETUP_OUTPUT" | grep -q "User"; then
        echo "✓ InfluxDB initialized successfully"
    else
        echo "⚠ Setup output: $SETUP_OUTPUT"
    fi
else
    echo "✗ Error: InfluxDB is not responding to ping"
    exit 1
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
echo "Verifying CLI configuration..."
MAX_RETRIES=10
RETRY_COUNT=0
CLI_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if influx auth list &>/dev/null; then
        echo "✓ InfluxDB CLI is configured and ready"
        CLI_READY=true
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "  Waiting for CLI configuration... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

if [ "$CLI_READY" = false ]; then
    echo "⚠ Warning: CLI not responding after $MAX_RETRIES attempts"
    echo "  Checking if config file exists..."
    if [ -f ~/.influxdbv2/configs ]; then
        echo "  Config file exists at: ~/.influxdbv2/configs"
    else
        echo "  Config file missing at: ~/.influxdbv2/configs"
        echo "  This might indicate the setup command didn't complete successfully"
    fi
    echo ""
    echo "  Attempting to continue with token creation anyway..."
fi

# Create a token with read/write permissions for both Node-RED and Grafana
echo "Creating API token for Node-RED and Grafana..."

# Function to extract token from output
extract_token() {
    local output="$1"
    local token=""
    
    # Method 1: Look for 86-char base64 token ending with ==
    token=$(echo "$output" | grep -oE '[A-Za-z0-9_-]{86}==' || true)
    
    # Method 2: Look for any token-like string (20+ chars ending with = or ==)
    if [ -z "$token" ]; then
        token=$(echo "$output" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[A-Za-z0-9_-]{20,}==?$/) print $i}' || true)
    fi
    
    echo "$token"
}

# Check if meshtastic-token already exists
# Disable error checking temporarily for this non-critical operation
set +e
EXISTING_TOKEN=$(influx auth list 2>/dev/null | grep "meshtastic-token" | head -1)
API_TOKEN=$(extract_token "$EXISTING_TOKEN")
set -e

if [ -n "$API_TOKEN" ]; then
    echo "✓ Token already exists, using existing token"
else
    # Create new token with retry logic
    echo "Creating new token..."
    
    MAX_CREATE_RETRIES=3
    CREATE_RETRY=0
    
    set +e  # Disable error checking for token creation
    
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
            --read-orgs 2>&1 || echo "Token creation failed")
        
        # Extract token from create output
        API_TOKEN=$(extract_token "$CREATE_OUTPUT")
        
        # If extraction failed, try listing tokens to find it
        if [ -z "$API_TOKEN" ]; then
            sleep 1
            LIST_OUTPUT=$(influx auth list 2>/dev/null | grep "meshtastic-token" | head -1 || echo "")
            API_TOKEN=$(extract_token "$LIST_OUTPUT")
        fi
    done
    
    set -e  # Re-enable error checking
fi

# Save token to file
if [ -n "$API_TOKEN" ] && [ ${#API_TOKEN} -gt 20 ]; then
    echo "$API_TOKEN" | sudo tee "$TOKEN_FILE" > /dev/null
    sudo chmod 644 "$TOKEN_FILE"
    echo "✓ Token created and saved to $TOKEN_FILE"
    echo ""
    echo "Token: ${API_TOKEN:0:30}..."
else
    echo "⚠ Warning: Could not create token automatically"
    echo ""
    echo "  You may need to create it manually in InfluxDB UI"
    echo "  Then save it to: $TOKEN_FILE"
    echo ""
    echo "  This is non-critical - continuing with installation..."
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
