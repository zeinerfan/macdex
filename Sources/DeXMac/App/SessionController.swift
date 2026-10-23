import DeXCore
import Foundation

// MARK: - Session state

enum SessionStatus: Equatable {
    case idle
    case starting
    case running
    case stopping
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .stopping: return true
        case .idle, .failed: return false
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .idle: return "Not running"
        case .starting: return "Starting DeX…"
        case .running: return "DeX is running"
        case .stopping: return "Closing…"
        case .failed: return "Could not start"
        }
    }
}

struct LogEntry: Identifiable, Equatable {
    enum Level {
        case system
        case output
        case error
    }

    let id = UUID()
    let date: Date
    let level: Level
    let text: String
}

// MARK: - Session controller

@MainActor
final class SessionController: ObservableObject {
    static weak var current: SessionController?

    @Published private(set) var status: SessionStatus = .idle
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var startedAt: Date?
    @Published private(set) var mode: LaunchMode?
    @Published private(set) var serial: String?
    @Published private(set) var hint: String?
    @Published var isLogVisible = false

    private var process: LineProcess?
    private var stopRequested = false
    private var startupWatchdog: Task<Void, Never>?
    private var lastConfiguration: ScrcpyLaunchConfiguration?

    init() {
        SessionController.current = self
    }

    var isActive: Bool { status.isActive }

    var lastCommand: String? {
        lastConfiguration.map { configuration in
            (["scrcpy"] + ScrcpyArguments.make(for: configuration)).joined(separator: " ")
        }
    }

    // MARK: Start / stop

    func start(configuration: ScrcpyLaunchConfiguration, toolchain: Toolchain, adbPort: Int?) {
        guard process == nil else { return }

        stopRequested = false
        hint = nil
        mode = configuration.mode
        serial = configuration.serial
        startedAt = Date()
        status = .starting
        lastConfiguration = configuration
        entries.removeAll()

        let arguments = ScrcpyArguments.make(for: configuration)
        append(.system, "Launching scrcpy \(toolchain.scrcpyVersion ?? "")")
        append(.system, "scrcpy " + arguments.joined(separator: " "))

        let process = LineProcess()
        process.onLine = { [weak self] line in
            Task { @MainActor [weak self] in
                self?.receive(line)
            }
        }
        process.onExit = { [weak self] code in
            Task { @MainActor [weak self] in
                self?.handleExit(code)
            }
        }

        do {
            try process.start(
                executable: toolchain.scrcpy,
                arguments: arguments,
                environment: toolchain.scrcpyEnvironment(serverPort: adbPort)
            )
        } catch {
            status = .failed(error.localizedDescription)
            hint = "scrcpy could not be started. Open Settings → Tools to repair the bundled tools."
            append(.error, "Could not launch scrcpy: \(error.localizedDescription)")
            self.process = nil
            return
        }

        self.process = process
        scheduleStartupFallback()
    }

    func stop() {
        guard let process else {
            status = .idle
            return
        }
        guard !stopRequested else { return }
        stopRequested = true
        status = .stopping
        append(.system, "Closing the DeX window…")
        process.terminate()
    }

    /// Best-effort synchronous shutdown used when the app terminates.
    func terminateForShutdown() {
        startupWatchdog?.cancel()
        process?.interrupt()
    }

    // MARK: Output

    private func receive(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .newlines)
        guard !line.isEmpty else { return }

        let isError = line.contains("ERROR:")
        append(isError ? .error : .output, line)

        if let message = Self.diagnosis(for: line) {
            hint = message
        }

        if case .starting = status,
           line.contains("New display id:") || line.contains("Texture:") || line.contains("Renderer:") {
            status = .running
            startupWatchdog?.cancel()
        }

        if case .failed = status {
            // A new log line does not clear a hard failure.
        }
    }

    private func handleExit(_ code: Int32) {
        startupWatchdog?.cancel()
        process = nil
        startedAt = nil

        if stopRequested {
            stopRequested = false
            status = .idle
            append(.system, "DeX session closed.")
            return
        }

        if code == 0 {
            status = .idle
            append(.system, "DeX session closed.")
        } else {
            let message = "scrcpy exited with code \(code)."
            status = .failed(message)
            if hint == nil {
                hint = Self.diagnosisForExit(code: code)
            }
            append(.error, message)
        }
    }

    private func scheduleStartupFallback() {
        startupWatchdog?.cancel()
        startupWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if case .starting = self.status, self.process != nil {
                self.status = .running
            }
        }
    }

    // MARK: Log helpers

    private func append(_ level: LogEntry.Level, _ text: String) {
        entries.append(LogEntry(date: Date(), level: level, text: text))
        if entries.count > 1500 {
            entries.removeFirst(entries.count - 1500)
        }
    }

    func clearLog() {
        entries.removeAll()
    }

    var logText: String {
        entries.map { entry in
            let prefix: String
            switch entry.level {
            case .system: prefix = "•"
            case .output: prefix = " "
            case .error: prefix = "!"
            }
            return "\(prefix) \(entry.text)"
        }.joined(separator: "\n")
    }

    // MARK: Diagnosis

    static func diagnosis(for line: String) -> String? {
        let lower = line.lowercased()

        if lower.contains("unauthorized") {
            return "Unlock your phone and tap Allow on the “Allow USB debugging?” prompt, then start DeX again."
        }
        if lower.contains("add_trusted_display") || lower.contains("could not create display") {
            return "This phone could not create a DeX display. DeX on Mac needs One UI 8 (Android 16) or newer."
        }
        if lower.contains("could not find any adb device") || lower.contains("device disconnected") || lower.contains("lost connection") {
            return "The phone disconnected. Check the cable, or connect over Wi-Fi and try again."
        }
        if lower.contains("no route to host") || lower.contains("connection refused") {
            return "The phone is not reachable over Wi-Fi. Keep both devices on the same network, and turn off VPNs or AP isolation."
        }
        if lower.contains("failed to connect") {
            return "adb could not connect to the phone. Reconnect it and try again."
        }
        if lower.contains("could not start adb server") {
            return "adb could not start. Open Settings → Tools to repair the bundled tools."
        }
        if lower.contains("scrcpy-server") && lower.contains("no such file") {
            return "The scrcpy server file is missing. Reinstall the tools in Settings → Tools."
        }
        if lower.contains("address already in use") {
            return "Another app is using the adb port. Quit Android Studio's adb or enable “Use an isolated adb server” in Settings."
        }
        return nil
    }

    static func diagnosisForExit(code: Int32) -> String {
        "scrcpy stopped unexpectedly (exit code \(code)). Check the log below for details."
    }
}
