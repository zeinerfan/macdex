import Foundation

public struct ADBOutcome: Sendable {
    public let ok: Bool
    public let message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }
}

/// Thin, typed wrapper around the adb command line.
public struct ADBClient: Sendable {
    public let toolchain: Toolchain
    /// When set, all adb processes (and scrcpy) use this isolated server port.
    public let serverPort: Int?

    public init(toolchain: Toolchain, serverPort: Int? = nil) {
        self.toolchain = toolchain
        self.serverPort = serverPort
    }

    public func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = toolchain.adb.path
        env["ADB_MDNS"] = "1"
        env["ADB_MDNS_OPENSCREEN"] = "0"
        if let serverPort {
            env["ANDROID_ADB_SERVER_PORT"] = String(serverPort)
        }
        return env
    }

    public func run(_ arguments: [String], timeout: TimeInterval = 20) async throws -> ProcessOutput {
        try await ProcessRunner.shared.run(
            toolchain.adb,
            arguments: arguments,
            environment: environment(),
            timeout: timeout
        )
    }

    private func serialArguments(_ serial: String, _ arguments: [String]) -> [String] {
        ["-s", serial] + arguments
    }

    // MARK: - Server

    public func startServer() async {
        _ = try? await run(["start-server"], timeout: 25)
    }

    public func killServer() async {
        _ = try? await run(["kill-server"], timeout: 8)
    }

    // MARK: - Devices

    public func devices() async throws -> [AndroidDevice] {
        let output = try await run(["devices", "-l"], timeout: 12)
        return ADBParsers.devices(from: output.stdout)
    }

    public func rawDevices() async -> String {
        (try? await run(["devices", "-l"], timeout: 12).stdout) ?? ""
    }

    public func properties(serial: String) async -> [String: String] {
        guard let output = try? await run(serialArguments(serial, ["shell", "getprop"]), timeout: 18) else {
            return [:]
        }
        return ADBParsers.getprop(from: output.stdout)
    }

    public func metadata(serial: String) async -> DeviceMetadata? {
        let props = await properties(serial: serial)
        guard !props.isEmpty else { return nil }
        return DeviceMetadata(props: props)
    }

    // MARK: - Wireless debugging

    public func mdnsServices() async -> [MDNSService] {
        guard let output = try? await run(["mdns", "services"], timeout: 8) else { return [] }
        return ADBParsers.mdnsServices(from: output.combined)
    }

    public func pair(endpoint: String, code: String) async -> ADBOutcome {
        guard let output = try? await run(["pair", endpoint, code], timeout: 40) else {
            return ADBOutcome(ok: false, message: "adb could not start. Check your tool settings.")
        }
        let text = output.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = text.lowercased().contains("successfully paired")
            || (output.status == 0 && !text.lowercased().contains("failed"))
        return ADBOutcome(ok: ok, message: text.isEmpty ? "No response from adb." : text)
    }

    public func connect(_ endpoint: String, timeout: TimeInterval = 15) async -> ADBOutcome {
        guard let output = try? await run(["connect", endpoint], timeout: timeout) else {
            return ADBOutcome(ok: false, message: "adb could not start. Check your tool settings.")
        }
        let text = output.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let ok = (lower.contains("connected to") || lower.contains("already connected"))
            && !lower.contains("failed")
            && !lower.contains("cannot")
            && !lower.contains("unable")
        return ADBOutcome(ok: ok, message: text.isEmpty ? "No response from adb." : text)
    }

    public func disconnect(_ endpoint: String) async {
        _ = try? await run(["disconnect", endpoint], timeout: 10)
    }

    /// Enables adb over TCP on a USB-connected device.
    public func enableTCPIP(serial: String, port: Int = 5555) async -> ADBOutcome {
        guard let output = try? await run(serialArguments(serial, ["tcpip", String(port)]), timeout: 20) else {
            return ADBOutcome(ok: false, message: "adb could not start. Check your tool settings.")
        }
        let text = output.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let ok = lower.contains("restarting in tcp mode")
            || lower.contains("tcp mode port")
            || (output.status == 0 && lower.contains("port"))
        return ADBOutcome(ok: ok, message: text.isEmpty ? "No response from adb." : text)
    }

    /// Finds the phone's Wi-Fi address using several fallbacks.
    public func wlanIP(serial: String) async -> String? {
        let commands: [[String]] = [
            ["shell", "ip", "-f", "inet", "addr", "show", "wlan0"],
            ["shell", "ip", "addr", "show", "wlan0"],
            ["shell", "ip", "-4", "addr"],
            ["shell", "ip", "route"],
            ["shell", "getprop", "dhcp.wlan0.ipaddress"]
        ]

        for command in commands {
            guard let output = try? await run(serialArguments(serial, command), timeout: 8) else { continue }
            let text = output.combined
            if command.contains("getprop"), text.contains("192.168") || text.contains("10.") || text.contains("172.") {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.split(separator: ".").count == 4 {
                    return trimmed
                }
            }
            if let ip = ADBParsers.wlanIP(from: text) {
                return ip
            }
        }

        return nil
    }

    // MARK: - Misc

    public func screenResolution(serial: String) async -> String? {
        guard let output = try? await run(serialArguments(serial, ["shell", "wm", "size"]), timeout: 8) else {
            return nil
        }
        return ADBParsers.resolution(from: output.stdout)
    }

    public func hostFromSerial(_ serial: String) -> String? {
        guard serial.contains(":") else { return nil }
        return ADBParsers.parseHostPort(serial)?.host
    }
}
