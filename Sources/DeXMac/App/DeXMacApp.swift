import AppKit
import DeXCore
import SwiftUI

@main
struct DeXMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var preferences: Preferences
    @StateObject private var session: SessionController
    @StateObject private var app: AppState

    init() {
        SelfCheck.runIfRequested()

        let preferences = Preferences()
        let session = SessionController()
        let app = AppState(preferences: preferences, session: session)

        _preferences = StateObject(wrappedValue: preferences)
        _session = StateObject(wrappedValue: session)
        _app = StateObject(wrappedValue: app)
    }

    var body: some Scene {
        Window("DeX for Mac", id: "main") {
            RootView()
                .environmentObject(app)
                .environmentObject(preferences)
                .environmentObject(session)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1080, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("DeX") {
                Button("Start DeX") {
                    app.startDeX()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(app.session.isActive || app.selectedDevice == nil)

                Button("Stop DeX") {
                    app.stopDeX()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!app.session.isActive)

                Divider()

                Button("Mirror Phone Screen") {
                    app.startDeX(.mirror)
                }
                .disabled(app.session.isActive || app.selectedDevice == nil)

                Button("Connect over Wi-Fi…") {
                    app.presentPairing()
                    NSApp.activate(ignoringOtherApps: true)
                }

                Button("Reconnect Wi-Fi") {
                    Task { await app.reconnectSavedWireless(quiet: false) }
                }
                .disabled(app.wireless.isEmpty)

                Divider()

                Button("Copy Diagnostics") {
                    Task {
                        let text = await app.diagnostics()
                        app.copyToPasteboard(text)
                        app.flash("Diagnostics copied to the clipboard.")
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(app)
                .environmentObject(preferences)
                .environmentObject(session)
        } label: {
            MenuBarLabel(active: session.isActive)
        }

        Settings {
            SettingsView()
                .environmentObject(app)
                .environmentObject(preferences)
                .environmentObject(session)
        }
    }
}

private struct MenuBarLabel: View {
    let active: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "display")
            if active {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 1)
            }
        }
        .accessibilityLabel(active ? "DeX is running" : "DeX for Mac")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            SessionController.current?.terminateForShutdown()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
