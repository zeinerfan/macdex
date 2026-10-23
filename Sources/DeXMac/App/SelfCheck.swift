import DeXCore
import Foundation

/// Command-line verification for a built app bundle:
///
///     "DeX for Mac.app/Contents/MacOS/DeXMac" --self-check
///
/// Resolves the toolchain exactly as the app does (so bundled tools are
/// exercised inside the real bundle), runs both binaries, and exits non-zero
/// if anything is wrong. Useful for packaging checks and support requests.
enum SelfCheck {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--self-check") else { return }
        exit(execute())
    }

    private static func execute() -> Int32 {
        print("DeX for Mac — self check")
        print("Bundle: \(Bundle.main.bundleURL.path)")

        guard let toolchain = Toolchain.locate() else {
            print("FAIL: could not locate adb and scrcpy.")
            return 1
        }

        print("Origin: \(toolchain.origin.label)")
        print("adb:    \(toolchain.adb.path)")
        print("scrcpy: \(toolchain.scrcpy.path)")
        print("server: \(toolchain.server?.path ?? "not found")")

        var failures: [String] = []

        let adbResult = run(toolchain.adb, ["version"], adb: toolchain.adb.path)
        if adbResult.status == 0, let version = Toolchain.parseADBVersion(adbResult.output) {
            print("adb version:    \(version)")
        } else {
            failures.append("adb version failed (exit \(adbResult.status)): \(firstLine(adbResult.output))")
        }

        let scrcpyResult = run(toolchain.scrcpy, ["--version"], adb: toolchain.adb.path)
        if scrcpyResult.status == 0, let version = Toolchain.parseScrcpyVersion(scrcpyResult.output) {
            print("scrcpy version: \(version)")
        } else {
            failures.append("scrcpy --version failed (exit \(scrcpyResult.status)): \(firstLine(scrcpyResult.output))")
        }

        if toolchain.server == nil {
            failures.append("scrcpy-server is missing next to the scrcpy binary.")
        }

        if failures.isEmpty {
            print("PASS: bundled toolchain is ready.")
            return 0
        }

        for failure in failures {
            print("FAIL: \(failure)")
        }
        return 1
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String],
        adb: String
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["ADB"] = adb
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func firstLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? "no output"
    }
}
