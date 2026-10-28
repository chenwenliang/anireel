import Foundation

/// Performance tier for real-time stylization (docs/DECISIONS.md D1). `nil` from the
/// initializers means the device is below the A13 floor and is not supported.
enum DeviceTier: Equatable {
    case a13
    case a14OrNewer

    /// Square side length for ML style inference. Thermal downgrade (Phase 3) only lowers from here.
    var inferenceSize: Int {
        switch self {
        case .a13: 384
        case .a14OrNewer: 512
        }
    }

    static let current = DeviceTier(modelIdentifier: currentModelIdentifier())

    /// iPhone identifiers encode the chip generation in the major number:
    /// iPhone12,x is A13 (11, 11 Pro, SE 2), iPhone13,x and later are A14+.
    /// Unrecognized identifiers are assumed to be newer hardware rather than blocked.
    init?(modelIdentifier: String) {
        guard modelIdentifier.hasPrefix("iPhone"),
              let major = Int(modelIdentifier.dropFirst("iPhone".count).prefix { $0.isNumber })
        else {
            self = .a14OrNewer
            return
        }
        switch major {
        case ..<12: return nil
        case 12: self = .a13
        default: self = .a14OrNewer
        }
    }

    private static func currentModelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
