import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var session: SessionController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusLine)

        if session.isActive {
            Text(session.status.label)
        }

        Divider()

        Button(session.isActive ? "Stop DeX" : "Start DeX") {
            if session.isActive {
                app.stopDeX()
            } else {
                app.startDeX()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .disabled(session.isActive ? false : !canStart)

        Button("Mirror Phone Screen") {
            app.startDeX(.mirror)
            NSApp.activate(ignoringOtherApps: true)
        }
        .disabled(session.isActive || !canStart)

        Divider()

        Button("Pair over Wi-Fi…") {
            app.presentPairing()
            showMainWindow()
        }

        Button("Reconnect Wi-Fi") {
            Task { await app.reconnectSavedWireless(quiet: false) }
        }
        .disabled(app.wireless.isEmpty || app.isBusy)

        Divider()

        Button("Open DeX for Mac") {
            showMainWindow()
        }

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit DeX for Mac") {
            NSApp.terminate(nil)
        }
    }

    private var canStart: Bool {
        guard let device = app.selectedDevice else { return false }
        return device.isConnected && app.toolStatus.isReady
    }

    private var statusLine: String {
        guard let device = app.selectedDevice else {
            return "No Galaxy connected"
        }
        let state = device.isConnected ? device.transport.label : device.state.label
        return "\(device.displayName) — \(state)"
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
