import DeXCore
import Foundation
import SwiftUI

// MARK: - Resolution presets

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case desktop1080
    case desktop1440
    case laptop
    case fourK
    case phone
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop1080: return "Full HD desktop"
        case .desktop1440: return "QHD desktop"
        case .laptop: return "Laptop"
        case .fourK: return "4K desktop"
        case .phone: return "Match my phone"
        case .custom: return "Custom…"
        }
    }

    var detail: String {
        switch self {
        case .desktop1080: return "1920 × 1080 · 160 dpi"
        case .desktop1440: return "2560 × 1440 · 200 dpi"
        case .laptop: return "1680 × 1050 · 160 dpi"
        case .fourK: return "3840 × 2160 · 240 dpi"
        case .phone: return "Use the phone's own size and density"
        case .custom: return "Choose your own resolution and density"
        }
    }

    /// nil means "let the phone decide".
    var size: (width: Int, height: Int, dpi: Int)? {
        switch self {
        case .desktop1080: return (1920, 1080, 160)
        case .desktop1440: return (2560, 1440, 200)
        case .laptop: return (1680, 1050, 160)
        case .fourK: return (3840, 2160, 240)
        case .phone: return nil
        case .custom: return nil
        }
    }
}

// MARK: - Preferences

@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let preset = "display.preset"
        static let customWidth = "display.customWidth"
        static let customHeight = "display.customHeight"
        static let customDPI = "display.customDPI"
        static let flexDisplay = "display.flex"
        static let fullscreen = "display.fullscreen"
        static let alwaysOnTop = "display.alwaysOnTop"
        static let keepAwake = "display.keepAwake"
        static let turnScreenOff = "display.turnScreenOff"
        static let physicalKeyboard = "input.physicalKeyboard"
        static let forwardAudio = "audio.forward"
        static let audioOnWiFi = "audio.onWiFi"
        static let wirelessCodec = "stream.codec"
        static let wirelessBitRate = "stream.bitRate"
        static let wirelessMaxFPS = "stream.maxFPS"
        static let wirelessBuffer = "stream.buffer"
        static let autoReconnect = "network.autoReconnect"
        static let isolatedServer = "network.isolatedServer"
        static let customADBPath = "tools.adbPath"
        static let customScrcpyPath = "tools.scrcpyPath"
        static let hasOnboarded = "app.hasOnboarded"
    }

    private let defaults: UserDefaults

    @Published var resolutionPreset: ResolutionPreset {
        didSet { defaults.set(resolutionPreset.rawValue, forKey: Key.preset) }
    }
    @Published var customWidth: Int {
        didSet { defaults.set(customWidth, forKey: Key.customWidth) }
    }
    @Published var customHeight: Int {
        didSet { defaults.set(customHeight, forKey: Key.customHeight) }
    }
    @Published var customDPI: Int {
        didSet { defaults.set(customDPI, forKey: Key.customDPI) }
    }
    @Published var flexDisplay: Bool {
        didSet { defaults.set(flexDisplay, forKey: Key.flexDisplay) }
    }
    @Published var fullscreen: Bool {
        didSet { defaults.set(fullscreen, forKey: Key.fullscreen) }
    }
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }
    @Published var keepAwake: Bool {
        didSet { defaults.set(keepAwake, forKey: Key.keepAwake) }
    }
    @Published var turnScreenOff: Bool {
        didSet { defaults.set(turnScreenOff, forKey: Key.turnScreenOff) }
    }
    @Published var physicalKeyboard: Bool {
        didSet { defaults.set(physicalKeyboard, forKey: Key.physicalKeyboard) }
    }
    @Published var forwardAudio: Bool {
        didSet { defaults.set(forwardAudio, forKey: Key.forwardAudio) }
    }
    @Published var audioOnWiFi: Bool {
        didSet { defaults.set(audioOnWiFi, forKey: Key.audioOnWiFi) }
    }
    @Published var wirelessCodec: String {
        didSet { defaults.set(wirelessCodec, forKey: Key.wirelessCodec) }
    }
    @Published var wirelessBitRate: String {
        didSet { defaults.set(wirelessBitRate, forKey: Key.wirelessBitRate) }
    }
    @Published var wirelessMaxFPS: Int {
        didSet { defaults.set(wirelessMaxFPS, forKey: Key.wirelessMaxFPS) }
    }
    @Published var wirelessBufferMS: Int {
        didSet { defaults.set(wirelessBufferMS, forKey: Key.wirelessBuffer) }
    }
    @Published var autoReconnect: Bool {
        didSet { defaults.set(autoReconnect, forKey: Key.autoReconnect) }
    }
    @Published var isolatedADBServer: Bool {
        didSet { defaults.set(isolatedADBServer, forKey: Key.isolatedServer) }
    }
    @Published var customADBPath: String {
        didSet { defaults.set(customADBPath, forKey: Key.customADBPath) }
    }
    @Published var customScrcpyPath: String {
        didSet { defaults.set(customScrcpyPath, forKey: Key.customScrcpyPath) }
    }
    @Published var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        resolutionPreset = ResolutionPreset(rawValue: defaults.string(forKey: Key.preset) ?? "") ?? .desktop1080
        customWidth = defaults.object(forKey: Key.customWidth) as? Int ?? 1920
        customHeight = defaults.object(forKey: Key.customHeight) as? Int ?? 1080
        customDPI = defaults.object(forKey: Key.customDPI) as? Int ?? 160
        flexDisplay = defaults.object(forKey: Key.flexDisplay) as? Bool ?? false
        fullscreen = defaults.object(forKey: Key.fullscreen) as? Bool ?? false
        alwaysOnTop = defaults.object(forKey: Key.alwaysOnTop) as? Bool ?? false
        keepAwake = defaults.object(forKey: Key.keepAwake) as? Bool ?? true
        turnScreenOff = defaults.object(forKey: Key.turnScreenOff) as? Bool ?? false
        physicalKeyboard = defaults.object(forKey: Key.physicalKeyboard) as? Bool ?? false
        forwardAudio = defaults.object(forKey: Key.forwardAudio) as? Bool ?? true
        audioOnWiFi = defaults.object(forKey: Key.audioOnWiFi) as? Bool ?? false
        wirelessCodec = defaults.string(forKey: Key.wirelessCodec) ?? "h265"
        wirelessBitRate = defaults.string(forKey: Key.wirelessBitRate) ?? "8M"
        wirelessMaxFPS = defaults.object(forKey: Key.wirelessMaxFPS) as? Int ?? 60
        wirelessBufferMS = defaults.object(forKey: Key.wirelessBuffer) as? Int ?? 50
        autoReconnect = defaults.object(forKey: Key.autoReconnect) as? Bool ?? true
        isolatedADBServer = defaults.object(forKey: Key.isolatedServer) as? Bool ?? false
        customADBPath = defaults.string(forKey: Key.customADBPath) ?? ""
        customScrcpyPath = defaults.string(forKey: Key.customScrcpyPath) ?? ""
        hasOnboarded = defaults.object(forKey: Key.hasOnboarded) as? Bool ?? false
    }

    /// Returns nil when the phone's own display should be used.
    var displaySize: (width: Int, height: Int, dpi: Int)? {
        if resolutionPreset == .custom {
            let width = min(7680, max(640, customWidth))
            let height = min(4320, max(480, customHeight))
            let dpi = min(640, max(72, customDPI))
            return (width, height, dpi)
        }
        return resolutionPreset.size
    }

    var wirelessStream: StreamSettings {
        StreamSettings(
            codec: wirelessCodec,
            bitRate: wirelessBitRate,
            maxFPS: wirelessMaxFPS,
            bufferMS: wirelessBufferMS
        )
    }

    var adbServerPort: Int? {
        isolatedADBServer ? 5038 : nil
    }
}

// MARK: - Saved wireless devices

struct WirelessRecord: Codable, Identifiable, Hashable {
    var endpoint: String
    var name: String
    var lastUsed: Date

    var id: String { endpoint }

    var host: String {
        ADBParsers.parseHostPort(endpoint)?.host ?? endpoint
    }
}

enum WirelessStore {
    private static let key = "wireless.records"

    static func load() -> [WirelessRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([WirelessRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.lastUsed > $1.lastUsed }
    }

    static func save(_ records: [WirelessRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
