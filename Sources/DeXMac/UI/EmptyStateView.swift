import DeXCore
import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                icon

                VStack(spacing: 7) {
                    Text("Connect your Galaxy")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Run Samsung DeX in a window on your Mac.\nNo monitor, dock, or Samsung software required.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    StepRow(
                        number: 1,
                        title: "Turn on USB debugging",
                        detail: "Settings → About phone → tap Build number 7×, then Developer options → USB debugging."
                    )
                    StepRow(
                        number: 2,
                        title: "Connect to your Mac",
                        detail: "Plug in a USB cable and tap Allow on the phone — or pair over Wi-Fi with a code."
                    )
                    StepRow(
                        number: 3,
                        title: "Open DeX",
                        detail: "Pick a resolution and press Start DeX. Your desktop opens in its own window."
                    )
                }
                .frame(maxWidth: 470, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        app.presentPairing()
                    } label: {
                        Label("Pair over Wi-Fi…", systemImage: "wifi")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Text("or plug in a USB cable")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                Text("DeX on a virtual display requires One UI 8 (Android 16) or later.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 104, height: 104)
                .shadow(color: Theme.accent.opacity(0.3), radius: 18, y: 8)

            Image(systemName: "display")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)

            Image(systemName: "iphone")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(Theme.accent)
                .padding(6)
                .background(Circle().fill(.white))
                .offset(x: 38, y: 34)
        }
        .padding(.bottom, 6)
    }
}
