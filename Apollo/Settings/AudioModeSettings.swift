import Foundation

/// Apple Music-style Dolby Atmos choice. `automatic` only uses Atmos when the
/// current output can render spatial audio (AirPods, Bluetooth, AirPlay).
enum AtmosMode: String, CaseIterable, Identifiable, SettingsOption {
    case automatic
    case alwaysOn
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .alwaysOn: return "Always On"
        case .off: return "Off"
        }
    }
}

/// Apple Music-style streaming/download tiers. The lossy tiers always exist;
/// the lossless ones are only offered when Lossless Audio is on.
enum StreamingTier: String, CaseIterable, Identifiable {
    case highEfficiency
    case highQuality
    case lossless
    case hiRes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highEfficiency: return "High Efficiency"
        case .highQuality: return "High Quality"
        case .lossless: return "Lossless"
        case .hiRes: return "Hi-Res Lossless"
        }
    }

    var subtitle: String {
        switch self {
        case .highEfficiency: return "HE-AAC with low data usage"
        case .highQuality: return "AAC 256 kbps"
        case .lossless: return "ALAC up to 24-bit/48 kHz"
        case .hiRes: return "ALAC up to 24-bit/192 kHz"
        }
    }

    /// Approximate size of a three-minute song.
    var sizeHint: String {
        switch self {
        case .highEfficiency: return "1.5 MB"
        case .highQuality: return "6 MB"
        case .lossless: return "36 MB"
        case .hiRes: return "145 MB"
        }
    }

    var requiresLossless: Bool {
        self == .lossless || self == .hiRes
    }
}

enum DownloadTier: String, CaseIterable, Identifiable {
    case highQuality
    case lossless
    case hiRes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highQuality: return "High Quality"
        case .lossless: return "Lossless"
        case .hiRes: return "Hi-Res Lossless"
        }
    }

    var subtitle: String {
        switch self {
        case .highQuality: return "AAC 256 kbps"
        case .lossless: return "ALAC up to 24-bit/48 kHz"
        case .hiRes: return "ALAC up to 24-bit/192 kHz"
        }
    }
}
