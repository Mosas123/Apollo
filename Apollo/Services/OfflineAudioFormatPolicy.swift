import Foundation

/// Playback settings may prefer a spatial E-AC3 stream, but the download
/// pipeline's FLAC branch is bit-perfect/remux-only. It MUST only accept
/// actual FLAC sources; an Atmos/E-AC3 file is not a FLAC file.
enum OfflineAudioFormatPolicy {
    static func isVerifiedFLAC(
        qualityTier: String,
        mimeType: String,
        pathExtension: String
    ) -> Bool {
        guard qualityTier.caseInsensitiveCompare("Lossless") == .orderedSame else {
            return false
        }
        let mime = mimeType.lowercased()
        let blocked = ["eac3", "e-ac-3", "ec-3", "ac-3", "dolby",
                       "mp4a", "aac", "opus", "vorbis"]
        guard !blocked.contains(where: { mime.contains($0) }) else {
            return false
        }
        if mime.contains("flac") { return true }
        return mime.isEmpty && pathExtension.lowercased() == "flac"
    }
}
