//
//  Sensors.swift
//  thermod
//
//  Temperature and power sensor reading. Die-sensor key catalogs per Apple
//  Silicon generation are community-documented facts, collected from
//  agoodkind/macos-smc-fan (MIT), the Asahi Linux SMC docs, and the Linux
//  macsmc-hwmon driver.
//

import Foundation

enum SensorGroup: String {
    case cpu = "cpu"
    case gpu = "gpu"
    case memory = "memory"
    case system = "system"
}

struct SensorKey {
    let key: String
    let name: String
    let group: SensorGroup
}

enum SensorCatalog {
    // Legacy / cross-platform keys (mostly Intel; harmless to probe on AS)
    static let crossPlatform: [SensorKey] = [
        SensorKey(key: "TC0D", name: "CPU diode", group: .cpu),
        SensorKey(key: "TC0E", name: "CPU virtual", group: .cpu),
        SensorKey(key: "TC0F", name: "CPU filtered", group: .cpu),
        SensorKey(key: "TC0P", name: "CPU proximity", group: .cpu),
        SensorKey(key: "TCAD", name: "CPU package", group: .cpu),
        SensorKey(key: "TG0D", name: "GPU diode", group: .gpu),
        SensorKey(key: "TG0P", name: "GPU proximity", group: .gpu),
        SensorKey(key: "Tm0P", name: "Mainboard", group: .system),
        SensorKey(key: "TB1T", name: "Battery", group: .system),
    ]

    static let m1: [SensorKey] = [
        SensorKey(key: "Tp09", name: "CPU E-core 1", group: .cpu),
        SensorKey(key: "Tp0T", name: "CPU E-core 2", group: .cpu),
        SensorKey(key: "Tp01", name: "CPU P-core 1", group: .cpu),
        SensorKey(key: "Tp05", name: "CPU P-core 2", group: .cpu),
        SensorKey(key: "Tp0D", name: "CPU P-core 3", group: .cpu),
        SensorKey(key: "Tp0H", name: "CPU P-core 4", group: .cpu),
        SensorKey(key: "Tp0L", name: "CPU P-core 5", group: .cpu),
        SensorKey(key: "Tp0P", name: "CPU P-core 6", group: .cpu),
        SensorKey(key: "Tp0X", name: "CPU P-core 7", group: .cpu),
        SensorKey(key: "Tp0b", name: "CPU P-core 8", group: .cpu),
        SensorKey(key: "Tg05", name: "GPU 1", group: .gpu),
        SensorKey(key: "Tg0D", name: "GPU 2", group: .gpu),
        SensorKey(key: "Tg0L", name: "GPU 3", group: .gpu),
        SensorKey(key: "Tg0T", name: "GPU 4", group: .gpu),
        SensorKey(key: "Tm02", name: "Memory 1", group: .memory),
        SensorKey(key: "Tm06", name: "Memory 2", group: .memory),
        SensorKey(key: "Tm08", name: "Memory 3", group: .memory),
        SensorKey(key: "Tm09", name: "Memory 4", group: .memory),
    ]

    static let m2: [SensorKey] = [
        SensorKey(key: "Tp1h", name: "CPU E-core 1", group: .cpu),
        SensorKey(key: "Tp1t", name: "CPU E-core 2", group: .cpu),
        SensorKey(key: "Tp1p", name: "CPU E-core 3", group: .cpu),
        SensorKey(key: "Tp1l", name: "CPU E-core 4", group: .cpu),
        SensorKey(key: "Tp01", name: "CPU P-core 1", group: .cpu),
        SensorKey(key: "Tp05", name: "CPU P-core 2", group: .cpu),
        SensorKey(key: "Tp09", name: "CPU P-core 3", group: .cpu),
        SensorKey(key: "Tp0D", name: "CPU P-core 4", group: .cpu),
        SensorKey(key: "Tp0X", name: "CPU P-core 5", group: .cpu),
        SensorKey(key: "Tp0b", name: "CPU P-core 6", group: .cpu),
        SensorKey(key: "Tp0f", name: "CPU P-core 7", group: .cpu),
        SensorKey(key: "Tp0j", name: "CPU P-core 8", group: .cpu),
        SensorKey(key: "Tg0f", name: "GPU 1", group: .gpu),
        SensorKey(key: "Tg0j", name: "GPU 2", group: .gpu),
    ]

    static let m3: [SensorKey] = [
        SensorKey(key: "Te05", name: "CPU E-core 1", group: .cpu),
        SensorKey(key: "Te0L", name: "CPU E-core 2", group: .cpu),
        SensorKey(key: "Te0P", name: "CPU E-core 3", group: .cpu),
        SensorKey(key: "Te0S", name: "CPU E-core 4", group: .cpu),
        SensorKey(key: "Tf04", name: "CPU P-core 1", group: .cpu),
        SensorKey(key: "Tf09", name: "CPU P-core 2", group: .cpu),
        SensorKey(key: "Tf0A", name: "CPU P-core 3", group: .cpu),
        SensorKey(key: "Tf0B", name: "CPU P-core 4", group: .cpu),
        SensorKey(key: "Tf0D", name: "CPU P-core 5", group: .cpu),
        SensorKey(key: "Tf0E", name: "CPU P-core 6", group: .cpu),
        SensorKey(key: "Tf44", name: "CPU P-core 7", group: .cpu),
        SensorKey(key: "Tf49", name: "CPU P-core 8", group: .cpu),
        SensorKey(key: "Tf4A", name: "CPU P-core 9", group: .cpu),
        SensorKey(key: "Tf4B", name: "CPU P-core 10", group: .cpu),
        SensorKey(key: "Tf4D", name: "CPU P-core 11", group: .cpu),
        SensorKey(key: "Tf4E", name: "CPU P-core 12", group: .cpu),
        SensorKey(key: "Tf14", name: "GPU 1", group: .gpu),
        SensorKey(key: "Tf18", name: "GPU 2", group: .gpu),
        SensorKey(key: "Tf19", name: "GPU 3", group: .gpu),
        SensorKey(key: "Tf1A", name: "GPU 4", group: .gpu),
        SensorKey(key: "Tf24", name: "GPU 5", group: .gpu),
        SensorKey(key: "Tf28", name: "GPU 6", group: .gpu),
        SensorKey(key: "Tf29", name: "GPU 7", group: .gpu),
        SensorKey(key: "Tf2A", name: "GPU 8", group: .gpu),
    ]

    static let m4: [SensorKey] = [
        SensorKey(key: "Te05", name: "CPU E-core 1", group: .cpu),
        SensorKey(key: "Te0S", name: "CPU E-core 2", group: .cpu),
        SensorKey(key: "Te09", name: "CPU E-core 3", group: .cpu),
        SensorKey(key: "Te0H", name: "CPU E-core 4", group: .cpu),
        SensorKey(key: "Tp01", name: "CPU P-core 1", group: .cpu),
        SensorKey(key: "Tp05", name: "CPU P-core 2", group: .cpu),
        SensorKey(key: "Tp09", name: "CPU P-core 3", group: .cpu),
        SensorKey(key: "Tp0D", name: "CPU P-core 4", group: .cpu),
        SensorKey(key: "Tp0V", name: "CPU P-core 5", group: .cpu),
        SensorKey(key: "Tp0Y", name: "CPU P-core 6", group: .cpu),
        SensorKey(key: "Tp0b", name: "CPU P-core 7", group: .cpu),
        SensorKey(key: "Tp0e", name: "CPU P-core 8", group: .cpu),
        SensorKey(key: "Tg1U", name: "GPU 1", group: .gpu),
        SensorKey(key: "Tg1k", name: "GPU 2", group: .gpu),
        SensorKey(key: "Tg0K", name: "GPU 3", group: .gpu),
        SensorKey(key: "Tg0L", name: "GPU 4", group: .gpu),
        SensorKey(key: "Tg0d", name: "GPU 5", group: .gpu),
        SensorKey(key: "Tg0e", name: "GPU 6", group: .gpu),
        SensorKey(key: "Tg0j", name: "GPU 7", group: .gpu),
        SensorKey(key: "Tg0k", name: "GPU 8", group: .gpu),
        SensorKey(key: "Tm0p", name: "Memory 1", group: .memory),
        SensorKey(key: "Tm1p", name: "Memory 2", group: .memory),
        SensorKey(key: "Tm2p", name: "Memory 3", group: .memory),
    ]

    static let m5: [SensorKey] = [
        SensorKey(key: "Tp00", name: "CPU S-core 1", group: .cpu),
        SensorKey(key: "Tp04", name: "CPU S-core 2", group: .cpu),
        SensorKey(key: "Tp08", name: "CPU S-core 3", group: .cpu),
        SensorKey(key: "Tp0C", name: "CPU S-core 4", group: .cpu),
        SensorKey(key: "Tp0G", name: "CPU S-core 5", group: .cpu),
        SensorKey(key: "Tp0K", name: "CPU S-core 6", group: .cpu),
        SensorKey(key: "Tp0O", name: "CPU P-core 1", group: .cpu),
        SensorKey(key: "Tp0R", name: "CPU P-core 2", group: .cpu),
        SensorKey(key: "Tp0U", name: "CPU P-core 3", group: .cpu),
        SensorKey(key: "Tp0X", name: "CPU P-core 4", group: .cpu),
        SensorKey(key: "Tp0a", name: "CPU P-core 5", group: .cpu),
        SensorKey(key: "Tp0d", name: "CPU P-core 6", group: .cpu),
        SensorKey(key: "Tp0g", name: "CPU P-core 7", group: .cpu),
        SensorKey(key: "Tp0j", name: "CPU P-core 8", group: .cpu),
        SensorKey(key: "Tp0m", name: "CPU P-core 9", group: .cpu),
        SensorKey(key: "Tp0p", name: "CPU P-core 10", group: .cpu),
        SensorKey(key: "Tp0u", name: "CPU P-core 11", group: .cpu),
        SensorKey(key: "Tp0y", name: "CPU P-core 12", group: .cpu),
        SensorKey(key: "Tg0U", name: "GPU 1", group: .gpu),
        SensorKey(key: "Tg0X", name: "GPU 2", group: .gpu),
        SensorKey(key: "Tg0d", name: "GPU 3", group: .gpu),
        SensorKey(key: "Tg0g", name: "GPU 4", group: .gpu),
        SensorKey(key: "Tg0j", name: "GPU 5", group: .gpu),
        SensorKey(key: "Tg1Y", name: "GPU 6", group: .gpu),
        SensorKey(key: "Tg1c", name: "GPU 7", group: .gpu),
        SensorKey(key: "Tg1g", name: "GPU 8", group: .gpu),
    ]

    static let power: [SensorKey] = [
        SensorKey(key: "PSTR", name: "System total", group: .system),
        SensorKey(key: "PDTR", name: "DC in", group: .system),
        SensorKey(key: "PPBR", name: "Battery", group: .system),
        SensorKey(key: "PCTR", name: "CPU total", group: .cpu),
    ]

    static func forModel(_ model: String) -> [SensorKey] {
        let generation: [SensorKey]
        if model.hasPrefix("Mac17") {
            generation = m5
        } else if model.hasPrefix("Mac16") {
            generation = m4
        } else if model.hasPrefix("Mac15") || model.hasPrefix("Mac14") {
            generation = m3
        } else if model.hasPrefix("Mac13") {
            generation = m2
        } else if model.hasPrefix("Mac12") || model.hasPrefix("MacBookPro18")
            || model.hasPrefix("MacBookAir10") {
            generation = m1
        } else {
            generation = []
        }
        return generation + crossPlatform
    }
}

// MARK: - Reader

struct TemperatureReading {
    let key: String
    let name: String
    let group: SensorGroup
    let celsius: Float
}

final class Sensors {
    private let smc: SMCConnection
    /// Keys that answered plausibly at least once; probed on first read.
    private var activeKeys: [SensorKey]?
    private let catalog: [SensorKey]

    init(smc: SMCConnection) {
        self.smc = smc
        catalog = SensorCatalog.forModel(hardwareModel())
    }

    private static func plausible(_ celsius: Float) -> Bool {
        celsius > 1.0 && celsius < 130.0
    }

    func readTemperatures() -> [TemperatureReading] {
        let keys = activeKeys ?? catalog
        var readings: [TemperatureReading] = []
        var alive: [SensorKey] = []
        for sensor in keys {
            guard let value = try? smc.readFloat(sensor.key), Self.plausible(value) else {
                continue
            }
            alive.append(sensor)
            readings.append(TemperatureReading(
                key: sensor.key, name: sensor.name, group: sensor.group, celsius: value
            ))
        }
        if activeKeys == nil { activeKeys = alive }
        return readings
    }

    func maxTemperature(_ readings: [TemperatureReading], group: SensorGroup? = nil) -> Float? {
        let filtered = group.map { g in readings.filter { $0.group == g } } ?? readings
        return filtered.map(\.celsius).max()
    }

    func readPowerWatts() -> [String: Float] {
        var result: [String: Float] = [:]
        for sensor in SensorCatalog.power {
            if let value = try? smc.readFloat(sensor.key), value >= 0, value < 1000 {
                result[sensor.key] = value
            }
        }
        return result
    }
}
