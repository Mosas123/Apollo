import Foundation

/// One shared radio start path for discovery and saved favorites. This
/// intentionally does not persist stream URLs or depend on a sign-in.
@MainActor
enum RadioPlaybackCoordinator {
    static func play(_ station: RadioStation) async {
        guard let stream = station.streamURL else { return }
        Log.player.info("RADIO_UI selection stationId=\(station.stationuuid)")
        NowPlaying.shared.bumpPlaybackIntent()
        let generation = NowPlaying.shared.playbackGeneration
        let hint: String?
        if SettingsStore.shared.apoloRadioBetaEnabled {
            hint = await RadioTransportResolver.shared.hint(for: station)
        } else {
            hint = station.apoloMIMEHint
        }
        guard generation == NowPlaying.shared.playbackGeneration else { return }
        await PlayerController.shared.play(
            url: stream,
            title: station.name,
            artist: station.subtitle.isEmpty ? nil : station.subtitle,
            videoId: NowPlaying.radioPrefix + station.stationuuid,
            duration: nil,
            thumbnailUrl: station.iconURL,
            sourceMIMEType: hint
        )
    }

    static func playSaved(stationUUID: String) async throws {
        let station = try await RadioBrowser.station(uuid: stationUUID)
        guard station.streamURL != nil else {
            throw RadioBrowserError.stationUnavailable
        }
        await play(station)
    }
}
