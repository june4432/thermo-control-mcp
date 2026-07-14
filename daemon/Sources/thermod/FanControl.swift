//
//  FanControl.swift
//  thermod
//
//  Fan mode and target-RPM control, including the Ftst unlock sequence
//  required on M3/M4-generation Apple Silicon.
//
//  Behavior documented in agoodkind/macos-smc-fan (MIT) docs/research.md:
//    - Fan mode key is `F%dMd` (M1–M4) or `F%dmd` (M5) — probe both at runtime.
//    - Mode values: 0 = auto, 1 = manual, 3 = system (thermalmonitord mitigation).
//    - On M3/M4, writing mode=1 while in mode 3 fails with firmware 0x82.
//      Writing Ftst=1 suppresses thermalmonitord's reclaim logic; the mode
//      write then succeeds within ~3–6 s. Ftst must STAY 1 while manual
//      control is held, and the firmware resets it to 0 across sleep/wake.
//

import Foundation

struct FanState {
    let index: Int
    let actualRpm: Float
    let targetRpm: Float
    let minRpm: Float
    let maxRpm: Float
    let mode: UInt8

    var modeName: String {
        switch mode {
        case 0: return "auto"
        case 1: return "manual"
        case 3: return "system"
        default: return "unknown(\(mode))"
        }
    }
}

enum ControlStrategy: String {
    case direct = "direct"
    case ftstUnlock = "ftst-unlock"
    case forceBits = "force-bits"   // legacy Intel FS! bitmask
}

final class FanControl {
    private static let ftstSettleDelay: TimeInterval = 0.5
    private static let ftstRetryDelay: TimeInterval = 0.1
    private static let ftstUnlockTimeout: TimeInterval = 10.0

    private static let forceBitsKey = "FS! "  // legacy Intel per-fan force bitmask

    let smc: SMCConnection
    let fanCount: Int
    let modeKeyFormat: String   // "F%dMd" or "F%dmd"
    let modeKeyAvailable: Bool
    let ftstAvailable: Bool
    let forceBitsAvailable: Bool

    init(smc: SMCConnection) {
        self.smc = smc
        fanCount = Int((try? smc.readUInt8("FNum")) ?? 0)

        var format = "F%dMd"
        var found = false
        for candidate in ["F%dMd", "F%dmd"] {
            let probe = candidate.replacingOccurrences(of: "%d", with: "0")
            if smc.keyExists(probe) {
                format = candidate
                found = true
                break
            }
        }
        modeKeyFormat = format
        modeKeyAvailable = found
        ftstAvailable = smc.keyExists("Ftst")
        forceBitsAvailable = smc.keyExists(Self.forceBitsKey)
    }

    private func modeKey(_ fan: Int) -> String {
        modeKeyFormat.replacingOccurrences(of: "%d", with: String(fan))
    }

    // MARK: Reads

    func readFan(_ index: Int) throws -> FanState {
        FanState(
            index: index,
            actualRpm: try smc.readFloat("F\(index)Ac"),
            targetRpm: (try? smc.readFloat("F\(index)Tg")) ?? 0,
            minRpm: (try? smc.readFloat("F\(index)Mn")) ?? 0,
            maxRpm: (try? smc.readFloat("F\(index)Mx")) ?? 0,
            mode: readMode(index)
        )
    }

    private func readMode(_ index: Int) -> UInt8 {
        if modeKeyAvailable {
            return (try? smc.readUInt8(modeKey(index))) ?? 255
        }
        if forceBitsAvailable, let bits = try? readForceBits() {
            return bits & (1 << UInt16(index)) != 0 ? 1 : 0
        }
        return 255
    }

    private func readForceBits() throws -> UInt16 {
        let (bytes, _) = try smc.readBytes(Self.forceBitsKey)
        guard bytes.count >= 2 else { throw SMCError.firmware(Self.forceBitsKey, .spuriousData) }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    private func writeForceBits(_ bits: UInt16) throws {
        try smc.writeBytes(Self.forceBitsKey, [UInt8(bits >> 8), UInt8(bits & 0xFF)])
    }

    func readAllFans() -> [FanState] {
        (0..<fanCount).compactMap { try? readFan($0) }
    }

    func ftstValue() -> UInt8? {
        guard ftstAvailable else { return nil }
        return try? smc.readUInt8("Ftst")
    }

    // MARK: Manual control

    /// Put one fan into manual mode. Tries a direct mode write first (works on
    /// M1/M2/M5 and T2 Intel); falls back to the Ftst unlock sequence (M3/M4).
    /// Pre-T2 Intel Macs have no mode key at all — there the legacy FS! force
    /// bitmask is used instead.
    @discardableResult
    func enableManual(fan: Int) throws -> ControlStrategy {
        guard modeKeyAvailable else {
            guard forceBitsAvailable else {
                throw SMCError.firmware("F0Md", .notFound)
            }
            try writeForceBits(try readForceBits() | (1 << UInt16(fan)))
            return .forceBits
        }

        do {
            try smc.writeUInt8(modeKey(fan), 1)
            return .direct
        } catch {
            guard ftstAvailable else { throw error }
        }

        try smc.writeUInt8("Ftst", 1)
        Thread.sleep(forTimeInterval: Self.ftstSettleDelay)

        let deadline = Date().addingTimeInterval(Self.ftstUnlockTimeout)
        while true {
            do {
                try smc.writeUInt8(modeKey(fan), 1)
                return .ftstUnlock
            } catch {
                if Date() >= deadline {
                    throw SMCError.timeout("Ftst unlock for fan \(fan)")
                }
                Thread.sleep(forTimeInterval: Self.ftstRetryDelay)
            }
        }
    }

    /// Write a target RPM. Firmware occasionally answers 0x87 (keySizeMismatch)
    /// on F%dTg writes even though the value was applied — verify by reading back.
    func setTarget(fan: Int, rpm: Float) throws {
        let key = "F\(fan)Tg"
        do {
            try smc.writeFloat(key, rpm)
        } catch SMCError.firmware(_, .keySizeMismatch) {
            let applied = try smc.readFloat(key)
            guard abs(applied - rpm) < 1.0 else {
                throw SMCError.firmware(key, .keySizeMismatch)
            }
        }
    }

    /// Return every fan to system control and release the Ftst override.
    func releaseAll() {
        if modeKeyAvailable {
            for fan in 0..<fanCount {
                try? smc.writeUInt8(modeKey(fan), 0)
            }
        }
        if forceBitsAvailable {
            try? writeForceBits(0)
        }
        if ftstAvailable, (try? smc.readUInt8("Ftst")) == 1 {
            try? smc.writeUInt8("Ftst", 0)
        }
    }
}
