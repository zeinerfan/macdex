import DeXCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionController

    var body: some View {
        List(selection: $app.selectedSerial) {
            Section {
                if app.devices.isEmpty {
                    emptyDeviceList
                } else {
                    ForEach(app.devices) { device in
                        DeviceRow(device: device)
                            .tag(device.serial)
                            .contextMenu {
                                Button("Start DeX") {
                                    app.selectedSerial = device.serial
                                    app.startDeX()
                                }
                                .disabled(!device.isConnected || session.isActive)

                                if !device.isWireless {
                                    Button("Go cable-free") {
                                        app.selectedSerial = device.serial
                                        Task { await app.enableWireless(for: device) }
                                    }
                                    .disabled(!device.isConnected || session.isActive || app.isBusy)
                                }

                                Divider()

                                Button("Copy serial number") {
                                    app.copyToPasteboard(device.serial)
                                    app.flash("Serial copied.")
                                }
                            }
                    }
                }
            } header: {
                Text("Devices")
            }

            if !app.wireless.isEmpty {
                Section {
                    ForEach(app.wireless) { record in
                        WirelessRow(record: record)
                    }
                } header: {
                    Text("Saved Wi-Fi")
                }
            }

            Section {
                Button {
                    app.presentPairing()
                } label: {
                    Label("Pair over Wi-Fi…", systemImage: "plus.circle")
                        .font(.system(size: 12.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private var emptyDeviceList: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.secondary)
                Text("No phone connected")
                    .font(.system(size: 12.5, weight: .medium))
            }
            Text("Plug in a Galaxy with USB debugging on, or pair it over Wi-Fi.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Pair over Wi-Fi…") {
                app.presentPairing()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let toolchain = app.toolchain, toolchain.isValid {
                        Text("scrcpy \(toolchain.scrcpyVersion ?? "?") · adb \(toolchain.adbVersion ?? "?")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var statusColor: Color {
        switch app.toolStatus {
        case .ready:
            return .green
        case .checking:
            return .orange
        case .missing, .failed:
            return .red
        }
    }

    private var statusTitle: String {
        switch app.toolStatus {
        case .ready:
            return app.toolchain.map { "Ready · \($0.origin.label)" } ?? "Ready"
        case .checking:
            return "Checking tools…"
        case .missing:
            return "Tools not installed"
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Device row

private struct DeviceRow: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: 10) {
            DeviceGlyph(device: device, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: device.isWireless ? "wifi" : "cable.connector")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text(device.transport.label)

                    if device.state != .device {
                        Text("·")
                        Text(device.state.label)
                    } else if let oneUI = device.oneUIDescription {
                        Text("·")
                        Text(oneUI)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            StatusDot(color: device.state.color, pulsing: device.isConnected)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Wireless row

private struct WirelessRow: View {
    let record: WirelessRecord

    @EnvironmentObject private var app: AppState

    private var isConnected: Bool {
        app.isWirelessConnected(record)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 17)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.name)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Text(record.endpoint)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isConnected {
                StatusDot(color: .green)
            } else {
                Button("Connect") {
                    Task { await app.connect(to: record) }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(app.isBusy)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Connect") {
                Task { await app.connect(to: record) }
            }
            .disabled(isConnected)

            Button("Disconnect") {
                Task { await app.disconnect(record) }
            }
            .disabled(!isConnected)

            Divider()

            Button("Forget") {
                Task { await app.forget(record) }
            }
        }
    }
}
