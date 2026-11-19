import Foundation
import ApoloEngine

/// First-stage audio backend for the Thrum music-only beta.
///
/// This adapter deliberately does NOT register system media commands or own
/// AVAudioSession: Thrum already owns both. The application will route sources
/// to it in a separate PR after the mixed FFmpeg/MPVKit build is validated.
@MainActor
final class ApoloAudioBackend {
    private let engine = ApoloEngine(
        managesSystemMediaControls: false,
        managesAudioSession: false
    )

    var state: PlaybackState { engine.state }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }

    var volume: Float {
        get { engine.volume }
        set { engine.volume = max(0, min(1, newValue)) }
    }

    func load(
        audioURL: URL,
        httpHeaders: [String: String] = [:],
        title: String,
        artist: String,
        album: String? = nil,
        artworkData: Data? = nil,
        sourceMIMEType: String? = nil,
        isAtmos: Bool = false
    ) async throws {
        try await engine.load(
            url: audioURL,
            httpHeaders: httpHeaders,
            metadata: NowPlayingMetadata(
                title: title,
                artist: artist,
                album: album,
                artworkData: artworkData
            ),
            sourceMIMEType: sourceMIMEType,
            isAtmos: isAtmos
        )
    }

    func play() { engine.play() }
    func pause() { engine.pause() }
    func seek(to seconds: TimeInterval) async { await engine.seek(to: seconds) }
    func stop() { engine.stop() }
}
