import AppKit
import DeXCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }

            StreamingSettingsView()
                .tabItem { Label("Streaming", systemImage: "slider.horizontal.3") }

            ToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 640, height: 560)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Reconnect saved Wi-Fi devices on launch", isOn: $prefs.autoReconnect)
                Toggle("Use an isolated adb server (port 5038)", isOn: $prefs.isolatedADBServer)

                Text("Isolated mode avoids conflicts with Android Studio. Devices connected through another adb server will not be visible here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Display defaults") {
                Picker("Resolution", selection: $prefs.resolutionPreset) {
                    ForEach(ResolutionPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                if prefs.resolutionPreset == .custom {
                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("Width", value: $prefs.customWidth, format: .number)
                            .frame(width: 76)
                        Text("×")
                        TextField("Height", value: $prefs.customHeight, format: .number)
                            .frame(width: 76)
                        Text("@")
                        TextField("DPI", value: $prefs.customDPI, format: .number)
                            .frame(width: 60)
                        Text("dpi")
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Make the DeX window resizable", isOn: $prefs.flexDisplay)
                Toggle("Launch DeX fullscreen", isOn: $prefs.fullscreen)
                Toggle("Keep the DeX window always on top", isOn: $prefs.alwaysOnTop)
            }

            Section("Input & audio") {
                Toggle("Physical keyboard mode (UHID)", isOn: $prefs.physicalKeyboard)
                Toggle("Forward phone audio", isOn: $prefs.forwardAudio)
                Toggle("Allow audio over Wi-Fi", isOn: $prefs.audioOnWiFi)
                Toggle("Keep the phone awake", isOn: $prefs.keepAwake)
                Toggle("Turn the phone screen off during DeX", isOn: $prefs.turnScreenOff)
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.isolatedADBServer) { _, _ in
            Task { await app.updateServerConfiguration() }
        }
    }
}

// MARK: - Streaming

private struct StreamingSettingsView: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section("Wi-Fi video") {
                Picker("Video codec", selection: $prefs.wirelessCodec) {
                    Text("Auto (H.264)").tag("auto")
                    Text("H.265 — better compression").tag("h265")
                    Text("AV1 — newest, not always supported").tag("av1")
                }

                Picker("Bit rate", selection: $prefs.wirelessBitRate) {
                    Text("4 Mbps — conservative").tag("4M")
                    Text("6 Mbps").tag("6M")
                    Text("8 Mbps — balanced").tag("8M")
                    Text("12 Mbps").tag("12M")
                    Text("16 Mbps — crisp, heavy").tag("16M")
                }

                Picker("Frame rate", selection: $prefs.wirelessMaxFPS) {
                    Text("30 fps").tag(30)
                    Text("60 fps — smoother").tag(60)
                    Text("Unlimited").tag(0)
                }

                Picker("Jitter buffer", selection: $prefs.wirelessBufferMS) {
                    Text("Off — lowest latency").tag(0)
                    Text("25 ms").tag(25)
                    Text("50 ms — recommended").tag(50)
                    Text("100 ms").tag(100)
                    Text("150 ms — smoother on weak Wi-Fi").tag(150)
                }

                Text("A jitter buffer absorbs Wi-Fi timing spikes. Higher values feel smoother but add delay. These settings apply to Wi-Fi sessions only; USB uses scrcpy's low-latency defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("USB") {
                Text("USB sessions use H.264 at 8 Mbps with no added buffer, because the cable is already fast and stable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tools

private struct ToolsSettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var prefs: Preferences
    @StateObject private var installer = ToolInstaller()

    var body: some View {
        Form {
            Section("Status") {
                if let toolchain = app.toolchain {
                    LabeledContent("scrcpy") {
                        Text(toolchain.scrcpyVersion ?? "Unknown")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    LabeledContent("adb") {
                        Text(toolchain.adbVersion ?? "Unknown")
                            .font(.system(size: 12, design: .monospaced))
                    }
                    LabeledContent("Source") {
                        Text(toolchain.origin.label)
                    }

                    pathRow("scrcpy", path: toolchain.scrcpy.path)
                    pathRow("adb", path: toolchain.adb.path)
                } else {
                    LabeledContent("Status") {
                        Text(app.toolStatus.message)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Check again") {
                        Task { await app.refreshTools() }
                    }

                    Button("Reveal in Finder") {
                        if let toolchain = app.toolchain {
                            NSWorkspace.shared.activateFileViewerSelecting([toolchain.scrcpy])
                        }
                    }
                    .disabled(app.toolchain == nil)
                }
            }

            Section("Update") {
                if installer.phase.isBusy {
                    VStack(alignment: .leading, spacing: 6) {
                        if let progress = downloadProgress {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(installer.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button("Download the latest scrcpy") {
                        updateTools()
                    }
                    Text("Downloads the latest release from GitHub into Application Support and verifies its SHA-256 checksum. The app's bundled copy is used until you update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if case .failed(let message) = installer.phase {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Custom binaries") {
                pathEditor("adb", text: $prefs.customADBPath)
                pathEditor("scrcpy", text: $prefs.customScrcpyPath)

                HStack {
                    Button("Apply paths") {
                        Task { await app.refreshTools() }
                    }
                    Button("Clear") {
                        prefs.customADBPath = ""
                        prefs.customScrcpyPath = ""
                        Task { await app.refreshTools() }
                    }
                }

                Text("Leave empty to use the bundled tools. Point these at Homebrew or Android SDK binaries only if you know they match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Copy diagnostics") {
                    Task {
                        let text = await app.diagnostics()
                        app.copyToPasteboard(text)
                        app.flash("Diagnostics copied.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var downloadProgress: Double? {
        if case .downloading(_, let progress) = installer.phase {
            return progress
        }
        return nil
    }

    private func updateTools() {
        Task {
            await installer.installLatest()
            if case .done = installer.phase {
                await app.refreshTools()
                app.flash("Tools updated.")
            }
        }
    }

    private func pathRow(_ label: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.8))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func pathEditor(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            TextField("Path to \(title)", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            Button("Choose…") {
                chooseExecutable { path in
                    text.wrappedValue = path
                }
            }
        }
    }

    private func chooseExecutable(_ completion: (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use"
        panel.message = "Choose an executable"
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}

// MARK: - About

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)

            Text("DeX for Mac")
                .font(.system(size: 22, weight: .semibold))

            Text("Version \(AppInfo.version) (\(AppInfo.build))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Samsung DeX on your Mac over USB or Wi-Fi.")
                .font(.callout)

            Divider()
                .frame(width: 300)

            HStack(spacing: 16) {
                Link("scrcpy on GitHub", destination: URL(string: "https://github.com/Genymobile/scrcpy")!)
                Link("Android platform-tools", destination: URL(string: "https://developer.android.com/tools/releases/platform-tools")!)
            }
            .font(.callout)

            Text("DeX needs One UI 8 (Android 16) or newer on the phone. USB debugging must be enabled.\n\nNot affiliated with Samsung. DeX and Galaxy are trademarks of Samsung Electronics. scrcpy is open source under Apache 2.0.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
