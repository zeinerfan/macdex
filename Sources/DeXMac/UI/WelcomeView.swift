import SwiftUI

struct WelcomeView: View {
    let onDone: () -> Void

    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 13) {
                    StepRow(
                        number: 1,
                        title: "Turn on USB debugging",
                        detail: "Settings → About phone → tap Build number seven times. Then open Developer options and turn on USB debugging."
                    )
                    StepRow(
                        number: 2,
                        title: "Connect your Galaxy",
                        detail: "Plug in a USB cable and tap Allow on the phone. Prefer no cable? Pair over Wi-Fi with a 6-digit code."
                    )
                    StepRow(
                        number: 3,
                        title: "Start DeX",
                        detail: "Choose a desktop resolution, then press Start DeX. Your DeX desktop opens in its own resizable window."
                    )
                }

                if !app.toolStatus.isReady {
                    HintBanner(
                        text: "adb and scrcpy are not ready. Open Settings → Tools to install or repair them.",
                        systemImage: "wrench.and.screwdriver.fill",
                        tint: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Good to know")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text("DeX on a virtual display requires One UI 8 (Android 16) or newer. Older Galaxy phones can still mirror their screen, but will not show the full DeX desktop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack {
                    Button("Maybe later") {
                        onDone()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Get Started") {
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 540, height: 600)
    }

    private var hero: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accent, Theme.accentLight],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

                Text("DeX for Mac")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Your Galaxy's desktop, in a window.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(.top, 6)
        }
        .frame(height: 200)
    }
}
