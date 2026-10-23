import Foundation

public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }

    public var combined: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public var succeeded: Bool { status == 0 }
}

public enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    case timedOut(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return "Could not run the command: \(message)"
        case .timedOut(let command): return "\(command) timed out."
        case .failed(let message): return message
        }
    }
}

/// Runs a helper binary and collects its output. Safe to call from any actor.
public final class ProcessRunner: @unchecked Sendable {
    public static let shared = ProcessRunner()

    public init() {}

    public func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 20
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let timedOut = Locked(false)
        let killer = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set(true)
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()

        read(pipe: stdoutPipe, into: outBox, group: group)
        read(pipe: stderrPipe, into: errBox, group: group)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                group.wait()
                continuation.resume()
            }
        }

        if timedOut.value {
            throw ProcessRunnerError.timedOut(executable.lastPathComponent)
        }

        return ProcessOutput(
            status: process.terminationStatus,
            stdout: String(decoding: outBox.value, as: UTF8.self),
            stderr: String(decoding: errBox.value, as: UTF8.self)
        )
    }

    private func read(pipe: Pipe, into box: DataBox, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            box.append(pipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
    }
}

// MARK: - Helpers

final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

// MARK: - Streaming process

/// A long-running process (scrcpy) whose output is delivered line by line.
public final class LineProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var readers: [Task<Void, Never>] = []

    public var onLine: (@Sendable (String) -> Void)?
    public var onExit: (@Sendable (Int32) -> Void)?

    public init() {}

    public var isRunning: Bool { process.isRunning }

    public func start(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let lineHandler = onLine
        let exitHandler = onExit

        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            guard let exitHandler else { return }
            // Give the pipe readers a moment to drain the final lines.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                exitHandler(status)
            }
        }

        try process.run()

        readers.append(Self.pump(pipe: stdoutPipe, handler: lineHandler))
        readers.append(Self.pump(pipe: stderrPipe, handler: lineHandler))
    }

    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        let running = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            if running.isRunning {
                kill(running.processIdentifier, SIGKILL)
            }
        }
    }

    public func interrupt() {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGTERM)
    }

    private static func pump(
        pipe: Pipe,
        handler: (@Sendable (String) -> Void)?
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            guard let handler else { return }
            let handle = pipe.fileHandleForReading
            do {
                for try await line in handle.bytes.lines {
                    handler(line)
                }
            } catch {
                // Stream closed.
            }
        }
    }
}
