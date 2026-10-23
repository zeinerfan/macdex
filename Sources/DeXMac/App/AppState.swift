import AppKit
import Combine
import DeXCore
import Foundation

enum ToolStatus: Equatable {
    case checking
    case ready
    case missing
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .checking: return "Checking adb and scrcpy…"
        case .ready: return "Ready"
        case .missing: return "adb and scrcpy were not found."
        case .failed(let message): return message
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    // Devices
    @Published private(set) var devices: [AndroidDevice] = []
    @Published var selectedSerial: String?
    @Published private(set) var isRefreshing = false

    // Tools
    @Published private(set) var toolchain: Toolchain?
    @Published private(set) var toolStatus: ToolStatus = .checking

    // Wireless
    @Published private(set) var wireless: [WirelessRecord] = WirelessStore.load()
    @Published private(set) var mdnsServices: [MDNSService] = []
    @Published var isPairingSheetPresented = false {
        didSet {
            if isPairingSheetPresented {
                startMDNSScan()
            } else {
                stopMDNSScan()
            }
        }
    }
    @Published var isBusy = false
    @Published var isPairing = false
    @Published var pairingError: String?
    @Published var pairingSuccess: String?
    @Published var wirelessNeedsConnectPort = false

    // Messages
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    let preferences: Preferences
    let session: SessionController

    private var adb: ADBClient?
    private var monitorTask: Task<Void, Never>?
    private var mdnsTask: Task<Void, Never>?
    private var didBootstrap = false
    private var metadataCache: [String: DeviceMetadata] = [:]
    private var metadataInFlight: Set<String> = []
    private var metadataFailures: [String: Int] = [:]

    init(preferences: Preferences, session: SessionController) {
        self.preferences = preferences
        self.session = session

        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        await refreshTools()
        startMonitoring()
    }

    func refreshTools() async {
        toolStatus = .checking
        metadataCache.removeAll()
        metadataInFlight.removeAll()
        metadataFailures.removeAll()

        let customADB = preferences.customADBPath.isEmpty ? nil : preferences.customADBPath
        let customScrcpy = preferences.customScrcpyPath.isEmpty ? nil : preferences.customScrcpyPath

        guard var found = Toolchain.locate(customADB: customADB, customScrcpy: customScrcpy) else {
            toolchain = nil
            adb = nil
            toolStatus = .missing
            return
        }

        found = await found.validating()

        guard found.isValid else {
            toolchain = nil
            adb = nil
            toolStatus = .failed("adb and scrcpy were found, but could not be launched. Reinstall the tools below.")
            return
        }

        toolchain = found
        let client = ADBClient(toolchain: found, serverPort: preferences.adbServerPort)
        adb = client
        toolStatus = .ready

        await client.startServer()
        await refreshDevices()

        if preferences.autoReconnect, !wireless.isEmpty {
            Task { [weak self] in
                await self?.reconnectSavedWireless(quiet: true)
            }
        }
    }

    func updateServerConfiguration() async {
        guard let toolchain else { return }
        let client = ADBClient(toolchain: toolchain, serverPort: preferences.adbServerPort)
        adb = client
        await client.startServer()
        await refreshDevices()
    }

    // MARK: - Device monitoring

    private func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDevices()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func refreshDevices() async {
        guard let adb, toolStatus.isReady, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fresh = try await adb.devices()
            var merged: [AndroidDevice] = []
            for device in fresh {
                var copy = device
                if let cached = metadataCache[device.serial] {
                    copy = copy.applying(cached)
                }
                merged.append(copy)
            }

            devices = merged.sorted { lhs, rhs in
                if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

            // Keep a valid selection when possible.
            if let selected = selectedSerial,
               !devices.contains(where: { $0.serial == selected }) {
                selectedSerial = devices.first(where: { $0.isConnected })?.serial ?? devices.first?.serial
            } else if selectedSerial == nil {
                selectedSerial = devices.first(where: { $0.isConnected })?.serial ?? devices.first?.serial
            }

            for device in devices where device.isConnected && !device.metadata.loaded {
                loadMetadata(for: device.serial)
            }
        } catch {
            // A failed poll (for example while adb restarts) should not raise an alert.
        }
    }

    private func loadMetadata(for serial: String) {
        guard let adb,
              !metadataInFlight.contains(serial),
              (metadataFailures[serial] ?? 0) < 3 else { return }

        metadataInFlight.insert(serial)
        Task { [weak self] in
            let metadata = await adb.metadata(serial: serial)
            guard let self else { return }
            self.metadataInFlight.remove(serial)

            if let metadata {
                self.metadataCache[serial] = metadata
                if let index = self.devices.firstIndex(where: { $0.serial == serial }) {
                    self.devices[index] = self.devices[index].applying(metadata)
                }
            } else {
                self.metadataFailures[serial, default: 0] += 1
            }
        }
    }

    var selectedDevice: AndroidDevice? {
        if let selectedSerial,
           let device = devices.first(where: { $0.serial == selectedSerial }) {
            return device
        }
        return devices.first(where: { $0.isConnected }) ?? devices.first
    }

    func device(for serial: String) -> AndroidDevice? {
        devices.first(where: { $0.serial == serial })
    }

    // MARK: - Launching

    func startDeX(_ mode: LaunchMode = .desktop) {
        guard let device = selectedDevice else {
            errorMessage = "Connect a Galaxy phone over USB or Wi-Fi first."
            return
        }
        guard device.isConnected else {
            if device.state == .unauthorized {
                errorMessage = "Unlock your phone and tap Allow on the “Allow USB debugging?” prompt, then try again."
            } else {
                errorMessage = "This device is \(device.state.label.lowercased()). Reconnect it and try again."
            }
            return
        }
        guard let toolchain, toolchain.isValid, toolStatus.isReady else {
            errorMessage = "adb and scrcpy are not ready. Open Settings → Tools to install or repair them."
            return
        }
        guard !session.isActive else { return }

        session.start(
            configuration: scrcpyConfiguration(for: device, mode: mode),
            toolchain: toolchain,
            adbPort: preferences.adbServerPort
        )
    }

    func toggleDeX() {
        if session.isActive {
            session.stop()
        } else {
            startDeX()
        }
    }

    func stopDeX() {
        session.stop()
    }

    private func scrcpyConfiguration(for device: AndroidDevice, mode: LaunchMode) -> ScrcpyLaunchConfiguration {
        let size = preferences.displaySize
        let wireless = device.isWireless

        return ScrcpyLaunchConfiguration(
            serial: device.serial,
            deviceName: device.displayName,
            mode: mode,
            width: size?.width ?? 0,
            height: size?.height ?? 0,
            dpi: size?.dpi ?? 0,
            flexDisplay: preferences.flexDisplay && mode == .desktop,
            fullscreen: preferences.fullscreen,
            alwaysOnTop: preferences.alwaysOnTop,
            keepAwake: preferences.keepAwake,
            turnScreenOff: preferences.turnScreenOff,
            physicalKeyboard: preferences.physicalKeyboard,
            forwardAudio: preferences.forwardAudio && (!wireless || preferences.audioOnWiFi),
            wireless: wireless,
            stream: preferences.wirelessStream
        )
    }

    // MARK: - Wireless: one-click cable-free

    func enableWireless(for device: AndroidDevice) async {
        guard let adb else { return }
        guard device.isConnected, !device.isWireless else {
            if device.isWireless {
                flash("This device is already connected over Wi-Fi.")
            }
            return
        }

        isBusy = true
        defer { isBusy = false }

        guard let ip = await adb.wlanIP(serial: device.serial) else {
            errorMessage = "Couldn't find the phone's Wi-Fi address. Connect the phone to Wi-Fi with the cable still plugged in, then try again."
            return
        }

        let port = 5555
        let tcpip = await adb.enableTCPIP(serial: device.serial, port: port)
        guard tcpip.ok else {
            errorMessage = "Could not switch the phone to wireless debugging.\n\n\(normalized(tcpip.message))"
            return
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let endpoint = "\(ip):\(port)"
        var outcome = await adb.connect(endpoint, timeout: 12)
        if !outcome.ok {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            outcome = await adb.connect(endpoint, timeout: 12)
        }

        guard outcome.ok else {
            errorMessage = "The phone is at \(ip), but adb could not connect. Make sure the Mac and phone are on the same Wi-Fi network (not a guest network or VPN).\n\n\(normalized(outcome.message))"
            return
        }

        saveWireless(endpoint: endpoint, name: device.displayName)
        flash("Wireless DeX is ready — you can unplug the cable.")
        await refreshDevices()
        if devices.contains(where: { $0.serial == endpoint }) {
            selectedSerial = endpoint
        }
    }

    // MARK: - Wireless: pairing with a code

    func pairWireless(host: String, pairingPort: String, code: String, connectPort: String) async {
        guard let adb else {
            pairingError = "adb is not ready. Open Settings → Tools."
            return
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            pairingError = "Enter the phone's IP address (shown on the Wireless debugging screen)."
            return
        }
        guard let port = Int(pairingPort.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(port) else {
            pairingError = "Enter the pairing port from the “Pair device with pairing code” dialog."
            return
        }
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...10).contains(trimmedCode.count), Int(trimmedCode) != nil else {
            pairingError = "Enter the 6-digit pairing code shown on your phone."
            return
        }

        isPairing = true
        pairingError = nil
        pairingSuccess = nil
        wirelessNeedsConnectPort = false
        defer { isPairing = false }

        let pairEndpoint = MDNSService.formatEndpoint(host: trimmedHost, port: port)
        let result = await adb.pair(endpoint: pairEndpoint, code: trimmedCode)
        guard result.ok else {
            pairingError = "Pairing failed. Make sure the code is current (they expire quickly) and both devices are on the same Wi-Fi network.\n\n\(normalized(result.message))"
            return
        }

        let requestedPort = Int(connectPort.trimmingCharacters(in: .whitespacesAndNewlines))
        let discoveredPort = mdnsServices.first(where: {
            $0.kind == .connect && $0.host == trimmedHost
        })?.port
        let resolvedPort = (requestedPort.flatMap { (1...65535).contains($0) ? $0 : nil }) ?? discoveredPort

        guard let resolvedPort else {
            wirelessNeedsConnectPort = true
            pairingError = "Paired successfully. Now enter the connection port shown on the main Wireless debugging screen (it is different from the pairing port), then press Pair & Connect again."
            return
        }

        await connectWireless(host: trimmedHost, port: String(resolvedPort))
    }

    /// Connects to a phone whose Wireless debugging is already paired.
    func connectWireless(host: String, port: String) async {
        guard let adb else {
            pairingError = "adb is not ready. Open Settings → Tools."
            return
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            pairingError = "Enter the phone's IP address."
            return
        }
        guard let portNumber = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(portNumber) else {
            pairingError = "Enter the connection port shown on the Wireless debugging screen."
            return
        }

        let managesSpinner = !isPairing
        if managesSpinner { isPairing = true }
        defer { if managesSpinner { isPairing = false } }

        pairingError = nil
        pairingSuccess = nil

        let endpoint = MDNSService.formatEndpoint(host: trimmedHost, port: portNumber)
        var outcome = await adb.connect(endpoint)
        if !outcome.ok {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            outcome = await adb.connect(endpoint)
        }

        guard outcome.ok else {
            pairingError = "Could not connect to \(endpoint). Check that Wireless debugging is still on, then try again.\n\n\(normalized(outcome.message))"
            return
        }

        var name = "Galaxy over Wi-Fi"
        if let metadata = await adb.metadata(serial: endpoint) {
            metadataCache[endpoint] = metadata
            name = metadata.marketName ?? metadata.model ?? name
        }

        wirelessNeedsConnectPort = false
        saveWireless(endpoint: endpoint, name: name)
        pairingSuccess = "Connected to \(name)"
        flash("Wireless DeX is ready.")
        await refreshDevices()
        selectedSerial = endpoint
    }

    func startMDNSScan() {
        guard mdnsTask == nil else { return }
        mdnsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMDNS()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stopMDNSScan() {
        mdnsTask?.cancel()
        mdnsTask = nil
    }

    func refreshMDNS() async {
        guard let adb else { return }
        mdnsServices = await adb.mdnsServices()
    }

    var availablePairingServices: [MDNSService] {
        mdnsServices.filter { $0.kind == .pairing }
    }

    // MARK: - Saved wireless devices

    func connect(to record: WirelessRecord) async {
        guard let adb else { return }
        isBusy = true
        defer { isBusy = false }

        var outcome = await adb.connect(record.endpoint)
        if !outcome.ok {
            try? await Task.sleep(nanoseconds: 800_000_000)
            outcome = await adb.connect(record.endpoint)
        }

        if outcome.ok {
            touch(record)
            flash("Connected to \(record.name).")
            await refreshDevices()
            if devices.contains(where: { $0.serial == record.endpoint }) {
                selectedSerial = record.endpoint
            }
        } else {
            errorMessage = "Could not reach \(record.name) at \(record.endpoint). Turn on Wireless debugging on the phone and keep both devices on the same Wi-Fi network.\n\n\(normalized(outcome.message))"
        }
    }

    func disconnect(_ record: WirelessRecord) async {
        guard let adb else { return }
        await adb.disconnect(record.endpoint)
        if selectedSerial == record.endpoint {
            selectedSerial = nil
        }
        await refreshDevices()
        flash("Disconnected \(record.name).")
    }

    func forget(_ record: WirelessRecord) async {
        await adb?.disconnect(record.endpoint)
        wireless.removeAll { $0.endpoint == record.endpoint }
        WirelessStore.save(wireless)
        if selectedSerial == record.endpoint {
            selectedSerial = nil
        }
        flash("Removed \(record.name).")
    }

    func reconnectSavedWireless(quiet: Bool) async {
        guard let adb, !wireless.isEmpty else { return }

        isBusy = true
        defer { isBusy = false }

        var connected: [String] = []
        for record in wireless {
            let outcome = await adb.connect(record.endpoint, timeout: 8)
            if outcome.ok {
                connected.append(record.name)
                touch(record)
            }
        }

        await refreshDevices()

        if !quiet {
            if connected.isEmpty {
                errorMessage = "No saved Wi-Fi device responded. Turn on Wireless debugging on the phone, or pair it again."
            } else {
                flash("Reconnected to \(connected.joined(separator: ", ")).")
            }
        }
    }

    private func saveWireless(endpoint: String, name: String) {
        var records = wireless.filter { $0.endpoint != endpoint }
        records.insert(WirelessRecord(endpoint: endpoint, name: name, lastUsed: Date()), at: 0)
        wireless = records
        WirelessStore.save(records)
    }

    private func touch(_ record: WirelessRecord) {
        guard let index = wireless.firstIndex(where: { $0.endpoint == record.endpoint }) else { return }
        wireless[index].lastUsed = Date()
        wireless.sort { $0.lastUsed > $1.lastUsed }
        WirelessStore.save(wireless)
    }

    func isWirelessConnected(_ record: WirelessRecord) -> Bool {
        devices.contains { $0.serial == record.endpoint && $0.isConnected }
    }

    // MARK: - Presentation helpers

    func presentPairing() {
        pairingError = nil
        pairingSuccess = nil
        wirelessNeedsConnectPort = false
        isPairingSheetPresented = true
    }

    func flash(_ message: String) {
        statusMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.statusMessage == message else { return }
            self.statusMessage = nil
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func copySessionLog() {
        copyToPasteboard(session.logText)
        flash("Log copied to the clipboard.")
    }

    func diagnostics() async -> String {
        var lines: [String] = []
        lines.append("DeX for Mac \(AppInfo.version) (\(AppInfo.build))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")

        if let toolchain {
            lines.append("Tools: \(toolchain.origin.label)")
            lines.append("scrcpy: \(toolchain.scrcpyVersion ?? "unknown") — \(toolchain.scrcpy.path)")
            lines.append("adb: \(toolchain.adbVersion ?? "unknown") — \(toolchain.adb.path)")
        } else {
            lines.append("Tools: not found")
        }
        lines.append("Tool status: \(toolStatus.message)")
        lines.append("Isolated adb server: \(preferences.isolatedADBServer ? "yes (5038)" : "no")")
        lines.append("Selected device: \(selectedDevice?.serial ?? "none")")
        lines.append("")

        if let adb {
            lines.append("adb devices -l:")
            let raw = await adb.rawDevices()
            lines.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")

            lines.append("Saved Wi-Fi endpoints:")
            if wireless.isEmpty {
                lines.append("  (none)")
            } else {
                for record in wireless {
                    lines.append("  \(record.endpoint) — \(record.name)")
                }
            }
            lines.append("")
        }

        lines.append("Session: \(session.status.label)")
        if session.entries.isEmpty {
            lines.append("  (no log output)")
        } else {
            lines.append(session.entries.suffix(80).map(\.text).joined(separator: "\n"))
        }

        return lines.joined(separator: "\n")
    }

    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

// MARK: - App info

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
