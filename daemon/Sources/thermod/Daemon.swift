//
//  Daemon.swift
//  thermod
//
//  Control state, request handling, and the safety loop.
//
//  Safety invariants live HERE, in root-owned code — never in the MCP layer
//  that an LLM talks to:
//    1. Dead-man switch: every manual request carries a TTL. When it expires
//       (or the daemon exits) fans revert to system control.
//    2. Thermal failsafe: if any die sensor crosses FAILSAFE_TEMP while under
//       manual control, the daemon abandons manual mode and returns fans to
//       the system, regardless of what was requested.
//    3. RPM clamping: requested targets are clamped to the fan's reported
//       [min, max] range.
//    4. Wake/reclaim recovery: firmware resets Ftst across sleep; the loop
//       re-asserts manual mode if it is still supposed to be active.
//

import Foundation

final class Daemon {
    // Hardcoded safety policy — intentionally not configurable over the socket.
    static let failsafeTempC: Float = 102.0
    static let defaultTtl: TimeInterval = 900       // 15 min
    static let maxTtl: TimeInterval = 7200          // 2 h
    static let tickInterval: TimeInterval = 2.0

    private struct ManualState {
        var targets: [Int: Float]   // fan index -> requested (clamped) rpm
        var expiresAt: Date
        var strategy: ControlStrategy
    }

    private let smc: SMCConnection
    private let fans: FanControl
    private let sensors: Sensors
    private let lock = NSLock()
    private var manual: ManualState?
    private var lastRevert: [String: Any]?

    init() throws {
        smc = try SMCConnection()
        fans = FanControl(smc: smc)
        sensors = Sensors(smc: smc)
        log("thermod started model=\(hardwareModel()) fans=\(fans.fanCount) " +
            "modeKey=\(fans.modeKeyFormat) ftst=\(fans.ftstAvailable)")
    }

    // MARK: - Request handling

    func handle(_ data: Data) -> Data {
        let response: [String: Any]
        do {
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let request = json as? [String: Any],
                  let cmd = request["cmd"] as? String
            else {
                return encode(["ok": false, "error": "malformed request; expected {\"cmd\": ...}"])
            }
            response = try dispatch(cmd: cmd, request: request)
        } catch let error as SMCError {
            response = ["ok": false, "error": error.description]
        } catch {
            response = ["ok": false, "error": String(describing: error)]
        }
        return encode(response)
    }

    private func dispatch(cmd: String, request: [String: Any]) throws -> [String: Any] {
        switch cmd {
        case "status":
            return status()
        case "set":
            return try setManual(request)
        case "auto":
            lock.lock()
            defer { lock.unlock() }
            revertLocked(reason: "requested")
            return ["ok": true, "control": controlLocked()]
        case "ping":
            return ["ok": true, "version": thermodVersion]
        default:
            return ["ok": false, "error": "unknown cmd '\(cmd)'"]
        }
    }

    // MARK: - Status

    func status() -> [String: Any] {
        let readings = sensors.readTemperatures()
        let fanStates = fans.readAllFans()

        var sensorList: [[String: Any]] = readings.map {
            ["key": $0.key, "name": $0.name, "group": $0.group.rawValue,
             "celsius": round1($0.celsius)]
        }
        sensorList.sort {
            (($0["group"] as? String) ?? "", ($0["key"] as? String) ?? "")
                < (($1["group"] as? String) ?? "", ($1["key"] as? String) ?? "")
        }

        var summary: [String: Any] = [:]
        if let cpu = sensors.maxTemperature(readings, group: .cpu) { summary["cpu_max_c"] = round1(cpu) }
        if let gpu = sensors.maxTemperature(readings, group: .gpu) { summary["gpu_max_c"] = round1(gpu) }
        if let all = sensors.maxTemperature(readings) { summary["overall_max_c"] = round1(all) }

        let power = sensors.readPowerWatts().mapValues { round1($0) }

        lock.lock()
        let control = controlLocked()
        lock.unlock()

        return [
            "ok": true,
            "model": hardwareModel(),
            "fans": fanStates.map { fan in
                [
                    "index": fan.index,
                    "actual_rpm": round1(fan.actualRpm),
                    "target_rpm": round1(fan.targetRpm),
                    "min_rpm": round1(fan.minRpm),
                    "max_rpm": round1(fan.maxRpm),
                    "mode": fan.modeName,
                ] as [String: Any]
            },
            "temperature": summary,
            "sensors": sensorList,
            "power_watts": power,
            "control": control,
        ]
    }

    private func controlLocked() -> [String: Any] {
        var control: [String: Any] = [
            "manual": manual != nil,
            "failsafe_temp_c": Self.failsafeTempC,
        ]
        if let manual {
            control["ttl_remaining_s"] = max(0, Int(manual.expiresAt.timeIntervalSinceNow))
            control["targets"] = Dictionary(uniqueKeysWithValues:
                manual.targets.map { (String($0.key), round1($0.value)) })
            control["strategy"] = manual.strategy.rawValue
        }
        if let lastRevert {
            control["last_revert"] = lastRevert
        }
        return control
    }

    // MARK: - Manual control

    private func setManual(_ request: [String: Any]) throws -> [String: Any] {
        guard fans.fanCount > 0 else {
            return ["ok": false, "error": "no fans detected on this machine"]
        }

        let ttlRequested = (request["ttl_seconds"] as? NSNumber)?.doubleValue ?? Self.defaultTtl
        let ttl = min(max(ttlRequested, 10), Self.maxTtl)

        let fanIndexes: [Int]
        if let fan = (request["fan"] as? NSNumber)?.intValue {
            guard fan >= 0 && fan < fans.fanCount else {
                return ["ok": false, "error": "fan index \(fan) out of range (0..\(fans.fanCount - 1))"]
            }
            fanIndexes = [fan]
        } else {
            fanIndexes = Array(0..<fans.fanCount)
        }

        let rpmParam = (request["rpm"] as? NSNumber)?.floatValue
        let percentParam = (request["percent"] as? NSNumber)?.floatValue
        guard rpmParam != nil || percentParam != nil else {
            return ["ok": false, "error": "provide 'rpm' or 'percent'"]
        }

        lock.lock()
        defer { lock.unlock() }

        var applied: [[String: Any]] = []
        var strategy: ControlStrategy = .direct
        var targets = manual?.targets ?? [:]

        for index in fanIndexes {
            let state = try fans.readFan(index)
            let requested: Float
            if let rpm = rpmParam {
                requested = rpm
            } else {
                let pct = min(max(percentParam!, 0), 100)
                requested = state.minRpm + (state.maxRpm - state.minRpm) * pct / 100.0
            }
            let clamped = min(max(requested, state.minRpm), state.maxRpm)

            let usedStrategy = try fans.enableManual(fan: index)
            if usedStrategy != .direct { strategy = usedStrategy }
            try fans.setTarget(fan: index, rpm: clamped)
            targets[index] = clamped

            applied.append([
                "fan": index,
                "requested_rpm": round1(requested),
                "applied_rpm": round1(clamped),
                "clamped": abs(requested - clamped) >= 1.0,
                "min_rpm": round1(state.minRpm),
                "max_rpm": round1(state.maxRpm),
            ])
        }

        manual = ManualState(
            targets: targets,
            expiresAt: Date().addingTimeInterval(ttl),
            strategy: strategy
        )
        lastRevert = nil
        log("manual set targets=\(targets) ttl=\(Int(ttl))s strategy=\(strategy.rawValue)")

        return [
            "ok": true,
            "applied": applied,
            "strategy": strategy.rawValue,
            "ttl_seconds": Int(ttl),
            "note": "Fans revert to system control automatically when the TTL expires, " +
                    "on thermal failsafe (\(Self.failsafeTempC)°C), or if the daemon stops.",
        ]
    }

    private func revertLocked(reason: String) {
        guard manual != nil else { return }
        fans.releaseAll()
        manual = nil
        lastRevert = [
            "reason": reason,
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        log("reverted to system control reason=\(reason)")
    }

    // MARK: - Safety loop

    func tick() {
        lock.lock()
        defer { lock.unlock() }
        guard let state = manual else { return }

        if Date() >= state.expiresAt {
            revertLocked(reason: "ttl-expired")
            return
        }

        // Failsafe watches die sensors (cpu/gpu) only — system/battery sensors
        // never legitimately reach this range and discovered unknown keys land
        // in the system group, so they cannot false-trigger a revert.
        let readings = sensors.readTemperatures()
        let dieMax = max(
            sensors.maxTemperature(readings, group: .cpu) ?? 0,
            sensors.maxTemperature(readings, group: .gpu) ?? 0
        )
        if dieMax >= Self.failsafeTempC {
            log("FAILSAFE: max die temp \(dieMax)°C >= \(Self.failsafeTempC)°C")
            revertLocked(reason: "thermal-failsafe")
            return
        }

        // Firmware resets Ftst across sleep/wake and thermalmonitord may reclaim
        // control. If manual mode should be active but isn't, re-assert it.
        let ftstDropped = fans.ftstAvailable
            && state.strategy == .ftstUnlock
            && fans.ftstValue() != 1
        let modeDropped = state.targets.keys.contains { index in
            (try? fans.readFan(index).mode) != 1
        }
        if ftstDropped || modeDropped {
            log("re-asserting manual control (ftstDropped=\(ftstDropped) modeDropped=\(modeDropped))")
            do {
                for (index, rpm) in state.targets {
                    try fans.enableManual(fan: index)
                    try fans.setTarget(fan: index, rpm: rpm)
                }
            } catch {
                log("re-assert failed: \(error) — reverting to system control")
                revertLocked(reason: "reassert-failed")
            }
        }
    }

    // MARK: - Shutdown

    func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        revertLocked(reason: "daemon-shutdown")
        log("thermod stopped")
    }

    // MARK: - Helpers

    private func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ??
            Data("{\"ok\":false,\"error\":\"encode failure\"}".utf8)
    }
}

/// One-decimal rounding that serializes cleanly (avoids Double artifacts like 7845.6999…).
func round1(_ value: Float) -> NSDecimalNumber {
    NSDecimalNumber(string: String(format: "%.1f", value))
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("[\(stamp)] \(message)\n".utf8))
}
