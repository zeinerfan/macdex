import Foundation

// MARK: - Transport & state

public enum DeviceTransport: String, Sendable, Codable {
    case usb
    case wireless
    case unknown

    public var label: String {
        switch self {
        case .usb: return "USB"
        case .wireless: return "Wi-Fi"
        case .unknown: return "Unknown"
        }
    }
}

public enum DeviceConnectionState: String, Sendable {
    case device = "device"
    case unauthorized = "unauthorized"
    case offline = "offline"
    case authorizing = "authorizing"
    case connecting = "connecting"
    case recovery = "recovery"
    case sideload = "sideload"
    case bootloader = "bootloader"
    case noPermissions = "no permissions"
    case unknown = "unknown"

    public var isUsable: Bool { self == .device }

    public var label: String {
        switch self {
        case .device: return "Connected"
        case .unauthorized: return "Waiting for approval"
        case .offline: return "Offline"
        case .authorizing: return "Authorizing"
        case .connecting: return "Connecting"
        case .recovery: return "Recovery"
        case .sideload: return "Sideload"
        case .bootloader: return "Bootloader"
        case .noPermissions: return "No USB permission"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - DeX support

public enum DeXSupport: Sendable, Equatable {
    case supported
    case requiresOneUI8(current: String?)
    case notSamsung
    case unknown
}

// MARK: - Metadata

public struct DeviceMetadata: Hashable, Sendable {
    public var model: String?
    public var marketName: String?
    public var manufacturer: String?
    public var androidRelease: String?
    public var apiLevel: Int?
    public var oneUI: String?
    public var oneUIMajor: Int?
    public var characteristics: String?
    public var loaded: Bool

    public init(
        model: String? = nil,
        marketName: String? = nil,
        manufacturer: String? = nil,
        androidRelease: String? = nil,
        apiLevel: Int? = nil,
        oneUI: String? = nil,
        oneUIMajor: Int? = nil,
        characteristics: String? = nil,
        loaded: Bool = false
    ) {
        self.model = model
        self.marketName = marketName
        self.manufacturer = manufacturer
        self.androidRelease = androidRelease
        self.apiLevel = apiLevel
        self.oneUI = oneUI
        self.oneUIMajor = oneUIMajor
        self.characteristics = characteristics
        self.loaded = loaded
    }

    /// Builds metadata from the output of `adb shell getprop` (already parsed into a dictionary).
    public init(props: [String: String]) {
        func value(_ key: String) -> String? {
            guard let raw = props[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  raw.lowercased() != "unknown" else { return nil }
            return raw
        }

        model = value("ro.product.model")
        marketName = value("ro.product.marketname") ?? value("ro.product.nickname")
        manufacturer = value("ro.product.manufacturer")
        androidRelease = value("ro.build.version.release")
        apiLevel = Int(value("ro.build.version.sdk") ?? "")
        characteristics = value("ro.build.characteristics")

        if let parsed = ADBParsers.parseOneUI(value("ro.build.version.oneui")) {
            oneUI = parsed.display
            oneUIMajor = parsed.major
        }

        loaded = true
    }
}

// MARK: - Device

public struct AndroidDevice: Identifiable, Hashable, Sendable {
    public var serial: String
    public var state: DeviceConnectionState
    public var transport: DeviceTransport
    public var rawModel: String?
    public var product: String?
    public var device: String?
    public var transportID: String?
    public var metadata: DeviceMetadata

    public init(
        serial: String,
        state: DeviceConnectionState = .unknown,
        transport: DeviceTransport = .unknown,
        rawModel: String? = nil,
        product: String? = nil,
        device: String? = nil,
        transportID: String? = nil,
        metadata: DeviceMetadata = DeviceMetadata()
    ) {
        self.serial = serial
        self.state = state
        self.transport = transport
        self.rawModel = rawModel
        self.product = product
        self.device = device
        self.transportID = transportID
        self.metadata = metadata
    }

    public var id: String { serial }
    public var isWireless: Bool { transport == .wireless }
    public var isConnected: Bool { state == .device }

    public var isGalaxy: Bool {
        if isSamsungModel { return true }
        return metadata.manufacturer?.localizedCaseInsensitiveContains("samsung") == true
    }

    private var isSamsungModel: Bool {
        let candidates = [metadata.model, rawModel].compactMap { $0?.uppercased() }
        return candidates.contains { $0.hasPrefix("SM-") || $0.hasPrefix("SM_") }
    }

    public var modelCode: String? {
        if let model = metadata.model, !model.isEmpty { return model }
        if let rawModel, !rawModel.isEmpty {
            return rawModel.replacingOccurrences(of: "_", with: "-")
        }
        return nil
    }

    public var displayName: String {
        if let market = metadata.marketName, !market.isEmpty { return market }
        if let model = modelCode { return model }
        return isGalaxy ? "Galaxy device" : (isWireless ? "Wireless device" : "Android device")
    }

    public var isTablet: Bool {
        if metadata.characteristics?.localizedCaseInsensitiveContains("tablet") == true { return true }
        guard let model = modelCode?.uppercased() else { return false }
        return model.hasPrefix("SM-X") || model.hasPrefix("SM-T")
    }

    public var oneUIDescription: String? {
        guard let oneUI = metadata.oneUI else { return nil }
        return "One UI \(oneUI)"
    }

    public var androidDescription: String? {
        guard let release = metadata.androidRelease else { return nil }
        return "Android \(release)"
    }

    public var dexSupport: DeXSupport {
        guard isGalaxy else { return .notSamsung }

        if let major = metadata.oneUIMajor {
            return major >= 8 ? .supported : .requiresOneUI8(current: metadata.oneUI)
        }
        if let api = metadata.apiLevel {
            return api >= 36 ? .supported : .requiresOneUI8(current: nil)
        }
        return .unknown
    }

    /// A merged copy carrying freshly fetched metadata.
    public func applying(_ metadata: DeviceMetadata) -> AndroidDevice {
        var copy = self
        copy.metadata = metadata
        return copy
    }
}

// MARK: - mDNS

public struct MDNSService: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case pairing = "_adb-tls-pairing._tcp"
        case connect = "_adb-tls-connect._tcp"

        public var label: String {
            switch self {
            case .pairing: return "Pairing"
            case .connect: return "Connection"
            }
        }
    }

    public let serviceName: String
    public let kind: Kind
    public let host: String
    public let port: Int

    public init(serviceName: String, kind: Kind, host: String, port: Int) {
        self.serviceName = serviceName
        self.kind = kind
        self.host = host
        self.port = port
    }

    public var id: String { "\(kind.rawValue)|\(host)|\(port)" }

    public var endpoint: String {
        MDNSService.formatEndpoint(host: host, port: port)
    }

    public static func formatEndpoint(host: String, port: Int) -> String {
        if host.contains(":"), !host.hasPrefix("[") {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }
}
