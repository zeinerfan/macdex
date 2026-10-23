import Foundation

public enum ToolOrigin: String, Sendable {
    case bundled
    case applicationSupport
    case homebrew
    case system
    case custom

    public var label: String {
        switch self {
        case .bundled: return "Bundled with DeX for Mac"
        case .applicationSupport: return "Installed by DeX for Mac"
        case .homebrew: return "Homebrew"
        case .system: return "System"
        case .custom: return "Custom location"
        }
    }
}

public struct Toolchain: Sendable, Equatable {
    public var adb: URL
    public var scrcpy: URL
    public var server: URL?
    public var origin: ToolOrigin
    public var adbVersion: String?
    public var scrcpyVersion: String?

    public init(
        adb: URL,
        scrcpy: URL,
        server: URL? = nil,
        origin: ToolOrigin,
        adbVersion: String? = nil,
        scrcpyVersion: String? = nil
    ) {
        self.adb = adb
        self.scrcpy = scrcpy
        self.server = server
        self.origin = origin
        self.adbVersion = adbVersion
        self.scrcpyVersion = scrcpyVersion
    }

    public static var applicationSupportToolsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DeXMac/tools", isDirectory: true)
    }

    public static var bundledToolsDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("tools", isDirectory: true)
    }

    // MARK: - Locate

    public static func locate(customADB: String? = nil, customScrcpy: String? = nil) -> Toolchain? {
        let fm = FileManager.default

        func executable(_ path: String?) -> URL? {
            guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
            let expanded = (path as NSString).expandingTildeInPath
            guard fm.isExecutableFile(atPath: expanded) else { return nil }
            return URL(fileURLWithPath: expanded)
        }

        func make(scrcpyPath: String?, adbPath: String?, origin: ToolOrigin) -> Toolchain? {
            guard let scrcpy = executable(scrcpyPath),
                  let adb = executable(adbPath) ?? executable(
                    scrcpy.deletingLastPathComponent().appendingPathComponent("adb").path
                  ) else { return nil }

            let adjacentServer = scrcpy.deletingLastPathComponent().appendingPathComponent("scrcpy-server")
            let server = fm.fileExists(atPath: adjacentServer.path) ? adjacentServer : nil

            return Toolchain(adb: adb, scrcpy: scrcpy, server: server, origin: origin)
        }

        // 1. Explicit custom paths.
        if customScrcpy != nil || customADB != nil {
            let scrcpyCandidate = customScrcpy ?? firstExistingScrcpy()
            if let toolchain = make(scrcpyPath: scrcpyCandidate, adbPath: customADB, origin: .custom) {
                return toolchain
            }
        }

        // 2. Tools downloaded by the app (updates, or a fresh install).
        let support = applicationSupportToolsDirectory
        if let toolchain = make(
            scrcpyPath: support.appendingPathComponent("scrcpy").path,
            adbPath: support.appendingPathComponent("adb").path,
            origin: .applicationSupport
        ) {
            return toolchain
        }

        // 3. Tools embedded in the app bundle, so it works out of the box.
        if let bundled = bundledToolsDirectory,
           let toolchain = make(
               scrcpyPath: bundled.appendingPathComponent("scrcpy").path,
               adbPath: bundled.appendingPathComponent("adb").path,
               origin: .bundled
           ) {
            return toolchain
        }

        // 4. Homebrew and other common locations.
        let prefixes = ["/opt/homebrew", "/usr/local"]
        for prefix in prefixes {
            if let toolchain = make(
                scrcpyPath: "\(prefix)/bin/scrcpy",
                adbPath: "\(prefix)/bin/adb",
                origin: .homebrew
            ) {
                return toolchain
            }
            if let toolchain = make(
                scrcpyPath: "\(prefix)/bin/scrcpy",
                adbPath: "\(prefix)/platform-tools/adb",
                origin: .homebrew
            ) {
                return toolchain
            }
        }

        // 5. Android SDK platform-tools combined with any scrcpy on the machine.
        let home = fm.homeDirectoryForCurrentUser.path
        let adbCandidates = [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "\(home)/Android/Sdk/platform-tools/adb",
            "/usr/local/platform-tools/adb"
        ]
        if let scrcpy = firstExistingScrcpy() {
            for adbPath in adbCandidates {
                if let toolchain = make(scrcpyPath: scrcpy, adbPath: adbPath, origin: .system) {
                    return toolchain
                }
            }
        }

        // 6. Last resort: whatever is on PATH.
        if let scrcpy = firstExistingScrcpy(), let adb = firstExistingADB() {
            if let toolchain = make(scrcpyPath: scrcpy, adbPath: adb, origin: .system) {
                return toolchain
            }
        }

        return nil
    }

    private static func firstExistingScrcpy() -> String? {
        let candidates = [
            "/opt/homebrew/bin/scrcpy",
            "/usr/local/bin/scrcpy",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/scrcpy",
            "/usr/bin/scrcpy"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func firstExistingADB() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Android/sdk/platform-tools/adb",
            "/usr/bin/adb"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Validation

    /// Confirms both binaries actually run and records their versions.
    public func validating() async -> Toolchain {
        var copy = self

        if let output = try? await ProcessRunner.shared.run(adb, arguments: ["version"], timeout: 10) {
            copy.adbVersion = Toolchain.parseADBVersion(output.combined)
        }

        if let output = try? await ProcessRunner.shared.run(scrcpy, arguments: ["--version"], timeout: 10) {
            copy.scrcpyVersion = Toolchain.parseScrcpyVersion(output.combined)
        }

        return copy
    }

    public var isValid: Bool {
        adbVersion != nil && scrcpyVersion != nil
    }

    public func scrcpyEnvironment(serverPort: Int? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["ADB"] = adb.path
        if let serverPort {
            env["ANDROID_ADB_SERVER_PORT"] = String(serverPort)
        }
        env["ADB_MDNS"] = "1"
        return env
    }

    public static func parseADBVersion(_ output: String) -> String? {
        // "Android Debug Bridge version 1.0.41" / "Version 37.0.1-15733141"
        for line in output.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("Version ") {
                return String(text.dropFirst("Version ".count))
                    .split(separator: "-").first.map(String.init)
            }
            if text.contains("Android Debug Bridge version ") {
                return text.components(separatedBy: "Android Debug Bridge version ").last?
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    public static func parseScrcpyVersion(_ output: String) -> String? {
        // "scrcpy 5.0.1 <https://github.com/...>"
        guard let firstLine = output.split(whereSeparator: \.isNewline).first else { return nil }
        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2, tokens[0] == "scrcpy" else { return nil }
        return String(tokens[1])
    }
}
