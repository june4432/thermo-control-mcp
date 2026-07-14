//
//  main.swift
//  thermod
//
//  Entry point. Subcommands:
//    thermod daemon   — run the control daemon (root; launchd)
//    thermod status   — one-shot status JSON to stdout (works unprivileged)
//    thermod version
//

import Foundation

let thermodVersion = "0.1.0"

func runDaemon() {
    let daemon: Daemon
    do {
        daemon = try Daemon()
    } catch {
        log("fatal: \(error)")
        exit(1)
    }

    let socketPath = ProcessInfo.processInfo.environment["THERMOD_SOCKET"]
        ?? SocketServer.defaultPath
    let server = SocketServer(path: socketPath)
    do {
        try server.start { daemon.handle($0) }
    } catch {
        log("fatal: \(error)")
        exit(1)
    }

    // Revert fans to system control on any orderly exit path.
    var signalSources: [DispatchSourceSignal] = []
    for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler {
            daemon.shutdown()
            server.stop()
            exit(0)
        }
        source.resume()
        signalSources.append(source)
    }

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "thermod.tick"))
    timer.schedule(deadline: .now() + Daemon.tickInterval, repeating: Daemon.tickInterval)
    timer.setEventHandler { daemon.tick() }
    timer.resume()

    // dispatchMain() never returns; keep the sources rooted for the process lifetime.
    withExtendedLifetime((signalSources, timer)) {
        dispatchMain()
    }
}

func runStatus() {
    do {
        let daemon = try Daemon()
        let data = try JSONSerialization.data(
            withJSONObject: daemon.status(),
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}

let arguments = CommandLine.arguments
switch arguments.count > 1 ? arguments[1] : "" {
case "daemon":
    runDaemon()
case "status":
    runStatus()
case "version":
    print(thermodVersion)
default:
    FileHandle.standardError.write(Data("""
    usage: thermod <command>

      daemon    run the fan-control daemon (requires root; normally via launchd)
      status    print thermal status as JSON (no root required)
      version   print version

    """.utf8))
    exit(64)
}
