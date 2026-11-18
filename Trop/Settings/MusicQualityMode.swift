import Foundation

/// How the app chooses the audio source for a track.
///
/// - `auto`: play whichever source resolves first (fastest start).
/// - `high`: upgrade to a high-bitrate source (JioSaavn 320 kbps) when found.
/// - `cd`: upgrade to CD-quality FLAC (16-bit / 44.1 kHz) and skip hi-res.
/// - `lossless`: upgrade to the best FLAC (CD or hi-res) when found.
///
/// Upgrades happen at track boundaries (prefetched), so playback never waits.
enum MusicQualityMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case off
    case auto
    case high
    case cd
    case lossless

    var id: String { rawValue }

    /// Both FLAC modes take the lossless path; CD additionally rejects hi-res.
    var prefersLossless: Bool { self == .cd || self == .lossless }
    var requiresCD: Bool { self == .cd }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .auto: return "Auto"
        case .high: return "High (320 kbps)"
        case .cd: return "CD (16/44)"
        case .lossless: return "Best FLAC"
        }
    }
}

extension MusicQualityMode: SettingsOption {}
