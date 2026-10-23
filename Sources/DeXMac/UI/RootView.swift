import DeXCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Preferences
    @EnvironmentObject private var session: SessionController

    @State private var showWelcome = false
    @State private var didCheckWelcome = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 262, ideal: 292, max: 340)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .toolbar { toolbar }
        .sheet(isPresented: $app.isPairingSheetPresented) {
            WirelessPairingView()
                .environmentObject(app)
                .environmentObject(prefs)
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView {
                prefs.hasOnboarded = true
                showWelcome = false
            }
            .environmentObject(app)
            .environmentObject(prefs)
        }
        .alert(
            "Something needs attention",
            isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
        .overlay(alignment: .top) { toast }
        .animation(.easeOut(duration: 0.25), value: app.statusMessage)
        .task {
            await app.bootstrap()
            guard !didCheckWelcome else { return }
            didCheckWelcome = true
            if !prefs.hasOnboarded {
                showWelcome = true
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let device = app.selectedDevice {
            DeviceDetailView(device: device)
        } else {
            EmptyStateView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await app.refreshDevices() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(app.isRefreshing || !app.toolStatus.isReady)
            .help("Refresh devices")

            Button {
                app.presentPairing()
            } label: {
                Image(systemName: "wifi")
            }
            .help("Connect over Wi-Fi")

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = app.statusMessage {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(message)
                    .font(.callout)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            .padding(.top, 12)
            .padding(.horizontal, 24)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}
