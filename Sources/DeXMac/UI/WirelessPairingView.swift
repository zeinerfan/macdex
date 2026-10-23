import DeXCore
import SwiftUI

struct WirelessPairingView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var pairingPort = ""
    @State private var code = ""
    @State private var connectPort = ""

    @FocusState private var focus: Field?

    private enum Field {
        case host
        case pairingPort
        case code
        case connectPort
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let success = app.pairingSuccess {
                        HintBanner(text: success, systemImage: "checkmark.circle.fill", tint: .green)
                    }

                    discovery
                    form

                    if let error = app.pairingError {
                        HintBanner(text: error, systemImage: "exclamationmark.triangle.fill", tint: .red)
                    }

                    instructions
                }
                .padding(22)
            }
            Divider()
            footer
        }
        .frame(width: 580, height: 680)
        .onAppear {
            app.startMDNSScan()
            if host.isEmpty {
                focus = .host
            }
        }
        .onChange(of: app.availablePairingServices) { _, services in
            guard host.isEmpty, let first = services.first else { return }
            host = first.host
            pairingPort = String(first.port)
        }
        .onChange(of: app.wirelessNeedsConnectPort) { _, needsPort in
            if needsPort {
                focus = .connectPort
            }
        }
        .onChange(of: app.pairingSuccess) { _, success in
            guard success != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                if app.pairingSuccess != nil {
                    app.isPairingSheetPresented = false
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent, Theme.accentLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                Image(systemName: "wifi")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect over Wi-Fi")
                    .font(.system(size: 16, weight: .semibold))
                Text("Pair once with a code — then no cable is needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Discovery

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Nearby phones")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if app.availablePairingServices.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Refresh") {
                        Task { await app.refreshMDNS() }
                    }
                    .controlSize(.small)
                }
            }

            if app.availablePairingServices.isEmpty {
                Text("On the phone, open Settings → Developer options → Wireless debugging → **Pair device with pairing code**. Keep that screen open; discovery takes a few seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.availablePairingServices.enumerated()), id: \.element.id) { index, service in
                        if index > 0 {
                            Divider().padding(.leading, 34)
                        }
                        discoveryRow(service)
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                }
            }
        }
    }

    private func discoveryRow(_ service: MDNSService) -> some View {
        Button {
            host = service.host
            pairingPort = String(service.port)
            focus = .code
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(service.host)
                        .font(.system(size: 12, design: .monospaced))
                    Text("Pairing port \(service.port)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Use")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                labeledField("Phone IP address", text: $host, prompt: "192.168.1.42")
                    .focused($focus, equals: .host)

                labeledField("Pairing port", text: $pairingPort, prompt: "41234")
                    .focused($focus, equals: .pairingPort)
                    .frame(width: 118)
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("6-digit pairing code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("6-digit pairing code", text: $code, prompt: Text("123456"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                        .focused($focus, equals: .code)
                }

                labeledField("Connection port (optional)", text: $connectPort, prompt: "37001")
                    .focused($focus, equals: .connectPort)
                    .frame(width: 190)
            }

            Text("The connection port is optional — it is filled in automatically when discovery works. You can also read it on the main Wireless debugging screen.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
    }

    // MARK: - Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Where to find these")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("1.  On the phone: Settings → Developer options → Wireless debugging.")
                .font(.caption)
            Text("2.  Tap **Pair device with pairing code** — the dialog shows the IP, pairing port and a 6-digit code.")
                .font(.caption)
            Text("3.  Enter them here, then press **Pair & Connect**.")
                .font(.caption)
            Text("The phone and Mac must be on the same Wi-Fi network. VPNs and guest networks can block pairing.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if app.isPairing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(app.isPairing ? "Talking to your phone…" : "Wireless DeX uses about 8 Mbps while active.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Cancel") {
                dismiss()
            }

            Button(app.wirelessNeedsConnectPort ? "Connect" : "Pair & Connect") {
                Task { await submit() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit || app.isPairing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var canSubmit: Bool {
        if app.wirelessNeedsConnectPort {
            return validPort(connectPort)
        }
        return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validPort(pairingPort)
            && (4...10).contains(code.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && Int(code.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    private func validPort(_ text: String) -> Bool {
        guard let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (1...65535).contains(port)
    }

    private func submit() async {
        if app.wirelessNeedsConnectPort {
            await app.connectWireless(host: host, port: connectPort)
        } else {
            await app.pairWireless(
                host: host,
                pairingPort: pairingPort,
                code: code,
                connectPort: connectPort
            )
        }
    }
}
