import Foundation

/// How the app chooses the audio source for a track.
///
/// - `auto`: play whichever source resolves first (fastest start).
/// - `high`: upgrade to a high-bitrate source (JioSaavn 320 kbps) when found.
/// - `lossless`: upgrade to FLAC (PencariMusic) when found.
///
/// Upgrades happen at track boundaries (prefetched), so playback never waits.
enum MusicQualityMode: String, CaseIterable, Identifiable, Sendable, Hashable {
    case auto
    case high
    case lossless

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "High (320 kbps)"
        case .lossless: return "Lossless (FLAC)"
        }
    }
}

extension MusicQualityMode: SettingsOption {}
