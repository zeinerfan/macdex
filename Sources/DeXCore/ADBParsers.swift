import Foundation

public enum ADBParsers {

    // MARK: - adb devices -l

    public static func devices(from output: String) -> [AndroidDevice] {
        var result: [AndroidDevice] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            guard !line.hasPrefix("List of devices") else { continue }
            guard !line.hasPrefix("*") else { continue }
            guard !line.lowercased().hasPrefix("adb server") else { continue }

            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }

            let serial = parts[0]

            // `adb devices` may print "no permissions (user in plugdev group; ...)".
            let joinedState = parts.dropFirst().joined(separator: " ").lowercased()
            if joinedState.hasPrefix("no permissions") {
                result.append(AndroidDevice(serial: serial, state: .noPermissions, transport: .usb))
                continue
            }

            guard let state = DeviceConnectionState(rawValue: parts[1]) else { continue }

            var fields: [String: String] = [:]
            for part in parts.dropFirst(2) {
                guard let separator = part.firstIndex(of: ":") else { continue }
                let key = String(part[part.startIndex..<separator])
                let value = String(part[part.index(after: separator)...])
                fields[key] = value
            }

            let transport: DeviceTransport
            if fields["usb"] != nil {
                transport = .usb
            } else if serial.contains(":") || serial.hasPrefix("adb-") {
                transport = .wireless
            } else {
                transport = .unknown
            }

            result.append(
                AndroidDevice(
                    serial: serial,
                    state: state,
                    transport: transport,
                    rawModel: fields["model"],
                    product: fields["product"],
                    device: fields["device"],
                    transportID: fields["transport_id"]
                )
            )
        }

        return result
    }

    // MARK: - adb mdns services

    public static func mdnsServices(from output: String) -> [MDNSService] {
        var result: [MDNSService] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard tokens.count >= 3 else { continue }

            var kind: MDNSService.Kind?
            if line.contains(MDNSService.Kind.pairing.rawValue) {
                kind = .pairing
            } else if line.contains(MDNSService.Kind.connect.rawValue) {
                kind = .connect
            }
            guard let kind else { continue }

            guard let endpointToken = tokens.last,
                  let (host, port) = parseHostPort(endpointToken) else { continue }

            result.append(
                MDNSService(
                    serviceName: tokens[0],
                    kind: kind,
                    host: host,
                    port: port
                )
            )
        }

        return result
    }

    public static func parseHostPort(_ token: String) -> (host: String, port: Int)? {
        var host = token.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }

        if host.hasPrefix("[") {
            // [fe80::1]:5555
            guard let closing = host.firstIndex(of: "]") else { return nil }
            let portStart = host.index(after: closing)
            guard portStart < host.endIndex, host[portStart] == ":" else { return nil }
            let portText = String(host[host.index(after: portStart)...])
            host = String(host[host.index(after: host.startIndex)..<closing])
            guard let port = Int(portText), (1...65535).contains(port) else { return nil }
            return (host, port)
        }

        guard let separator = host.lastIndex(of: ":") else { return nil }
        let portText = String(host[host.index(after: separator)...])
        host = String(host[host.startIndex..<separator])
        guard !host.isEmpty,
              let port = Int(portText),
              (1...65535).contains(port) else { return nil }
        return (host, port)
    }

    // MARK: - getprop

    public static func getprop(from output: String) -> [String: String] {
        var props: [String: String] = [:]

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.hasPrefix("["),
                  let separator = line.range(of: "]: [") else { continue }

            let key = String(line[line.index(after: line.startIndex)..<separator.lowerBound])
            var value = String(line[separator.upperBound...])
            if value.hasSuffix("]") { value.removeLast() }
            props[key] = value
        }

        return props
    }

    // MARK: - One UI

    /// Parses Samsung's numeric One UI version (e.g. 80000 → 8, 60100 → 6.1).
    public static func parseOneUI(_ raw: String?) -> (display: String, major: Int)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let number = Int(raw),
              number > 0 else { return nil }

        if number >= 10000 {
            let major = number / 10000
            let minor = (number / 100) % 100
            let patch = number % 100

            var display = "\(major)"
            if minor > 0 || patch > 0 { display += ".\(minor)" }
            if patch > 0 { display += ".\(patch)" }
            return (display, major)
        }

        return (raw, number)
    }

    // MARK: - Wireless IP

    public static func wlanIP(from output: String) -> String? {
        let patterns = [
            #"inet\s+(?:addr:)?(\d{1,3}(?:\.\d{1,3}){3})"#,
            #"src\s+(\d{1,3}(?:\.\d{1,3}){3})"#,
            #"ipaddress\s+(\d{1,3}(?:\.\d{1,3}){3})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            for match in regex.matches(in: output, range: range) {
                guard match.numberOfRanges > 1,
                      let captured = Range(match.range(at: 1), in: output) else { continue }
                let candidate = String(output[captured])
                if candidate != "127.0.0.1" {
                    return candidate
                }
            }
        }

        // `getprop dhcp.wlan0.ipaddress` prints a bare address.
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let octets = trimmed.split(separator: ".")
        if octets.count == 4,
           octets.allSatisfy({ Int($0).map { (0...255).contains($0) } == true }),
           trimmed != "127.0.0.1" {
            return trimmed
        }

        return nil
    }

    // MARK: - Display helpers

    public static func resolution(from output: String) -> String? {
        // "Physical size: 1440x3120"
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix("physical size:") {
                return text.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
