import Foundation

/// Small pure policy for artist/album diversity in a station. It owns the
/// counters so the ranker and the golden checks apply exactly the same rules.
struct StationDiversityPolicy {
    let maxPerArtist: Int
    let maxPerAlbum: Int
    private var artistCounts: [String: Int] = [:]
    private var albumCounts: [String: Int] = [:]

    init(maxPerArtist: Int, maxPerAlbum: Int) {
        self.maxPerArtist = max(1, maxPerArtist)
        self.maxPerAlbum = max(1, maxPerAlbum)
    }

    static func caps(
        style: String,
        maxPerArtist: Int,
        maxPerAlbum: Int
    ) -> (artist: Int, album: Int) {
        let artistDefault = style == "variety" ? 1 : (style == "deepCuts" ? 2 : 3)
        let albumDefault = style == "variety" ? 1 : 2
        return (
            maxPerArtist > 0 ? maxPerArtist : artistDefault,
            maxPerAlbum > 0 ? maxPerAlbum : albumDefault
        )
    }

    /// Returns true and reserves one slot when the candidate fits. Empty keys
    /// mean the catalogue did not identify that dimension, so they never block.
    mutating func select(artistKey: String, albumKey: String) -> Bool {
        if !artistKey.isEmpty, artistCounts[artistKey, default: 0] >= maxPerArtist {
            return false
        }
        if !albumKey.isEmpty, albumCounts[albumKey, default: 0] >= maxPerAlbum {
            return false
        }
        if !artistKey.isEmpty { artistCounts[artistKey, default: 0] += 1 }
        if !albumKey.isEmpty { albumCounts[albumKey, default: 0] += 1 }
        return true
    }
}
