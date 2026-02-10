#!/bin/bash
# Display InfluxDB token for manual configuration

TOKEN_FILE="/etc/meshtasticd/influxdb_token"

echo "=========================================="
echo "InfluxDB API Token"
echo "=========================================="
echo ""

if [ -f "$TOKEN_FILE" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
    echo "Token:"
    echo ""
    echo "$TOKEN"
    echo ""
    echo "=========================================="
    echo ""
    echo "Configure Node-RED:"
    echo "  1. Open http://<Pi-IP>:1880"
    echo "  2. Double-click 'Write to InfluxDB' node"
    echo "  3. Click pencil icon next to 'Local InfluxDB'"
    echo "  4. Paste the token above into 'Token' field"
    echo "  5. Click 'Update', then 'Done'"
    echo "  6. Click 'Deploy'"
    echo ""
    echo "Grafana:"
    echo "  (Auto-configured by 06-install-grafana.sh)"
else
    echo "✗ Token file not found: $TOKEN_FILE"
    echo ""
    echo "Please run 04-install-influxdb.sh first to create the token."
    echo ""
    echo "Or check InfluxDB for existing tokens:"
    echo "  influx auth list"
fi
