import Foundation

public enum LaunchMode: String, Sendable {
    case desktop
    case mirror

    public var title: String {
        switch self {
        case .desktop: return "Samsung DeX"
        case .mirror: return "Phone screen"
        }
    }
}

public struct StreamSettings: Sendable, Equatable {
    /// "auto" lets scrcpy choose (H.264).
    public var codec: String
    public var bitRate: String
    /// 0 means "do not set --max-fps".
    public var maxFPS: Int
    /// 0 means "do not set --video-buffer".
    public var bufferMS: Int

    public init(codec: String = "auto", bitRate: String = "8M", maxFPS: Int = 0, bufferMS: Int = 0) {
        self.codec = codec
        self.bitRate = bitRate
        self.maxFPS = maxFPS
        self.bufferMS = bufferMS
    }

    public static let wifiDefault = StreamSettings(codec: "h265", bitRate: "8M", maxFPS: 60, bufferMS: 50)
}

public struct ScrcpyLaunchConfiguration: Sendable, Equatable {
    public var serial: String
    public var deviceName: String
    public var mode: LaunchMode
    /// 0 for width/height means "use the phone's own display size".
    public var width: Int
    public var height: Int
    /// 0 means "use the phone's own density".
    public var dpi: Int
    public var flexDisplay: Bool
    public var fullscreen: Bool
    public var alwaysOnTop: Bool
    public var keepAwake: Bool
    public var turnScreenOff: Bool
    public var physicalKeyboard: Bool
    public var forwardAudio: Bool
    public var wireless: Bool
    public var stream: StreamSettings

    public init(
        serial: String,
        deviceName: String,
        mode: LaunchMode = .desktop,
        width: Int = 1920,
        height: Int = 1080,
        dpi: Int = 160,
        flexDisplay: Bool = false,
        fullscreen: Bool = false,
        alwaysOnTop: Bool = false,
        keepAwake: Bool = true,
        turnScreenOff: Bool = false,
        physicalKeyboard: Bool = false,
        forwardAudio: Bool = true,
        wireless: Bool = false,
        stream: StreamSettings = StreamSettings()
    ) {
        self.serial = serial
        self.deviceName = deviceName
        self.mode = mode
        self.width = width
        self.height = height
        self.dpi = dpi
        self.flexDisplay = flexDisplay
        self.fullscreen = fullscreen
        self.alwaysOnTop = alwaysOnTop
        self.keepAwake = keepAwake
        self.turnScreenOff = turnScreenOff
        self.physicalKeyboard = physicalKeyboard
        self.forwardAudio = forwardAudio
        self.wireless = wireless
        self.stream = stream
    }
}

public enum ScrcpyArguments {

    public static func make(for configuration: ScrcpyLaunchConfiguration) -> [String] {
        var arguments = ["-s", configuration.serial]

        if configuration.mode == .desktop {
            if configuration.width > 0, configuration.height > 0 {
                var display = "--new-display=\(configuration.width)x\(configuration.height)"
                if configuration.dpi > 0 {
                    display += "/\(configuration.dpi)"
                }
                arguments.append(display)
            } else {
                arguments.append("--new-display")
            }

            if configuration.flexDisplay {
                arguments.append("--flex-display")
            }
        }

        arguments.append("--window-title=\(windowTitle(for: configuration))")

        if configuration.fullscreen { arguments.append("--fullscreen") }
        if configuration.alwaysOnTop { arguments.append("--always-on-top") }
        if configuration.turnScreenOff { arguments.append("--turn-screen-off") }
        if configuration.physicalKeyboard { arguments.append("--keyboard=uhid") }

        if configuration.keepAwake {
            arguments.append(configuration.wireless ? "--keep-active" : "--stay-awake")
        }

        if !configuration.forwardAudio {
            arguments.append("--no-audio")
        }

        if configuration.wireless {
            let stream = configuration.stream
            if stream.codec != "auto", !stream.codec.isEmpty {
                arguments.append("--video-codec=\(stream.codec)")
            }
            if !stream.bitRate.isEmpty {
                arguments.append("--video-bit-rate=\(stream.bitRate)")
            }
            if stream.maxFPS > 0 {
                arguments.append("--max-fps=\(stream.maxFPS)")
            }
            if stream.bufferMS > 0 {
                arguments.append("--video-buffer=\(stream.bufferMS)")
            }
        }

        return arguments
    }

    public static func windowTitle(for configuration: ScrcpyLaunchConfiguration) -> String {
        switch configuration.mode {
        case .desktop:
            return "DeX — \(configuration.deviceName)"
        case .mirror:
            return "\(configuration.deviceName) — Screen"
        }
    }
}
