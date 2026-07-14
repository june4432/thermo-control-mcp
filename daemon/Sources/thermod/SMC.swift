//
//  SMC.swift
//  thermod
//
//  Low-level access to Apple's System Management Controller via IOKit.
//
//  Protocol facts (80-byte param struct, selector 2, commands 5/6/9,
//  per-key read/write firmware permissions) are documented in:
//    - agoodkind/macos-smc-fan (MIT) — docs/research.md
//    - acidanthera VirtualSMC SDK — AppleSmc.h
//    - Linux kernel applesmc / macsmc-hwmon drivers
//

import Foundation
import IOKit

// MARK: - Commands & result codes

enum SMCCommand: UInt8 {
    /// IOConnectCallStructMethod selector for all SMC calls
    static let kernelIndex: UInt32 = 2

    case readBytes = 5
    case writeBytes = 6
    case readIndex = 8
    case readKeyInfo = 9
}

enum SMCResultCode: UInt8, CustomStringConvertible {
    case success = 0x00
    case error = 0x01
    case commCollision = 0x80
    case spuriousData = 0x81
    case badCommand = 0x82        // firmware rejection, e.g. mode write while in system mode 3
    case badParameter = 0x83
    case notFound = 0x84
    case notReadable = 0x85
    case notWritable = 0x86
    case keySizeMismatch = 0x87   // write may still have been applied — verify by reading back
    case framingError = 0x88
    case badArgumentError = 0x89

    var description: String {
        let name: String
        switch self {
        case .success: name = "success"
        case .error: name = "error"
        case .commCollision: name = "commCollision"
        case .spuriousData: name = "spuriousData"
        case .badCommand: name = "badCommand"
        case .badParameter: name = "badParameter"
        case .notFound: name = "notFound"
        case .notReadable: name = "notReadable"
        case .notWritable: name = "notWritable"
        case .keySizeMismatch: name = "keySizeMismatch"
        case .framingError: name = "framingError"
        case .badArgumentError: name = "badArgumentError"
        }
        return String(format: "%@ (0x%02x)", name, rawValue)
    }
}

enum SMCError: Error, CustomStringConvertible {
    case connectionFailed
    case invalidKey(String)
    case ioKit(kern_return_t)
    case firmware(String, SMCResultCode)
    case timeout(String)

    var description: String {
        switch self {
        case .connectionFailed: return "failed to open AppleSMC service"
        case .invalidKey(let key): return "invalid SMC key '\(key)'"
        case .ioKit(let code): return String(format: "IOKit error 0x%08x", code)
        case .firmware(let key, let code): return "SMC \(key): \(code)"
        case .timeout(let what): return "timed out: \(what)"
        }
    }
}

// MARK: - Param struct (80-byte kernel ABI)

/// Mirrors the AppleSMC kernel interface. Field offsets must match the C layout:
/// key@0, vers@4, pLimitData@8, keyInfo@28, result@40, status@41, data8@42,
/// data32@44, bytes@48..79. Swift places these at the expected offsets as long as
/// `MemoryLayout<SMCParamStruct>.stride` (80) is passed to IOConnectCallStructMethod.
struct SMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

// MARK: - Connection

final class SMCConnection {
    private let connection: io_connect_t

    init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else { throw SMCError.connectionFailed }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            throw SMCError.connectionFailed
        }
        connection = conn
    }

    deinit {
        IOServiceClose(connection)
    }

    // MARK: Key info

    struct KeyInfo {
        let dataSize: UInt32
        let dataType: String
    }

    func keyInfo(_ key: String) throws -> KeyInfo {
        var input = SMCParamStruct()
        input.key = try fourCharCode(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue
        let output = try call(input)
        try checkResult(output.result, key: key)
        return KeyInfo(
            dataSize: output.keyInfo.dataSize,
            dataType: fourCharString(output.keyInfo.dataType)
        )
    }

    func keyExists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    // MARK: Read / write

    func readBytes(_ key: String) throws -> (bytes: [UInt8], size: UInt32) {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = try fourCharCode(key)
        input.data8 = SMCCommand.readBytes.rawValue
        input.keyInfo.dataSize = info.dataSize
        let output = try call(input)
        try checkResult(output.result, key: key)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return (bytes, info.dataSize)
    }

    func writeBytes(_ key: String, _ bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        var input = SMCParamStruct()
        input.key = try fourCharCode(key)
        input.data8 = SMCCommand.writeBytes.rawValue
        input.keyInfo.dataSize = info.dataSize
        input.bytes = Self.tuple32(bytes)
        let output = try call(input)
        try checkResult(output.result, key: key)
    }

    // MARK: Typed helpers

    /// Read a numeric key as Float. Handles Apple Silicon `flt` (4-byte native-endian
    /// IEEE 754) and legacy Intel `fpe2` (2-byte big-endian 14.2 fixed point).
    func readFloat(_ key: String) throws -> Float {
        let (bytes, size) = try readBytes(key)
        if size == 4, bytes.count >= 4 {
            return bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
        }
        if bytes.count >= 2 {
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Float(raw) / 4.0
        }
        throw SMCError.firmware(key, .spuriousData)
    }

    func writeFloat(_ key: String, _ value: Float) throws {
        let info = try keyInfo(key)
        var bytes: [UInt8]
        if info.dataSize == 4 {
            bytes = withUnsafeBytes(of: value) { Array($0) }
        } else {
            let raw = UInt16((value * 4.0).rounded())
            bytes = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        }
        try writeBytes(key, bytes)
    }

    func readUInt8(_ key: String) throws -> UInt8 {
        let (bytes, _) = try readBytes(key)
        guard let first = bytes.first else { throw SMCError.firmware(key, .spuriousData) }
        return first
    }

    func writeUInt8(_ key: String, _ value: UInt8) throws {
        try writeBytes(key, [value])
    }

    // MARK: Internals

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        var inp = input
        var out = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            connection,
            SMCCommand.kernelIndex,
            &inp,
            MemoryLayout<SMCParamStruct>.stride,
            &out,
            &outSize
        )
        guard result == kIOReturnSuccess else { throw SMCError.ioKit(result) }
        return out
    }

    private func checkResult(_ result: UInt8, key: String) throws {
        guard result != SMCResultCode.success.rawValue else { return }
        throw SMCError.firmware(key, SMCResultCode(rawValue: result) ?? .error)
    }

    private func fourCharCode(_ string: String) throws -> UInt32 {
        guard string.utf8.count == 4 else { throw SMCError.invalidKey(string) }
        return string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func fourCharString(_ code: UInt32) -> String {
        let chars = [
            UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
        ]
        return String(bytes: chars, encoding: .ascii) ?? "????"
    }

    private static func tuple32(_ array: [UInt8]) -> SMCParamStruct.Bytes32 {
        var padded = array
        if padded.count < 32 { padded += Array(repeating: 0, count: 32 - padded.count) }
        return (
            padded[0], padded[1], padded[2], padded[3],
            padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11],
            padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19],
            padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27],
            padded[28], padded[29], padded[30], padded[31]
        )
    }
}

// MARK: - Hardware model

func hardwareModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    var model = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &model, &size, nil, 0)
    return String(cString: model)
}
