import Foundation

@main
struct RadioAdvancedChecks {
    private static var passed = 0

    private static func expect(_ condition: Bool, _ label: String) {
        precondition(condition, label)
        passed += 1
    }

    static func main() {
        // HTTP ICY metadata is not the legacy "ICY 200 OK" transport.
        let mp3 = RadioTransportResolver.classifyHeaders(
            contentType: "audio/mpeg", icyMetaInt: "16000"
        )
        expect(mp3.transport == .icy && mp3.hint == "audio/mpeg",
               "HTTP MP3 with icy-metaint stays native, never application/x-icy")
        let aac = RadioTransportResolver.classifyHeaders(
            contentType: "audio/aacp; charset=utf-8", icyMetaInt: "8192"
        )
        expect(aac.transport == .icy && aac.hint == "audio/aac",
               "HTTP AAC with icy-metaint is not a legacy raw ICY response")
        let opaque = RadioTransportResolver.classifyHeaders(
            contentType: "application/octet-stream", icyMetaInt: "8192"
        )
        expect(opaque.transport == .icy && opaque.hint == nil,
               "Opaque HTTP ICY headers do not force the FFmpeg route")
        let hls = RadioTransportResolver.classifyHeaders(
            contentType: "application/vnd.apple.mpegurl", icyMetaInt: nil
        )
        expect(hls.transport == .hls && hls.hint == "application/vnd.apple.mpegurl",
               "Actual HLS MIME remains on AVFoundation HLS")
        let opus = RadioTransportResolver.classifyHeaders(
            contentType: "audio/ogg", icyMetaInt: nil
        )
        expect(opus.transport == .ffmpeg && opus.hint == "audio/ogg",
               "Ogg uses exotic FFmpeg route")
        let direct = RadioTransportResolver.classifyHeaders(
            contentType: "audio/mpeg", icyMetaInt: nil
        )
        expect(direct.transport == .direct && direct.hint == "audio/mpeg",
               "Ordinary HTTP MP3 stays native")

        // Old station's replies must not touch the current station or song.
        let old = RadioMetadataIdentity(
            generation: 11,
            stationID: "radio:station-A",
            streamURL: "https://radio.example/one"
        )
        expect(old.matches(
            generation: 11, stationID: "radio:station-A",
            streamURL: "https://radio.example/one"
        ), "Same station and generation accepted")
        expect(!old.matches(
            generation: 12, stationID: "radio:station-A",
            streamURL: "https://radio.example/one"
        ), "Later selection invalidates old metadata")
        expect(!old.matches(
            generation: 11, stationID: "radio:station-B",
            streamURL: "https://radio.example/one"
        ), "Station change invalidates old metadata")
        expect(!old.matches(
            generation: 11, stationID: "radio:station-A",
            streamURL: "https://radio.example/two"
        ), "Resolved stream change invalidates old metadata")

        let track = ICYTitleParser.parse("The Beatles - Come Together")
        expect(track?.artist == "The Beatles" && track?.title == "Come Together",
               "ICY Artist - Title parsed")
        let reverse = ICYTitleParser.parse("Hotel California by Eagles")
        expect(reverse?.artist == "Eagles" && reverse?.title == "Hotel California",
               "ICY Title by Artist parsed")
        expect(ICYTitleParser.parse("BBC Radio 1", stationName: "BBC Radio 1") == nil,
               "Station-name-only metadata is rejected")
        expect(ICYTitleParser.parse("https://suspicious.example/track") == nil,
               "URL metadata is not a song title")
        expect(ICYTitleParser.parse("jingle") == nil,
               "Generic station jingles are rejected")
        let suffix = ICYTitleParser.parse(
            "Fleetwood Mac - Dreams - Classic Vinyl on walmradio.com"
        )
        expect(suffix?.artist == "Fleetwood Mac" && suffix?.title == "Dreams",
               "Broadcaster slogan suffix is stripped")

        let tritonURL = URL(string: "https://playerservices.streamtheworld.com/api/livestream-redirect/CARACOL_RADIOAAC_SC")!
        let mounts = TritonProvider.mounts(for: tritonURL)
        expect(mounts.contains("CARACOL_RADIOAAC") && mounts.contains("CARACOL_RADIO"),
               "Triton mount strips _SC and AAC variants")
        expect(BBCRadioProvider.serviceID(
            streamURL: URL(string: "https://example.com/live")!,
            stationName: "BBC Radio 6 Music"
        ) == "bbc_6music", "BBC service id mapped without trusting URL host")
        expect(RadioFranceProvider.stationID(
            streamURL: URL(string: "https://stream.radiofrance.fr/fip")!,
            stationName: "FIP"
        ) == 7, "Radio France station identity resolved")

        print("PASS: \(passed) radio transport / metadata / station race checks")
    }
}
