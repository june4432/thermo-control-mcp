//
//  SocketServer.swift
//  thermod
//
//  Newline-delimited JSON over a unix domain socket. One request per
//  connection: client sends a single JSON line, daemon answers with a single
//  JSON line and closes.
//
//  The socket is owned root:admin with mode 0660, so only administrator
//  users on the local machine can issue commands.
//

import Foundation

final class SocketServer {
    static let defaultPath = "/var/run/thermod.sock"
    private static let adminGid: gid_t = 80  // "admin" group on macOS
    private static let maxRequestBytes = 64 * 1024

    private let path: String
    private var serverFd: Int32 = -1

    init(path: String) {
        self.path = path
    }

    func start(handler: @escaping (Data) -> Data) throws {
        unlink(path)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw SocketError.create(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        try path.withCString { cPath in
            guard strlen(cPath) < MemoryLayout.size(ofValue: addr.sun_path) else {
                throw SocketError.pathTooLong(path)
            }
            withUnsafeMutableBytes(of: &addr.sun_path) { dest in
                _ = strcpy(dest.baseAddress!.assumingMemoryBound(to: CChar.self), cPath)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { throw SocketError.bind(path, errno) }

        // Restrict to root + admin group. chown fails silently when running
        // unprivileged (dev mode with THERMOD_SOCKET override) — that's fine.
        chmod(path, 0o660)
        _ = chown(path, 0, Self.adminGid)

        guard listen(serverFd, 16) == 0 else { throw SocketError.listen(errno) }
        log("listening on \(path)")

        let fd = serverFd
        Thread.detachNewThread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    if errno == EBADF { return }  // socket closed during shutdown
                    continue
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.serve(client: client, handler: handler)
                }
            }
        }
    }

    private static func serve(client: Int32, handler: (Data) -> Data) {
        defer { close(client) }

        var request = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !request.contains(0x0A) && request.count < maxRequestBytes {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { break }
            request.append(contentsOf: buffer[0..<count])
        }
        guard let newline = request.firstIndex(of: 0x0A) else { return }

        var response = handler(request.prefix(upTo: newline))
        response.append(0x0A)
        response.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(client, raw.baseAddress! + offset, raw.count - offset)
                guard written > 0 else { break }
                offset += written
            }
        }
    }

    func stop() {
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        unlink(path)
    }

    enum SocketError: Error, CustomStringConvertible {
        case create(Int32)
        case bind(String, Int32)
        case listen(Int32)
        case pathTooLong(String)

        var description: String {
            switch self {
            case .create(let err): return "socket() failed: \(String(cString: strerror(err)))"
            case .bind(let path, let err):
                return "bind(\(path)) failed: \(String(cString: strerror(err)))"
            case .listen(let err): return "listen() failed: \(String(cString: strerror(err)))"
            case .pathTooLong(let path): return "socket path too long: \(path)"
            }
        }
    }
}
