import Foundation

@main
struct LocalAudioFileChecks {
    static func main() {
        let local = { (name: String) -> URL in
            URL(fileURLWithPath: "/tmp/Audio Library/\(name)")
        }
        for ext in ["m4a", "m4b", "mp3", "aac", "FLAC", "wav", "ogg", "opus", "ape", "tta"] {
            precondition(LocalAudioFilePolicy.supports(local("song.\(ext)")),
                "Audio extension should be importable: \(ext)")
        }
        precondition(!LocalAudioFilePolicy.supports(local("document.pdf")))
        precondition(!LocalAudioFilePolicy.supports(local("folder")))
        precondition(!LocalAudioFilePolicy.supports(
            URL(string: "https://example.org/song.mp3")!
        ))
        precondition(!LocalAudioFilePolicy.isValidAudioSize(0))
        precondition(!LocalAudioFilePolicy.isValidAudioSize(8_191))
        precondition(LocalAudioFilePolicy.isValidAudioSize(8_192))
        precondition(LocalAudioFilePolicy.mimeHint(for: local("song.flac")) == "audio/flac")
        precondition(LocalAudioFilePolicy.mimeHint(for: local("song.mp3")) == "audio/mpeg")
        precondition(LocalAudioFilePolicy.mimeHint(for: local("song.m4a")) == "audio/mp4")
        precondition(LocalAudioFilePolicy.mimeHint(for: local("song.ogg")) == "audio/ogg")
        let id = "local:123E4567-E89B-12D3-A456-426614174000"
        let fileName = LocalAudioFilePolicy.storedFilename(
            title: "An Artist - My Song",
            videoId: id,
            fileExtension: "FLAC"
        )
        precondition(fileName.hasSuffix(".flac"))
        precondition(LocalAudioFilePolicy.videoId(from: fileName) == id,
            "Imported tracks must remain discoverable after app restart")
        precondition(LocalAudioFilePolicy.videoId(
            from: "Artist - Track [dQw4w9WgXcQ].mp3"
        ) == "dQw4w9WgXcQ", "Existing downloaded IDs must remain compatible")
        precondition(LocalAudioFilePolicy.videoId(
            from: "untagged-track.m4a"
        ) == nil, "Do not accidentally adopt unrelated sandbox files")
        print("PASS: local audio extension, MIME, size and persisted ID checks")
    }
}
