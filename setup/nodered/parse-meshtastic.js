// Meshtastic JSON 解析函数
// 用于 Node-RED Function 节点
// 解析来自 meshtasticd MQTT JSON 输出的数据

// 节点 ID 映射表 - 根据你的设备修改
// 格式: { decimal_node_id: "friendly_name" }
const NODE_MAP = {
    // 示例：将你的设备 ID 添加到这里
    // 可以通过 meshtastic --nodes 命令获取节点 ID
    // 12345678: "gateway",
    // 87654321: "sensor1",
};

// 获取节点名称
function getNodeName(fromId) {
    if (NODE_MAP[fromId]) {
        return NODE_MAP[fromId];
    }
    // 如果没有映射，使用节点 ID 的十六进制格式
    return "node_" + fromId.toString(16);
}

// 主解析逻辑
var node_id = getNodeName(msg.payload.from);
var new_payload = [];
msg.valid = true;

// 解析 Telemetry 数据
if (msg.payload.type === "telemetry") {
    var payload = msg.payload.payload;
    
    // 环境数据 (RAK1906 BME680)
    if (typeof payload.barometric_pressure !== "undefined" ||
        typeof payload.temperature !== "undefined" ||
        typeof payload.relative_humidity !== "undefined") {
        
        var fields = {};
        
        if (typeof payload.temperature !== "undefined") {
            fields.temperature = payload.temperature;
        }
        if (typeof payload.relative_humidity !== "undefined") {
            fields.humidity = payload.relative_humidity;
        }
        if (typeof payload.barometric_pressure !== "undefined") {
            fields.pressure = payload.barometric_pressure;
        }
        if (typeof payload.gas_resistance !== "undefined") {
            fields.gas_resistance = payload.gas_resistance;
        }
        if (typeof payload.iaq !== "undefined") {
            fields.iaq = payload.iaq;
        }
        if (typeof payload.lux !== "undefined") {
            fields.light = payload.lux;
        }
        if (typeof payload.uv_lux !== "undefined") {
            fields.uv_light = payload.uv_lux;
        }
        
        new_payload.push({
            measurement: node_id + "_env",
            fields: fields,
            timestamp: new Date().getTime()
        });
        msg.payload = new_payload;
        msg.dataType = "environment";
    }
    // 设备数据（电池、电压等）
    else if (typeof payload.battery_level !== "undefined" ||
             typeof payload.voltage !== "undefined") {
        
        var fields = {};
        
        if (typeof payload.battery_level !== "undefined" && payload.battery_level > 0) {
            fields.battery_level = payload.battery_level;
        }
        if (typeof payload.voltage !== "undefined" && payload.voltage > 0) {
            fields.voltage = payload.voltage;
        }
        if (typeof payload.channel_utilization !== "undefined") {
            fields.channel_utilization = payload.channel_utilization;
        }
        if (typeof payload.air_util_tx !== "undefined") {
            fields.air_util_tx = payload.air_util_tx;
        }
        if (typeof payload.uptime_seconds !== "undefined") {
            fields.uptime = payload.uptime_seconds;
        }
        
        if (Object.keys(fields).length > 0) {
            new_payload.push({
                measurement: node_id + "_device",
                fields: fields,
                timestamp: new Date().getTime()
            });
            msg.payload = new_payload;
            msg.dataType = "device";
        } else {
            msg.valid = false;
        }
    }
    // 颗粒物数据
    else if (typeof payload.pm10 !== "undefined") {
        new_payload.push({
            measurement: node_id + "_air",
            fields: {
                pm10: payload.pm10,
                pm25: payload.pm25,
                pm100: payload.pm100,
                pm10_e: payload.pm10_e || 0,
                pm25_e: payload.pm25_e || 0,
                pm100_e: payload.pm100_e || 0
            },
            timestamp: new Date().getTime()
        });
        msg.payload = new_payload;
        msg.dataType = "air_quality";
    }
    // Host Metrics (meshtasticd 特有)
    else if (typeof payload.uptime_seconds !== "undefined" &&
             typeof payload.freemem_bytes !== "undefined") {
        new_payload.push({
            measurement: node_id + "_host",
            fields: {
                uptime: payload.uptime_seconds,
                freemem: payload.freemem_bytes,
                diskfree: payload.diskfree1_bytes || 0,
                load1: (payload.load1 || 0) / 100,
                load5: (payload.load5 || 0) / 100,
                load15: (payload.load15 || 0) / 100
            },
            timestamp: new Date().getTime()
        });
        msg.payload = new_payload;
        msg.dataType = "host_metrics";
    }
    else {
        msg.valid = false;
    }
}
// 解析位置数据
else if (msg.payload.type === "position") {
    var payload = msg.payload.payload;
    
    if (typeof payload.latitude_i !== "undefined" &&
        typeof payload.longitude_i !== "undefined") {
        
        var latitude = payload.latitude_i / 10000000;
        var longitude = payload.longitude_i / 10000000;
        var altitude = payload.altitude || 0;
        
        var fields = {
            latitude: latitude,
            longitude: longitude,
            altitude: altitude
        };
        
        // 添加额外的GPS信息
        if (typeof payload.PDOP !== "undefined") {
            fields.pdop = payload.PDOP / 100; // PDOP通常需要除以100
        }
        if (typeof payload.ground_track !== "undefined") {
            fields.ground_track = payload.ground_track / 10000; // 转换为度数
        }
        if (typeof payload.sats_in_view !== "undefined") {
            fields.sats_in_view = payload.sats_in_view;
        }
        if (typeof payload.precision_bits !== "undefined") {
            fields.precision_bits = payload.precision_bits;
        }
        
        new_payload.push({
            measurement: node_id + "_position",
            fields: fields,
            timestamp: new Date().getTime()
        });
        msg.payload = new_payload;
        msg.dataType = "position";
    } else {
        msg.valid = false;
    }
}
// 节点信息
else if (msg.payload.type === "nodeinfo") {
    // 可选：记录节点信息
    msg.valid = false; // 默认不存储到数据库
}
// 其他类型
else {
    msg.valid = false;
}

return msg;
