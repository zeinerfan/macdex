import AppKit
import DeXCore
import SwiftUI

// MARK: - Theme

enum Theme {
    static let accent = Color(red: 0.24, green: 0.42, blue: 0.97)
    static let accentLight = Color(red: 0.36, green: 0.66, blue: 0.98)
    static let cardRadius: CGFloat = 14
}

extension DeviceConnectionState {
    var color: Color {
        switch self {
        case .device: return .green
        case .unauthorized, .authorizing, .connecting: return .orange
        case .noPermissions: return .red
        case .offline, .recovery, .sideload, .bootloader, .unknown: return .secondary
        }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(CardLabelStyle())

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }
}

private struct CardLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent.opacity(0.9))
            configuration.title
                .textCase(.uppercase)
                .kerning(0.4)
        }
    }
}

// MARK: - Pills & dots

struct StatusPill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(Capsule(style: .continuous).fill(color.opacity(0.13)))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(color.opacity(0.2), lineWidth: 1)
        }
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8
    var pulsing: Bool = false

    @State private var animate = false

    var body: some View {
        ZStack {
            if pulsing && color != .secondary {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: size * 2.4, height: size * 2.4)
                    .scaleEffect(animate ? 1 : 0.6)
                    .opacity(animate ? 0 : 1)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

// MARK: - Device glyph

struct DeviceGlyph: View {
    let device: AndroidDevice
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.accent, Theme.accentLight],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: device.isTablet ? "ipad" : "iphone")
                    .font(.system(size: size * 0.44, weight: .regular))
                    .foregroundStyle(.white.opacity(0.96))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
    }
}

// MARK: - Rows

struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityLabel(title)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Banners

struct HintBanner: View {
    let text: String
    var systemImage: String = "lightbulb.fill"
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.10))
        }
    }
}

// MARK: - Steps

struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 19, height: 19)
                .background(Circle().fill(Theme.accent))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Log console

struct LogConsole: View {
    let entries: [LogEntry]
    var maxHeight: CGFloat = 170

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if entries.isEmpty {
                        Text("No output yet.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        ForEach(entries) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: maxHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            }
            .onChange(of: entries.count) { _, _ in
                guard let last = entries.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .system: return .secondary
        case .output: return .primary.opacity(0.8)
        case .error: return .red
        }
    }
}
