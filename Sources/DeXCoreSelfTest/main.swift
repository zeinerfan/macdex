import DeXCore
import Foundation

// A dependency-free self test runner. Run with: swift run dex-self-test
// (XCTest is not available with the Command Line Tools alone.)

var checks = 0
var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: UInt = #line) {
    checks += 1
    if !condition() {
        failures.append("line \(line): \(message)")
    }
}

func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String, line: UInt = #line) {
    checks += 1
    if actual != expected {
        failures.append("line \(line): \(message) — expected \(expected), got \(actual)")
    }
}

// MARK: - adb devices

let devicesOutput = """
List of devices attached
R5CT1234ABCD           device usb:34603008X product:b0qxxx model:SM_S928B device:b0q transport_id:1
192.168.1.42:5555      device product:b0qxxx model:SM_S928B device:b0q transport_id:2
"""
let devices = ADBParsers.devices(from: devicesOutput)
equal(devices.count, 2, "two devices")
equal(devices[0].serial, "R5CT1234ABCD", "usb serial")
equal(devices[0].state, .device, "usb state")
equal(devices[0].transport, .usb, "usb transport")
equal(devices[0].rawModel, "SM_S928B", "raw model")
equal(devices[1].transport, .wireless, "wireless transport")
check(devices[1].isWireless, "wireless flag")

let mixedOutput = """
List of devices attached
ABCDEFGH        unauthorized usb:1-1
ZYXWVUTS        offline usb:1-2
"""
let mixed = ADBParsers.devices(from: mixedOutput)
equal(mixed.map(\.state), [.unauthorized, .offline], "unauthorized and offline")

let noisyOutput = """
* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
adb-1A2B3C-4D5E6F._adb-tls-connect._tcp device product:x model:SM_F956B device:x transport_id:3
"""
let noisy = ADBParsers.devices(from: noisyOutput)
equal(noisy.count, 1, "noise ignored")
if let first = noisy.first {
    equal(first.transport, .wireless, "mdns serial transport")
}

// MARK: - mDNS

let mdnsOutput = """
List of discovered mdns services
adb-R5CT1234-abcdef\t_adb-tls-pairing._tcp\t192.168.1.42:41567
adb-R5CT1234-abcdef\t_adb-tls-connect._tcp\t192.168.1.42:37001
"""
let services = ADBParsers.mdnsServices(from: mdnsOutput)
equal(services.count, 2, "two mdns services")
equal(services.first?.kind, .pairing, "pairing kind")
equal(services.first?.host, "192.168.1.42", "mdns host")
equal(services.first?.port, 41567, "mdns port")
equal(services.last?.kind, .connect, "connect kind")

equal(ADBParsers.parseHostPort("192.168.1.42:5555")?.host, "192.168.1.42", "ipv4 host")
equal(ADBParsers.parseHostPort("192.168.1.42:5555")?.port, 5555, "ipv4 port")
equal(ADBParsers.parseHostPort("[fe80::1]:41414")?.host, "fe80::1", "ipv6 host")
equal(ADBParsers.parseHostPort("[fe80::1]:41414")?.port, 41414, "ipv6 port")
check(ADBParsers.parseHostPort("not-an-endpoint") == nil, "invalid endpoint rejected")
check(ADBParsers.parseHostPort("192.168.1.42:99999") == nil, "invalid port rejected")

// MARK: - getprop / metadata

let getpropOutput = """
[ro.product.model]: [SM-S928B]
[ro.product.marketname]: [Galaxy S24 Ultra]
[ro.build.version.oneui]: [80000]
[ro.build.version.release]: [16]
[ro.build.version.sdk]: [36]
[ro.build.characteristics]: [default]
"""
let props = ADBParsers.getprop(from: getpropOutput)
equal(props["ro.product.model"] ?? "", "SM-S928B", "getprop model")
equal(props["ro.product.marketname"] ?? "", "Galaxy S24 Ultra", "getprop market name")

equal(ADBParsers.parseOneUI("80000")?.display, "8", "one ui 8")
equal(ADBParsers.parseOneUI("80000")?.major, 8, "one ui major 8")
equal(ADBParsers.parseOneUI("60100")?.display, "6.1", "one ui 6.1")
equal(ADBParsers.parseOneUI("60101")?.display, "6.1.1", "one ui 6.1.1")
equal(ADBParsers.parseOneUI("70000")?.major, 7, "one ui major 7")
check(ADBParsers.parseOneUI(nil) == nil, "nil one ui")
check(ADBParsers.parseOneUI("unknown") == nil, "unknown one ui")

let metadata = DeviceMetadata(props: [
    "ro.product.model": "SM-S928B",
    "ro.product.marketname": "Galaxy S24 Ultra",
    "ro.product.manufacturer": "samsung",
    "ro.build.version.release": "16",
    "ro.build.version.sdk": "36",
    "ro.build.version.oneui": "80000",
    "ro.build.characteristics": "default"
])
equal(metadata.marketName ?? "", "Galaxy S24 Ultra", "metadata market name")
equal(metadata.oneUIMajor ?? 0, 8, "metadata one ui major")
check(metadata.loaded, "metadata loaded")

// MARK: - Wi-Fi IP

equal(
    ADBParsers.wlanIP(from: "2: wlan0: <UP> mtu 1500\n    inet 192.168.1.42/24 brd 192.168.1.255 scope global wlan0"),
    "192.168.1.42",
    "wlan0 ip"
)
equal(
    ADBParsers.wlanIP(from: "default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.99 metric 303"),
    "192.168.1.99",
    "route src ip"
)
equal(ADBParsers.wlanIP(from: "192.168.1.77"), "192.168.1.77", "dhcp prop ip")
check(ADBParsers.wlanIP(from: "inet 127.0.0.1/8") == nil, "loopback rejected")

// MARK: - Presentation

var device = AndroidDevice(serial: "R5CT", rawModel: "SM_S928B")
equal(device.displayName, "SM-S928B", "fallback display name")
check(device.isGalaxy, "samsung model detected")
device.metadata = metadata
equal(device.displayName, "Galaxy S24 Ultra", "market display name")
equal(device.dexSupport, .supported, "dex support")
check(!device.isTablet, "phone is not tablet")

let oldDevice = AndroidDevice(
    serial: "X",
    metadata: DeviceMetadata(
        model: "SM-S918B",
        marketName: "Galaxy S23 Ultra",
        manufacturer: "samsung",
        androidRelease: "15",
        apiLevel: 35,
        oneUI: "7",
        oneUIMajor: 7,
        loaded: true
    )
)
equal(oldDevice.dexSupport, .requiresOneUI8(current: "7"), "one ui 7 warning")

let pixel = AndroidDevice(
    serial: "X",
    metadata: DeviceMetadata(model: "Pixel 9", manufacturer: "Google", apiLevel: 36, loaded: true)
)
equal(pixel.dexSupport, .notSamsung, "non samsung")

let tablet = AndroidDevice(
    serial: "X",
    metadata: DeviceMetadata(model: "SM-X910", characteristics: "tablet", loaded: true)
)
check(tablet.isTablet, "tablet detected")

// MARK: - Versions

equal(
    Toolchain.parseScrcpyVersion("scrcpy 5.0.1 <https://github.com/Genymobile/scrcpy>\n"),
    "5.0.1",
    "scrcpy version"
)
equal(
    Toolchain.parseADBVersion("Android Debug Bridge version 1.0.41\nVersion 37.0.1-15733141\n"),
    "1.0.41",
    "adb version"
)
equal(
    Toolchain.parseADBVersion("Version 37.0.1-15733141\nInstalled as /opt/homebrew/bin/adb"),
    "37.0.1",
    "adb version (new format)"
)

// MARK: - scrcpy arguments

func baseDesktop() -> ScrcpyLaunchConfiguration {
    ScrcpyLaunchConfiguration(
        serial: "R5CT1234",
        deviceName: "Galaxy S24 Ultra",
        mode: .desktop,
        width: 1920,
        height: 1080,
        dpi: 160
    )
}

let desktopArguments = ScrcpyArguments.make(for: baseDesktop())
equal(Array(desktopArguments.prefix(3)), ["-s", "R5CT1234", "--new-display=1920x1080/160"], "desktop args")
check(!desktopArguments.contains("--no-audio"), "audio forwarded by default")
check(!desktopArguments.contains("--video-codec=h264"), "no wireless codec on usb")

var autoDisplay = baseDesktop()
autoDisplay.width = 0
autoDisplay.height = 0
autoDisplay.dpi = 0
check(ScrcpyArguments.make(for: autoDisplay).contains("--new-display"), "auto display")

var mirror = baseDesktop()
mirror.mode = .mirror
let mirrorArguments = ScrcpyArguments.make(for: mirror)
check(!mirrorArguments.contains { $0.hasPrefix("--new-display") }, "mirror has no new display")
check(!mirrorArguments.contains("--flex-display"), "mirror has no flex display")

var wireless = baseDesktop()
wireless.wireless = true
wireless.forwardAudio = false
wireless.stream = .wifiDefault
wireless.turnScreenOff = true
wireless.physicalKeyboard = true
let wirelessArguments = ScrcpyArguments.make(for: wireless)
for expected in ["--video-codec=h265", "--video-bit-rate=8M", "--max-fps=60", "--video-buffer=50",
                 "--no-audio", "--turn-screen-off", "--keyboard=uhid", "--keep-active"] {
    check(wirelessArguments.contains(expected), "wireless args include \(expected)")
}

var usb = baseDesktop()
usb.stream = .wifiDefault
let usbArguments = ScrcpyArguments.make(for: usb)
check(!usbArguments.contains("--no-audio"), "usb audio")
check(!usbArguments.contains("--video-codec=h265"), "usb codec")
check(!usbArguments.contains("--video-buffer=50"), "usb buffer")
check(usbArguments.contains("--stay-awake"), "usb stay awake")

var flex = baseDesktop()
flex.flexDisplay = true
check(ScrcpyArguments.make(for: flex).contains("--flex-display"), "flex display")
flex.mode = .mirror
check(!ScrcpyArguments.make(for: flex).contains("--flex-display"), "no flex in mirror")

check(
    ScrcpyArguments.make(for: baseDesktop()).contains("--window-title=DeX — Galaxy S24 Ultra"),
    "window title"
)

var autoCodec = baseDesktop()
autoCodec.wireless = true
autoCodec.stream = StreamSettings(codec: "auto", bitRate: "8M", maxFPS: 0, bufferMS: 0)
let autoCodecArguments = ScrcpyArguments.make(for: autoCodec)
check(!autoCodecArguments.contains { $0.hasPrefix("--video-codec") }, "auto codec omitted")
check(!autoCodecArguments.contains { $0.hasPrefix("--max-fps") }, "unlimited fps omitted")
check(!autoCodecArguments.contains { $0.hasPrefix("--video-buffer") }, "zero buffer omitted")

// MARK: - Result

print("")
if failures.isEmpty {
    print("✓ \(checks) checks passed")
    exit(0)
} else {
    print("✗ \(failures.count) of \(checks) checks failed:")
    for failure in failures {
        print("  • \(failure)")
    }
    exit(1)
}
