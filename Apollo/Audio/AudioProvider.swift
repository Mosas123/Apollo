import Foundation

struct AudioQuery: Sendable {
    let title: String
    let artist: String
    let durationSeconds: Int
    let isrc: String?
    let limit: Int

    init(song: SongItem, isrc: String?, limit: Int = 8) {
        title = song.title
        artist = song.artists.first?.name ?? ""
        durationSeconds = song.duration
        self.isrc = isrc
        self.limit = limit
    }

    var searchText: String {
        [title, artist].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct AudioCandidate: Sendable {
    let song: SongItem
    let source: MusicCatalogSource
    let isrc: String?
    let score: Double
}

@MainActor
protocol AudioProvider {
    var source: MusicCatalogSource { get }
    var supportsLossless: Bool { get }
    func search(_ query: AudioQuery) async -> [AudioCandidate]
}

struct JioSaavnAudioProvider: AudioProvider {
    let source: MusicCatalogSource = .jiosaavn
    let supportsLossless = false

    func search(_ query: AudioQuery) async -> [AudioCandidate] {
        guard !query.searchText.isEmpty,
              let tracks = try? await JioSaavnClient().search(query: query.searchText, limit: query.limit) else {
            return []
        }
        return tracks.map { Self.candidate(from: $0, source: source) }
    }

    static func candidate(from track: MusicCatalogTrack, source: MusicCatalogSource) -> AudioCandidate {
        AudioCandidate(
            song: track.asQueueSong(),
            source: source,
            isrc: track.isrc,
            score: 0
        )
    }
}

struct AudiusAudioProvider: AudioProvider {
    let source: MusicCatalogSource = .audius
    let supportsLossless = false

    func search(_ query: AudioQuery) async -> [AudioCandidate] {
        guard !query.searchText.isEmpty,
              let tracks = try? await AudiusClient().searchTracks(query: query.searchText, limit: query.limit) else {
            return []
        }
        return tracks.map { JioSaavnAudioProvider.candidate(from: $0, source: source) }
    }
}

struct QobuzAudioProvider: AudioProvider {
    let source: MusicCatalogSource = .qobuz
    let supportsLossless = true

    func search(_ query: AudioQuery) async -> [AudioCandidate] {
        guard !query.searchText.isEmpty else { return [] }
        let tracks = await QobuzCatalogService.shared.searchIfConfigured(
            query: query.searchText,
            limit: query.limit
        )
        return tracks.map { JioSaavnAudioProvider.candidate(from: $0, source: source) }
    }
}

struct AddonAudioProvider: AudioProvider {
    let source: MusicCatalogSource = .addon
    let supportsLossless = true

    func search(_ query: AudioQuery) async -> [AudioCandidate] {
        guard !query.searchText.isEmpty else { return [] }
        let installations = Array(MusicAddonsStore.shared.enabledStremioInstallations.prefix(4))
        guard !installations.isEmpty else { return [] }

        var perAddon = [[AddonTrack]](repeating: [], count: installations.count)
        await withTaskGroup(of: (Int, [AddonTrack]).self) { group in
            for (index, installation) in installations.enumerated() {
                group.addTask {
                    guard let client = try? MusicAddonClient(installation: installation),
                          let found = try? await client.search(query.searchText, limit: query.limit) else {
                        return (index, [])
                    }
                    return (index, found)
                }
            }
            for await (index, found) in group {
                perAddon[index] = found
            }
        }

        var candidates: [AudioCandidate] = []
        for found in perAddon {
            for item in found {
                var title = item.title
                var artist = item.artist ?? ""
                if artist.isEmpty, let separator = title.range(of: " - ") {
                    artist = String(title[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
                    title = String(title[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
                let storage = AddonPlaybackID.encode(key: item.installationKey, type: item.type, id: item.id)
                let raw = String(storage.dropFirst(AddonPlaybackID.prefix.count))
                let track = MusicCatalogTrack(
                    id: MusicCatalogID(source: .addon, rawValue: raw),
                    title: title.isEmpty ? item.title : title,
                    artist: artist,
                    durationSeconds: item.durationSeconds ?? 0,
                    artworkURL: item.poster,
                    permalinkURL: nil,
                    isStreamable: true
                )
                candidates.append(JioSaavnAudioProvider.candidate(from: track, source: source))
            }
        }
        return candidates
    }
}

/// Ordered audio provider set for the current quality mode.
@MainActor
struct AudioProviderRegistry {
    let providers: [any AudioProvider]

    static func forQuality(_ mode: MusicQualityMode) -> AudioProviderRegistry {
        let allowsLossy = mode != .cd && mode != .lossless
        let allowsLossless = mode != .high && mode != .off

        var providers: [any AudioProvider] = []
        if allowsLossy {
            providers.append(JioSaavnAudioProvider())
            providers.append(AudiusAudioProvider())
        }
        if allowsLossless {
            providers.append(QobuzAudioProvider())
            if SettingsStore.shared.hasMusicAddons {
                providers.append(AddonAudioProvider())
            }
        }
        return AudioProviderRegistry(providers: providers)
    }

    func bestCandidate(for song: SongItem, isrc: String?) async -> AudioCandidate? {
        guard !providers.isEmpty else { return nil }
        let query = AudioQuery(song: song, isrc: isrc)

        var all: [AudioCandidate] = []
        for provider in providers {
            all.append(contentsOf: await provider.search(query))
        }

        return all.compactMap { candidate -> AudioCandidate? in
            var score = candidate.score
            if let isrc, let candidateISRC = candidate.isrc,
               candidateISRC.caseInsensitiveCompare(isrc) == .orderedSame {
                score += 100
            } else if isrc != nil, candidate.isrc != nil {
                return nil
            }

            let title = TextMatch.normalizeTitle(candidate.song.title)
            let wantedTitle = TextMatch.normalizeTitle(song.title)
            guard !wantedTitle.isEmpty,
                  title == wantedTitle || title.contains(wantedTitle) || wantedTitle.contains(title) else {
                return nil
            }
            if title == wantedTitle { score += 50 } else { score += 20 }

            let artist = candidate.song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
            let wantedArtist = song.artists.first.map { TextMatch.normalizeArtist($0.name) } ?? ""
            if !wantedArtist.isEmpty, !artist.isEmpty {
                if artist == wantedArtist { score += 30 }
                else if artist.contains(wantedArtist) || wantedArtist.contains(artist) { score += 15 }
            }

            if song.duration > 0, candidate.song.duration > 0 {
                let delta = abs(candidate.song.duration - song.duration)
                if delta <= 5 { score += 20 } else if delta <= 15 { score += 8 } else if delta > 45 { return nil }
            }

            if candidate.source == .qobuz || candidate.source == .addon { score += 3 }
            return AudioCandidate(
                song: candidate.song,
                source: candidate.source,
                isrc: candidate.isrc,
                score: score
            )
        }.max { $0.score < $1.score }
    }
}
