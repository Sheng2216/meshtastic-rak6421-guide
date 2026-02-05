#!/bin/bash
# Check all service status

echo "=========================================="
echo "Meshtastic Monitoring System Service Status"
echo "=========================================="
echo ""

# Define colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

check_service() {
    local service=$1
    local name=$2
    local port=$3
    
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓${NC} $name is running"
        if [ -n "$port" ]; then
            echo "  URL: http://localhost:$port"
        fi
    else
        echo -e "${RED}✗${NC} $name is not running"
        echo "  Start command: sudo systemctl start $service"
    fi
}

# Check meshtasticd
echo "--- Meshtastic Daemon ---"
if systemctl is-active --quiet meshtasticd; then
    echo -e "${GREEN}✓${NC} meshtasticd is running"
else
    echo -e "${RED}✗${NC} meshtasticd is not running"
    echo "  Start command: sudo systemctl start meshtasticd"
fi

echo ""
echo "--- MQTT Broker ---"
check_service "mosquitto" "Mosquitto" "1883"

echo ""
echo "--- Node-RED ---"
check_service "nodered" "Node-RED" "1880"

echo ""
echo "--- InfluxDB ---"
check_service "influxdb" "InfluxDB" "8086"

echo ""
echo "--- Grafana ---"
check_service "grafana-server" "Grafana" "3000"

echo ""
echo "=========================================="
echo "MQTT Test"
echo "=========================================="

# Test MQTT connection
if command -v mosquitto_sub &> /dev/null; then
    echo "Listening for MQTT messages (5 seconds)..."
    echo "Topic: msh/#"
    timeout 5 mosquitto_sub -h localhost -t 'msh/#' -v 2>/dev/null || echo "(No messages or timeout)"
else
    echo "mosquitto_sub not installed, skipping MQTT test"
fi

echo ""
echo "=========================================="
echo "Port Listening Status"
echo "=========================================="

echo "MQTT (1883):"
ss -tlnp | grep :1883 || echo "  Not listening"

echo "Node-RED (1880):"
ss -tlnp | grep :1880 || echo "  Not listening"

echo "InfluxDB (8086):"
ss -tlnp | grep :8086 || echo "  Not listening"

echo "Grafana (3000):"
ss -tlnp | grep :3000 || echo "  Not listening"

echo ""
echo "=========================================="
echo "Quick Access Links"
echo "=========================================="
IP=$(hostname -I | awk '{print $1}')
echo "Node-RED:  http://$IP:1880"
echo "InfluxDB:  http://$IP:8086"
echo "Grafana:   http://$IP:3000"
