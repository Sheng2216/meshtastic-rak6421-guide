# Meshtastic Environment Monitoring System with RAK6421 WisMesh Pi HAT

Transform your Raspberry Pi 4B/5 + RAK 6421 WisMesh Pi HAT + RAK Wisblock sensors into a complete environment monitoring station with real-time visualization.

![Grafana Dashboard](assets/grafana_dashboard_measurements.png)

## 1) Project Overview

### What This Guide Provides

This guide explains how to build a complete environmental monitoring station on a Raspberry Pi using Meshtasticd, MQTT, Node-RED, InfluxDB, and Grafana.

You will get:
- Environment telemetry collection (temperature, humidity, pressure, air quality)
- GPS location services
- Real-time Grafana dashboards
- MQTT integration for automation
- Historical storage in InfluxDB

If you only want basic Meshtastic messaging (without monitoring stack), you can stop at HAT + radio assembly and use Meshtastic web/mobile app directly.

### Data Flow (High-Level)

This project follows a simple chain:

`Sensors -> meshtasticd -> MQTT (Mosquitto) -> Node-RED -> InfluxDB -> Grafana`

```text
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   RAK1906/1901  │────▶│   meshtasticd   │────▶│   Mosquitto     │
│   Environment   │ I2C │        Daemon   │MQTT │   MQTT Broker   │
│     Sensors     │     │                 │     │   Port 1883     │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│     Grafana     │◀────│    InfluxDB     │◀────│    Node-RED     │
│  Visualization  │Query│  Time-series DB │Write│   JSON Parser   │
│   Port 3000     │     │   Port 8086     │     │   Port 1880     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

---

## 2) Hardware Preparation

![RAK6421 Pi HAT](assets/RAK6421.jpg)

### RAK6421 Role in This Build

The RAK6421 WisMesh Pi HAT is the hardware integration layer for Raspberry Pi Meshtastic nodes:
- **Hardware layer:** connects Pi GPIO to LoRa radio module and I2C sensors
- **Software layer:** works with `meshtasticd` on Linux
- **Gateway layer:** can forward telemetry into MQTT/Node-RED/InfluxDB/Grafana

### Assembly

To assemble the board on top of Raspberry Pi:
- Mount modules/sensors to the HAT first and secure with screws
- Connect antennas before mounting the HAT
- Keep host powered off and unplugged during assembly
- Use spacers to keep proper distance/alignment between boards

![RAK6421 Pi HAT assembly](assets/rak6421-assembly.png)

### Slot Layout

The RAK6421 WisBlock Pi HAT provides **2 IO slots** and **4 sensor slots**:
- **IO Slots (1 & 2):** LoRa radio modules such as **RAK13300** or **RAK13302**
- **Sensor Slot A:** larger slot for **RAK12501** / **RAK12500** GNSS module
- **Sensor Slots B/C/D:** environmental sensors such as **RAK1901**, **RAK1906**

> **Note:** Slot pin layouts differ. See the [RAK6421 WisBlock Pi HAT Datasheet](https://docs.rakwireless.com/product-categories/wishat/rak6421-wisblock-pi-hat/datasheet/#schematics).

### Meshtasticd-Supported WisBlock Modules
> **Compatibility note:** This document targets **meshtasticd 2.7.15 only**. RAK1906 and RAK1901 sensors are not yet fully supported in this version. Before starting, run:
> `sudo cp /etc/meshtasticd/available.d/lora-RAK6421-13300-slot1.yaml /etc/meshtasticd/config.d/`
>
> The examples use **RAK12019** as reference hardware (supported in 2.7.15). The guide will be updated once Meshtasticd adds full RAK1906/RAK1901 support.
The following WisBlock modules have been tested and work with meshtasticd (as of version 2.7.17). We will update this list as new versions are released:

| RAK Name   | Chip / Component   | Measures              | Status  |
|------------|--------------------|-----------------------|---------|
| RAK13000   | Semtech SX1262  | LoRa module            | Yes     |
| RAK13002   | Semtech SX1262, SKY66122 signal booster | LoRa module           | Yes     |
| RAK12002   | Micro Crystal RV-3028-C7 | RTC             | Yes     |
| RAK12003   | Melexis MLX90632   | IR Temperature        | Yes     |
| RAK12019   | Lite On LTR-390UV-01 | UV sensor           | Yes     |
| RAK12020   | AMS TSL25911FN     | Ambient light         | Yes     |
| RAK12034   | BMX160             | 9-axis Accelerometer  | Yes     |
| RAK12037   | Sensirion SCD30    | CO2                   | PR ongoing |
| RAK12500   | u-blox ZOE-M8Q     | GNSS GPS Location         | Yes |
| RAK12501   | Quectel L76K   |  GNSS GPS Location         | Yes |
| RAK1902    | STMicro LPS22HB    | Barometric Pressure   | Release soon     |
| RAK1901    | Sensirion SHTC3   | Temp, Humidity   | Release soon    |
| RAK1906    | BME680             | Temperature, Humidity, Pressure, VOC gas sensing | Release soon     |

### HAT EEPROM Auto-Discovery

RAK6421 includes onboard EEPROM so meshtasticd can auto-detect board info.
If you use your own Raspberry Pi image, ensure EEPROM detection is enabled in `/boot/firmware/config.txt`:

```bash
# Enable I2C-0 bus for HAT EEPROM
dtparam=i2c_vc=on
dtoverlay=i2c0
```

A reboot is required. If you use the [RAKwireless-provided image](https://github.com/Sheng2216/meshtastic-rak6421-guide/releases), this is already configured, you can ignore this.

---

## 3) Software Preparation

### Get the Repository

Clone this project first:

```bash
git clone https://github.com/Sheng2216/meshtastic-rak6421-guide.git
cd meshtastic-rak6421-guide
```

If `git` is not installed, install it first:

```bash
sudo apt update
sudo apt install -y git
```

### Prerequisites

| Requirement | Details |
|-------------|---------|
| **Hardware** | Raspberry Pi 4 or Raspberry Pi 5 |
| **Raspberry Pi Image** | See [Base image options](#base-image-options) below |
| **Hat** | RAK6421 WisMesh Pi HAT|
| **Sensors and radio module** | RAK1906 (BME680) + RAK1901 (SHTC3) + RAK13300/RAK13302 |

### Base Image Options

You can run this guide on any Linux image that has meshtasticd installed and working with the RAK6421 WisMesh Pi HAT:

| Option | Description |
|--------|-------------|
| **Meshtastic Linux docs** | Follow the [meshtasticd Linux installation](https://meshtastic.org/docs/software/linux/installation/) to install meshtasticd on your preferred distro (e.g. Raspberry Pi OS). You manage the base system yourself. |
| **mPWRD OS (Armbian)** | Build a custom Armbian image with Meshtastic integration using [mPWRD-userpatches](https://github.com/mPWRD-OS/mPWRD-userpatches) (Armbian + Meshtastic). Use `config-raspberry-pi-64bit.conf` for Raspberry Pi. |
| **RAKwireless image** | Use the dedicated [firmware from RAKwireless](https://github.com/Sheng2216/meshtastic-rak6421-guide/releases) (based on [pi-gen](https://github.com/RPi-Distro/pi-gen)), which includes meshtasticd and is ready for RAK6421. |

This guide assumes meshtasticd is already running. Installation scripts then add Mosquitto, Node-RED, InfluxDB, and Grafana.

---

## 4) Pre-Installation Check

### Verify LoRa Radio (Before Installation)

Before running installation scripts, confirm the following:
1. LoRa radio module (RAK13300/RAK13302) is enabled and working
2. You can query and control the node from at least one client (web, mobile app, or CLI)

This check ensures hardware and base meshtasticd setup are healthy before adding monitoring services.

### Verification Methods (Choose One or More)

You can verify node connectivity using any of the methods below.

#### Method A: Meshtastic Web Client

1. Open Meshtastic web client from a device in the same LAN: `https://<Pi-IP>:9443`
2. Click **"+ New Connection"**

   ![Meshtastic Web Client - Add Device](assets/meshtastic_web_client_add_device.png)

3. Select **HTTP**, enter `<Pi-IP>:9443`, then click **Connect**

   ![Meshtastic Web Client - Connect](assets/meshtastic_web_client_connect_to_new_device.png)

4. Go to **Config** -> **Radio Config** -> **LoRa** to verify settings

   ![Meshtastic Web Client - Radio Config](assets/meshtastic_web_client_radio_config.png)

#### Method B: Meshtastic Mobile App

Connect from the Meshtastic mobile app using the Pi IP address. Ensure phone and Pi are on the same LAN.

#### Method C: Meshtastic Python CLI

Run the following command on the Pi:

```bash
meshtastic --info
```

If the command returns node information successfully, the LoRa radio is reachable and working.

---

## 5) Choose an Installation Path

- Use [Quick Start (One-Command Installation)](#quick-start-one-command-installation) for the fastest setup
- Use [Detailed Installation Steps](#detailed-installation-steps) for step-by-step control

   Both paths continue with:
- [Post-Installation Configuration](#post-installation-configuration)
- [Verify Installation](#verify-installation)

---

## Quick Start (One-Command Installation)

The fastest way to get started is to run the complete installation script:

```bash
cd setup/scripts
./install-all.sh
```

This script will install all components in the correct order and takes approximately 20-30 minutes (depending on your network speed).
> **Tip:** Before running installation scripts, you can customize InfluxDB and Grafana's credentials in `setup/config/credentials.env`
```bash
# InfluxDB Configuration
INFLUXDB_USERNAME="admin"
INFLUXDB_PASSWORD="your_secure_password"
INFLUXDB_ORG="meshtastic"
INFLUXDB_BUCKET="meshtastic"

# Grafana Configuration
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASSWORD="your_secure_password"
```
---

## Detailed Installation Steps

If you prefer to install components individually or need more control, follow these steps:

### Step 1: Configure Serial Port (Optional)

```bash
cd setup/scripts
./01-configure-serial.sh
```

This configures the serial port for the Meshtastic GPS module (UART enabled, serial console disabled) and also updates `/etc/meshtasticd/config.yaml` by **uncommenting** common required lines (only if they are currently commented), including:
- `GPS.SerialPath`: The script automatically detects your Raspberry Pi version and sets the correct device:
  - **Raspberry Pi 5**: `/dev/ttyAMA0`
  - **Raspberry Pi 4**: `/dev/ttyS0`
- `I2C.I2CDevice: /dev/i2c-1`
- `Webserver.Port: 9443`

A reboot is required for changes to take effect.

> **Important for Manual Configuration:** If you prefer to edit `/etc/meshtasticd/config.yaml` manually instead of running this script, note that the GPS serial path differs between Raspberry Pi models:
> - **Raspberry Pi 5**: Use `SerialPath: /dev/ttyAMA0`
> - **Raspberry Pi 4**: Use `SerialPath: /dev/ttyS0`

If you'd rather make these edits yourself, see [`config.yaml`](./config.yaml) in this repository for an example configuration.

Each of the following service scripts (Mosquitto, InfluxDB, Node-RED, Grafana) installs its own dependencies when run standalone, so you can run any step independently.

### Step 2: Install Mosquitto MQTT Broker

```bash
./02-install-mosquitto.sh
```

The MQTT broker receives messages from meshtasticd on port 1883.

> **Note:** Install the MQTT broker first before configuring telemetry settings. The Meshtastic device needs a working MQTT broker connection to successfully apply MQTT-related configurations.

### Step 3: Configure Telemetry & MQTT

```bash
./03-configure-telemetry.sh
```

This script will use the Meshtastic Python CLI to configure:
- Environment telemetry (sensor data collection)
- GPS/position mode and broadcast settings
- MQTT: enabled, broker address (default `localhost`), JSON output enabled
- Channel 0 uplink enabled (required for MQTT publishing)

> **Important:** Before running this script, ensure your MQTT broker is running and accessible. The script will configure MQTT settings on your Meshtastic device, which requires a working MQTT connection. If you use a remote MQTT broker instead of the local one from Step 2, edit the script to set the correct MQTT address, or configure it manually as described below.

**If you configure manually** (via the Meshtastic web client, mobile app, or Python CLI instead of this script), you must enable the same options:
- **MQTT:** enable MQTT, set the broker address (e.g. `localhost` or your remote broker), enable JSON packets
- **Channel 0:** enable uplink for the primary channel (e.g. with the CLI: `meshtastic --ch-set uplink_enabled true --ch-index 0`)
- **Telemetry:** enable environment measurement and set update interval as needed
- **Position:** set GPS mode and position broadcast options as needed 

### Step 4: Install InfluxDB

```bash
./04-install-influxdb.sh
```

This script installs InfluxDB as a system service, creates the organization and bucket for Meshtastic data, and configures the admin account. Node-RED will write telemetry to this database; Grafana will read from it.

Default configuration:
| Setting | Value |
|---------|-------|
| Username | admin |
| Password | meshtastic |
| Organization | meshtastic |
| Bucket | meshtastic |

> **Note:** You can customize these in `config/credentials.env` before installation.

### Step 5: Install Node-RED

```bash
./05-install-nodered.sh
```

This script installs Node.js (20 LTS) and Node-RED using the official installer, applies the project’s custom [settings.js](setup/nodered/settings.js), and enables the Node-RED system service. After installation you will configure the InfluxDB token in Node-RED (see [Post-Installation Configuration](#post-installation-configuration)).

> **Important:** This step takes 20-30 minutes on slower Pi models.

### Step 6: Install Grafana

```bash
./06-install-grafana.sh
```

This script adds the Grafana APT repository, installs Grafana, enables the service, and provisions the InfluxDB data source. A pre-configured dashboard is deployed so you can view Meshtastic data without manual setup: it displays **environment telemetry** (temperature, humidity, pressure, air quality / IAQ, light and UV) and **GPS/position** (satellite count, PDOP, track, and map). After installation, open **Dashboards** → **Meshtastic** → **Meshtastic Environment Monitor** in Grafana. The dashboard definition is in [setup/grafana/dashboard.json](setup/grafana/dashboard.json) if you want to customize or inspect it.

Default configuration:
| Setting | Value |
|---------|-------|
| Admin user | admin |
| Admin password | admin |

> **Note:** You can customize these in `config/credentials.env` before installation. 

---

## Post-Installation Configuration

### Configure Node-RED InfluxDB Token

After installation, you need to configure the InfluxDB token in Node-RED:

**1. Get the token:**
```bash
./show-token.sh
```

**2. Open Node-RED** at `http://<Pi-IP>:1880` (from any device on your LAN)

**3. Double-click the "Write to InfluxDB" node:**

![Edit InfluxDB Node](assets/edit_influxdb_node.png)

**4. Click the pencil icon next to "Local InfluxDB" and paste the token:**

![Enter Token](assets/enter_token.png)

**5. Click "Update", then "Done", then click "Deploy":**

![Deploy Flow](assets/deploy_flow.png)

---

## Verify Installation

### Check Service Status

```bash
rak@rakpios:~/setup/scripts $ ./check-services.sh 
==========================================
Meshtastic Monitoring System Service Status
==========================================

--- Meshtastic Daemon ---
✓ meshtasticd is running

--- MQTT Broker ---
✓ Mosquitto is running
  URL: http://<Pi-IP>:1883

--- Node-RED ---
✓ Node-RED is running
  URL: http://<Pi-IP>:1880

--- InfluxDB ---
✓ InfluxDB is running
  URL: http://<Pi-IP>:8086

--- Grafana ---
✓ Grafana is running
  URL: http://<Pi-IP>:3000

==========================================
MQTT Test
==========================================
mosquitto_sub not installed, skipping MQTT test

==========================================
Port Listening Status
==========================================
MQTT (1883):
LISTEN 0      100          0.0.0.0:1883      0.0.0.0:*                                       
Node-RED (1880):
LISTEN 0      511          0.0.0.0:1880      0.0.0.0:*    users:(("node-red",pid=2839,fd=19))
InfluxDB (8086):
LISTEN 0      4096               *:8086            *:*                                       
Grafana (3000):
LISTEN 0      4096               *:3000            *:*                                       

==========================================
Quick Access Links
==========================================
Node-RED:  http://10.2.13.62:1880
InfluxDB:  http://10.2.13.62:8086
Grafana:   http://10.2.13.62:3000
```

### Access URLs

Access these services from any device on your LAN using `http://<Pi-IP>:<port>`, where `<Pi-IP>` is your Raspberry Pi's IP address.

| Service | URL | Default Login |
|---------|-----|---------------|
| Node-RED | `http://<Pi-IP>:1880` | - |
| InfluxDB | `http://<Pi-IP>:8086` | admin / meshtastic |
| Grafana | `http://<Pi-IP>:3000` | admin / admin |

### View Dashboard

1. Open Grafana at `http://<Pi-IP>:3000`
2. Login with admin / admin
3. Navigate to **Dashboards** → **Meshtastic** folder
4. Click **Meshtastic Environment Monitor**

![Grafana Dashboard](assets/grafana_dashboard.png)




---

## Troubleshooting

### No MQTT Messages?

1. Check if meshtasticd is running:
   ```bash
   systemctl status meshtasticd
   ```

2. Verify MQTT is enabled:
   ```bash
   meshtastic --get mqtt.enabled
   ```

3. Test MQTT subscription (run on the Pi or from another machine on the LAN):
   ```bash
   mosquitto_sub -h <Pi-IP> -t 'msh/#' -v
   ```

### Node-RED Can't Connect to InfluxDB?

1. Verify InfluxDB is running:
   ```bash
   systemctl status influxdb
   ```

2. Check the token is correct in Node-RED

3. Verify organization name matches (default: "meshtastic")

### Grafana Shows No Data?

1. Check data source configuration:
   - Go to **Connections** → **Data Sources** → **InfluxDB**
   - Click **Save & Test**

2. Verify data is being written:
   - Open InfluxDB UI at `http://<Pi-IP>:8086`
   - Go to **Data Explorer**
   - Query the "meshtastic" bucket
   ![InfluxDB data explorer](assets/influxdb_data_explorer.png)

3. Check Node-RED debug output for errors

### Sensor Data Not Updating?

1. Check sensor connection:
   ```bash
   i2cdetect -y 1
   ```
   Should show address 0x76 for RAK1906（BME680）and 0x70 for RAK1901(SHTC3)

2. View meshtasticd logs:
   ```bash
   journalctl -u meshtasticd -f
   ```

### GPS Module Not Working?

Use minicom to check whether the GPS is outputting NMEA data on the serial port (install minicom if needed):

1. Install minicom:
   ```bash
   sudo apt-get install -y minicom
   ```

2. Connect to the GPS serial device at 9600 baud. Use the device that matches your Pi and setup:
   - **Raspberry Pi 4:** `/dev/ttyS0`
   - **Raspberry Pi 5:** `/dev/ttyAMA0`

   ```bash
   sudo minicom -D /dev/ttyS0 -b 9600
   ```
   Replace `/dev/ttyS0` with `/dev/ttyAMA0` as appropriate.

3. You should see NMEA sentences (lines starting with `$GP...`) if the GPS is working. Exit minicom with **Ctrl+A**, then **Z** (Opens the Help Screen),**Q** (quit), and finally **Enter**.

### Service Management

```bash
# Restart all services
sudo systemctl restart mosquitto nodered influxdb grafana-server

# View logs
journalctl -u meshtasticd -f
journalctl -u nodered -f
...

# Check status
setup/scripts/check-services.sh
```

---


## References

- [meshtasticd Linux installation](https://meshtastic.org/docs/software/linux/installation/)
- [Meshtastic Web client](https://meshtastic.org/docs/software/web-client/)
- [Meshtastic Python CLI](https://meshtastic.org/docs/software/python/cli/)
- [Meshtastic Position Configuration](https://meshtastic.org/docs/configuration/radio/position/)
- [Meshtastic Telemetry Configuration](https://meshtastic.org/docs/configuration/module/telemetry/)
- [meshtasticd MQTT Configuration](https://meshtastic.org/docs/configuration/module/mqtt/)


