import CryptoKit
import Foundation

/// Downloads the latest scrcpy release (which also contains adb) into application support.
@MainActor
public final class ToolInstaller: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case checking
        case downloading(version: String, progress: Double)
        case verifying
        case extracting
        case done(version: String)
        case failed(String)

        public var isBusy: Bool {
            switch self {
            case .checking, .downloading, .verifying, .extracting: return true
            case .idle, .done, .failed: return false
            }
        }
    }

    @Published public private(set) var phase: Phase = .idle

    public init() {}

    public var statusText: String {
        switch phase {
        case .idle:
            return ""
        case .checking:
            return "Looking up the latest scrcpy release…"
        case .downloading(let version, let progress):
            return "Downloading scrcpy \(version) — \(Int(progress * 100))%"
        case .verifying:
            return "Verifying the download…"
        case .extracting:
            return "Installing adb and scrcpy…"
        case .done(let version):
            return "scrcpy \(version) installed."
        case .failed(let message):
            return message
        }
    }

    public func installLatest() async {
        guard !phase.isBusy else { return }

        do {
            phase = .checking

            let release = try await fetchLatestRelease()
            let version = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName

            let architecture: String
            #if arch(arm64)
            architecture = "aarch64"
            #else
            architecture = "x86_64"
            #endif

            guard let archive = release.assets.first(where: {
                $0.name.hasPrefix("scrcpy-macos-\(architecture)-") && $0.name.hasSuffix(".tar.gz")
            }) else {
                throw InstallerError.noCompatibleAsset(architecture)
            }

            let workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeXMacInstall-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            let archiveURL = workDirectory.appendingPathComponent(archive.name)

            phase = .downloading(version: version, progress: 0)
            try await Downloader.download(from: archive.browserDownloadURL, to: archiveURL) { [weak self] progress in
                Task { @MainActor in
                    if case .downloading(let currentVersion, _) = self?.phase {
                        self?.phase = .downloading(version: currentVersion, progress: progress)
                    }
                }
            }

            phase = .verifying
            try await verify(archive: archiveURL, named: archive.name, release: release, workDirectory: workDirectory)

            phase = .extracting
            let installedVersion = try await extractAndInstall(archive: archiveURL, workDirectory: workDirectory, version: version)

            phase = .done(version: installedVersion)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Release lookup

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Genymobile/scrcpy/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DeXMac", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstallerError.badResponse
        }
        do {
            return try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw InstallerError.badRelease
        }
    }

    // MARK: - Verification

    private func verify(archive: URL, named name: String, release: Release, workDirectory: URL) async throws {
        guard let sumsAsset = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }) else {
            throw InstallerError.missingChecksums
        }

        let (data, response) = try await URLSession.shared.data(from: sumsAsset.browserDownloadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstallerError.badResponse
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw InstallerError.missingChecksums
        }

        var expected: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { continue }
            let checksum = parts[0]
            let filename = parts.last?.trimmingCharacters(in: CharacterSet(charactersIn: "*")) ?? ""
            if filename == name {
                expected = checksum.lowercased()
                break
            }
        }

        guard let expected else { throw InstallerError.missingChecksums }

        let archiveData = try Data(contentsOf: archive)
        let actual = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw InstallerError.checksumMismatch
        }
    }

    // MARK: - Extraction

    private func extractAndInstall(archive: URL, workDirectory: URL, version: String) async throws -> String {
        let fm = FileManager.default
        let extractDirectory = workDirectory.appendingPathComponent("extract", isDirectory: true)
        try fm.createDirectory(at: extractDirectory, withIntermediateDirectories: true)

        let tar = try await ProcessRunner.shared.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archive.path, "-C", extractDirectory.path],
            timeout: 90
        )
        guard tar.succeeded else {
            throw InstallerError.extractionFailed(tar.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let contents = try fm.contentsOfDirectory(at: extractDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        guard let source = contents.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
                ?? contents.first else {
            throw InstallerError.extractionFailed("The archive was empty.")
        }

        let candidates = ["scrcpy", "adb", "scrcpy-server"]
        for name in candidates {
            let file = source.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else {
                throw InstallerError.extractionFailed("The archive did not contain \(name).")
            }
        }

        // Make sure the binary actually runs on this Mac before installing it.
        let test = try? await ProcessRunner.shared.run(source.appendingPathComponent("scrcpy"), arguments: ["--version"], timeout: 15)
        guard let test, test.succeeded else {
            throw InstallerError.invalidBinary
        }

        let destination = Toolchain.applicationSupportToolsDirectory
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        for name in ["scrcpy", "adb", "scrcpy-server", "LICENSE", "scrcpy.1"] {
            let from = source.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: to.path) {
                try fm.removeItem(at: to)
            }
            try fm.copyItem(at: from, to: to)
        }

        for name in ["scrcpy", "adb"] {
            let binary = destination.appendingPathComponent(name)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }

        // Strip quarantine so macOS can launch the freshly downloaded tools.
        _ = try? await ProcessRunner.shared.run(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", destination.path],
            timeout: 20
        )

        let metadata = ["version": version, "installedAt": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted]) {
            try? data.write(to: destination.appendingPathComponent("installed.json"))
        }

        return version
    }

    // MARK: - Errors

    private enum InstallerError: LocalizedError {
        case badResponse
        case badRelease
        case noCompatibleAsset(String)
        case missingChecksums
        case checksumMismatch
        case extractionFailed(String)
        case invalidBinary
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "GitHub returned an unexpected response. Check your internet connection and try again."
            case .badRelease:
                return "Could not read the latest scrcpy release information."
            case .noCompatibleAsset(let architecture):
                return "No scrcpy build is available for \(architecture) Macs."
            case .missingChecksums:
                return "The download could not be verified (checksums were missing)."
            case .checksumMismatch:
                return "The download failed verification. Please try again."
            case .extractionFailed(let detail):
                return detail.isEmpty ? "The download could not be unpacked." : "Unpacking failed: \(detail)"
            case .invalidBinary:
                return "The downloaded scrcpy could not run on this Mac."
            case .downloadFailed(let detail):
                return detail
            }
        }
    }
}

// MARK: - Downloading

private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let completion: @Sendable (Result<Void, Error>) -> Void
    private let lock = NSLock()
    private var finished = false
    private var session: URLSession?

    private init(
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.destination = destination
        self.progress = progress
        self.completion = completion
    }

    static func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = Downloader(destination: destination, progress: progress) { result in
                continuation.resume(with: result)
            }

            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 900
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.session = session

            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let fm = FileManager.default
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else {
            finish(.success(()))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let session = self.session
        lock.unlock()

        completion(result)
        session?.finishTasksAndInvalidate()
    }
}
