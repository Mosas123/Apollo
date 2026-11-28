import Foundation

@main
struct PlaylistCSVImporterChecks {
    static func main() throws {
        let exportify = """
        Track URI,Track Name,Artist Name(s),Album Name,Album Image URL,Track Duration (ms),Explicit?,ISRC
        spotify:track:abc123,"Song, One","Artist A","Album One",https://i.scdn.co/image/a,234000,true,USABC1234567
        https://open.spotify.com/track/def456,Song Two,Artist B,Album Two,,180500,false,
        """
        let file = try PlaylistCSVImporter().parse(
            data: Data(exportify.utf8),
            fileName: "My Mix.csv"
        )
        precondition(file.name == "My Mix")
        precondition(file.rows.count == 2)
        precondition(file.rows[0].title == "Song, One")
        precondition(file.rows[0].artist == "Artist A")
        precondition(file.rows[0].durationSeconds == 234)
        precondition(file.rows[0].isExplicit)
        precondition(file.rows[0].spotifyTrackID == "abc123")
        precondition(file.rows[0].isrc == "USABC1234567")
        precondition(file.rows[1].spotifyTrackID == "def456")
        precondition(!file.rows[1].isExplicit)
        precondition(file.rows[1].durationSeconds == 180)

        let semicolon = """
        Track Name;Artist;Duration;Explicit
        Otra canción;Artista;3:45;no
        """
        let second = try PlaylistCSVImporter().parse(
            data: Data(semicolon.utf8),
            fileName: "otra.csv"
        )
        precondition(second.rows[0].title == "Otra canción")
        precondition(second.rows[0].durationSeconds == 225)
        precondition(second.rows[0].spotifyTrackID == nil)

        do {
            _ = try PlaylistCSVImporter().parse(
                data: Data("Artist,Album\nA,B\n".utf8),
                fileName: "bad.csv"
            )
            preconditionFailure("CSV without a title column must fail")
        } catch PlaylistCSVError.missingTitle {
        }

        print("PlaylistCSVImporterChecks passed")
    }
}
