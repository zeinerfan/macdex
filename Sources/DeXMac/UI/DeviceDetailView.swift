import DeXCore
import SwiftUI

struct DeviceDetailView: View {
    let device: AndroidDevice

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var session: SessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                banners

                if session.isActive || !session.entries.isEmpty {
                    sessionCard
                }

                HStack(alignment: .top, spacing: 18) {
                    desktopCard
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 18) {
                        connectionCard
                        if device.isWireless {
                            streamingCard
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            DeviceGlyph(device: device, size: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text(device.displayName)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StatusPill(
                        text: device.transport.label,
                        systemImage: device.isWireless ? "wifi" : "cable.connector",
                        color: device.isWireless ? .teal : Theme.accent
                    )

                    if device.isConnected {
                        StatusPill(text: "Connected", color: .green)
                    } else {
                        StatusPill(text: device.state.label, color: device.state.color)
                    }

                    if session.isActive {
                        StatusPill(text: "DeX open", systemImage: "display", color: .green)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if session.isActive {
                    Button {
                        app.stopDeX()
                    } label: {
                        Label("Stop DeX", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.red)
                } else {
                    Button {
                        app.startDeX(.desktop)
                    } label: {
                        Label("Start DeX", systemImage: "display")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!device.isConnected || !app.toolStatus.isReady)
                    .keyboardShortcut(.return, modifiers: [.command])
                }

                Menu {
                    Button("Mirror phone screen") {
                        app.startDeX(.mirror)
                    }
                    .disabled(!device.isConnected || session.isActive)

                    if !device.isWireless {
                        Button("Go cable-free…") {
                            Task { await app.enableWireless(for: device) }
                        }
                        .disabled(!device.isConnected || session.isActive || app.isBusy)
                    }

                    Divider()

                    Button("Connect over Wi-Fi…") {
                        app.presentPairing()
                    }

                    Button("Copy diagnostics") {
                        Task {
                            let text = await app.diagnostics()
                            app.copyToPasteboard(text)
                            app.flash("Diagnostics copied.")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []

        if let model = device.modelCode,
           model.caseInsensitiveCompare(device.displayName) != .orderedSame {
            parts.append(model)
        }
        if let android = device.androidDescription {
            parts.append(android)
        }
        if let oneUI = device.oneUIDescription {
            parts.append(oneUI)
        }
        if parts.isEmpty {
            parts.append(device.serial)
        }
        return parts.joined(separator: "  ·  ")
    }

    // MARK: - Banners

    @ViewBuilder
    private var banners: some View {
        if !app.toolStatus.isReady {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("adb and scrcpy need attention")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(app.toolStatus.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SettingsLink {
                    Text("Open Settings")
                }
                .controlSize(.small)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            }
        }

        if device.state == .unauthorized {
            Card("Waiting for your phone", systemImage: "lock.shield") {
                Text("Unlock the phone and tap **Allow** on the “Allow USB debugging?” prompt.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Check again") {
                        Task { await app.refreshDevices() }
                    }
                    .controlSize(.small)

                    Text("Choose “Always allow from this computer” so it only asks once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if case .requiresOneUI8(let current) = device.dexSupport {
            HintBanner(
                text: "This phone reports One UI \(current ?? "7") (Android \(device.metadata.androidRelease ?? "15")). DeX on a virtual display needs One UI 8 (Android 16) or newer. You can still try — older phones may open a plain desktop display instead of DeX.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }

        if device.dexSupport == .notSamsung {
            HintBanner(
                text: "This does not look like a Galaxy phone. DeX is a Samsung feature, so the desktop may look different or not start.",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
    }

    // MARK: - Session

    private var sessionCard: some View {
        Card("DeX session", systemImage: "display") {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(sessionColor.opacity(0.12))
                        .frame(width: 38, height: 38)
                    if case .starting = session.status {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: sessionIcon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(sessionColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.status.label)
                        .font(.system(size: 13, weight: .semibold))

                    if let startedAt = session.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(elapsed(since: startedAt))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } else if case .failed(let message) = session.status {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("The DeX window opens separately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Button(session.isLogVisible ? "Hide log" : "Show log") {
                    session.isLogVisible.toggle()
                }
                .controlSize(.small)

                if session.isActive {
                    Button("Stop") {
                        app.stopDeX()
                    }
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            if let hint = session.hint {
                HintBanner(text: hint)
            }

            if session.isLogVisible {
                LogConsole(entries: session.entries, maxHeight: 200)
            }
        }
    }

    private var sessionColor: Color {
        switch session.status {
        case .starting, .stopping: return .orange
        case .running: return .green
        case .failed: return .red
        case .idle: return .secondary
        }
    }

    private var sessionIcon: String {
        switch session.status {
        case .running: return "checkmark"
        case .failed: return "exclamationmark"
        case .stopping: return "stop.fill"
        case .starting, .idle: return "display"
        }
    }

    private func elapsed(since date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, rest)
        }
        return String(format: "%02d:%02d", minutes, rest)
    }

    // MARK: - Desktop

    private var desktopCard: some View {
        Card("Desktop", systemImage: "display") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("Resolution")
                        .font(.system(size: 12))
                    Spacer()
                    Picker("Resolution", selection: $prefs.resolutionPreset) {
                        ForEach(ResolutionPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                }

                Text(prefs.resolutionPreset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if prefs.resolutionPreset == .custom {
                    HStack(alignment: .bottom, spacing: 8) {
                        numberField("Width", value: $prefs.customWidth)
                        Text("×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                        numberField("Height", value: $prefs.customHeight)
                        Text("@")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 6)
                        numberField("DPI", value: $prefs.customDPI)
                        Spacer()
                    }
                }

                Divider()

                ToggleRow(
                    title: "Resizable desktop",
                    subtitle: "DeX reflows as you resize its window. Experimental on some phones.",
                    isOn: $prefs.flexDisplay
                )

                ToggleRow(
                    title: "Fullscreen",
                    subtitle: "Open DeX over the whole display.",
                    isOn: $prefs.fullscreen
                )

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 11) {
                        ToggleRow(title: "Always on top", isOn: $prefs.alwaysOnTop)
                        ToggleRow(
                            title: "Keep phone awake",
                            subtitle: "Stops the phone sleeping while DeX is open.",
                            isOn: $prefs.keepAwake
                        )
                        ToggleRow(
                            title: "Turn phone screen off",
                            subtitle: "Saves battery; DeX remains visible on the Mac.",
                            isOn: $prefs.turnScreenOff
                        )
                        ToggleRow(
                            title: "Physical keyboard mode",
                            subtitle: "Uses a virtual USB keyboard for fuller shortcut support.",
                            isOn: $prefs.physicalKeyboard
                        )
                        ToggleRow(
                            title: "Forward phone audio",
                            isOn: $prefs.forwardAudio
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Text("More launch options")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text("DPI controls how large the desktop looks: lower is denser, higher is bigger.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func numberField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 74)
        }
    }

    // MARK: - Connection

    private var connectionCard: some View {
        Card("Connection", systemImage: device.isWireless ? "wifi" : "cable.connector") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    StatusDot(color: device.state.color, pulsing: device.isConnected)
                    Text(connectionHeadline)
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    StatusPill(
                        text: device.transport.label,
                        systemImage: device.isWireless ? "wifi" : "cable.connector",
                        color: device.isWireless ? .teal : Theme.accent
                    )
                }

                if device.isWireless {
                    InfoRow(label: "Endpoint", value: device.serial)
                }
                if let model = device.modelCode {
                    InfoRow(label: "Model", value: model)
                }
                if let android = device.androidDescription {
                    InfoRow(label: "System", value: android)
                }
                if let oneUI = device.oneUIDescription {
                    InfoRow(label: "One UI", value: oneUI)
                }

                Divider()

                if device.isWireless {
                    HStack(spacing: 10) {
                        Button("Disconnect") {
                            Task { await app.disconnect(wirelessRecord) }
                        }

                        if savedWirelessRecord != nil {
                            Button("Forget") {
                                Task { await app.forget(wirelessRecord) }
                            }
                        }

                        Spacer()
                    }
                    .controlSize(.small)

                    Text("Wireless debugging stays on until the phone reboots or you turn it off. Reconnect from the sidebar afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button {
                        Task { await app.enableWireless(for: device) }
                    } label: {
                        Label(app.isBusy ? "Switching…" : "Go cable-free", systemImage: "wifi")
                    }
                    .controlSize(.small)
                    .disabled(!device.isConnected || app.isBusy || session.isActive)

                    Text(
                        session.isActive
                            ? "Close DeX before switching this session to Wi-Fi."
                            : "Turns on adb over Wi-Fi using this cable, then you can unplug it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var connectionHeadline: String {
        switch device.state {
        case .device:
            return device.isWireless ? "Connected over Wi-Fi" : "Connected over USB"
        case .unauthorized:
            return "Waiting for approval on the phone"
        default:
            return device.state.label
        }
    }

    private var savedWirelessRecord: WirelessRecord? {
        app.wireless.first(where: { $0.endpoint == device.serial })
    }

    private var wirelessRecord: WirelessRecord {
        savedWirelessRecord
            ?? WirelessRecord(endpoint: device.serial, name: device.displayName, lastUsed: Date())
    }

    // MARK: - Streaming

    private var streamingCard: some View {
        Card("Wi-Fi streaming", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                pickerRow("Video codec") {
                    Picker("Video codec", selection: $prefs.wirelessCodec) {
                        Text("Auto (H.264)").tag("auto")
                        Text("H.265").tag("h265")
                        Text("AV1").tag("av1")
                    }
                }

                pickerRow("Bit rate") {
                    Picker("Bit rate", selection: $prefs.wirelessBitRate) {
                        Text("4 Mbps").tag("4M")
                        Text("6 Mbps").tag("6M")
                        Text("8 Mbps").tag("8M")
                        Text("12 Mbps").tag("12M")
                        Text("16 Mbps").tag("16M")
                    }
                }

                pickerRow("Frame rate") {
                    Picker("Frame rate", selection: $prefs.wirelessMaxFPS) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                        Text("Unlimited").tag(0)
                    }
                }

                pickerRow("Jitter buffer") {
                    Picker("Jitter buffer", selection: $prefs.wirelessBufferMS) {
                        Text("Off").tag(0)
                        Text("25 ms").tag(25)
                        Text("50 ms").tag(50)
                        Text("100 ms").tag(100)
                        Text("150 ms").tag(150)
                    }
                }

                Divider()

                ToggleRow(
                    title: "Audio over Wi-Fi",
                    subtitle: "Adds bandwidth use. Off by default for a smoother desktop.",
                    isOn: $prefs.audioOnWiFi
                )

                Text("H.265 at 8 Mbps with a 50 ms buffer is a good balance of sharpness and smoothness.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pickerRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
            Spacer()
            content()
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
        }
    }
}
