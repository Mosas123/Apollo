import Foundation

@main
struct PortableLibraryCSVChecks {
    static func main() throws {
        let parser = PortableLibraryCSVImporter()
        let soundiiz = #"""
        title,artist,album,isrc,platform,trackId,duration,addedDate
        "Hello, World","Artist ""A""","Album, One",US-AAA-23-00001,Spotify,track-1,201,2025-01-01
        Second Song,Another Artist,Other Album,US-AAA-23-00002,Qobuz,1099,180,2025-01-02
        """#
        let first = try parser.parse(
            data: Data(soundiiz.utf8), fileName: "My Mix.csv",
            destinationAccountID: "profile-A"
        )
        let again = try parser.parse(
            data: Data(soundiiz.utf8), fileName: "My Mix.csv",
            destinationAccountID: "profile-A"
        )
        precondition(first.rows.count == 2)
        precondition(first.playlistItem?.title == "My Mix")
        precondition(first.rows[0].item.title == "Hello, World")
        precondition(first.rows[0].artist == "Artist \"A\"")
        precondition(first.rows[0].album == "Album, One")
        precondition(first.rows[0].item.isrc == "USAAA2300001")
        precondition(first.rows[0].item.source.provider == "spotify")
        precondition(first.rows[0].item.source.remoteID == "track-1")
        precondition(first.rows[1].item.source.provider == "qobuz")
        precondition(first.rows[1].item.source.remoteID == "1099")
        precondition(first.rows.map(\.position) == [0, 1])
        precondition(first.libraryItems.count == 3)
        precondition(first.rows.map(\.item) == again.rows.map(\.item))
        precondition(first.sourceFileHash == again.sourceFileHash)

        let spotifyID = "0VjIjW4GlUZAMYd2vXMi3b"
        let exportify = """
        Track URI;Track Name;Artist Name(s);Album Name;ISRC
        spotify:track:\(spotifyID);Blinding Lights;The Weeknd;After Hours;USUG11904206
        spotify:track:\(spotifyID);Blinding Lights;The Weeknd;After Hours;USUG11904206
        """
        let second = try parser.parse(
            data: Data(exportify.utf8), fileName: "Exportify.csv",
            destinationAccountID: "profile-A"
        )
        precondition(second.rows.count == 2)
        precondition(second.rows[0].item.source.provider == "spotify")
        precondition(second.rows[0].item.source.remoteID == spotifyID)
        precondition(second.rows[1].item.source.remoteID == spotifyID)
        // The user's playlist can contain repeat occurrences in order.
        precondition(second.rows.map(\.position) == [0, 1])
        let planned = try LibraryImportPlanner().preview(
            incoming: second.libraryItems, existing: [],
            activeAccountID: "profile-A",
            selectedKinds: Set(UnifiedLibraryItemKind.allCases)
        )
        precondition(planned.inserts.count == 2) // one playlist + one track
        precondition(planned.duplicateInputs.count == 1)

        let fallback = """
        title\tartist\talbum
        Una Canción\tCantante\tDisco
        Una Canción\tCantante\tDisco
        """
        let third = try parser.parse(
            data: Data(fallback.utf8), fileName: "Favorites.csv",
            destinationAccountID: "profile-A", importAsPlaylist: false
        )
        precondition(third.playlistItem == nil)
        precondition(third.libraryItems.count == 2)
        precondition(third.rows[0].item.source.provider == "portableFile")
        precondition(third.rows[0].item.source.remoteID != third.rows[1].item.source.remoteID)
        let reimport = try parser.parse(
            data: Data(fallback.utf8), fileName: "Favorites.csv",
            destinationAccountID: "profile-A", importAsPlaylist: false
        )
        precondition(third.rows[0].item.source == reimport.rows[0].item.source)

        let bom = "\u{FEFF}title,artist\r\n" +
            "Café,Beyoncé\r\n" +
            "Héroes,David Bowie\r\n"
        let fourth = try parser.parse(
            data: Data(bom.utf8), fileName: "BOM.csv",
            destinationAccountID: "profile-A"
        )
        precondition(fourth.rows.map { $0.item.title } == ["Café", "Héroes"])

        func rejected(_ expected: PortableLibraryFileError, _ data: Data) {
            do {
                _ = try parser.parse(
                    data: data, fileName: "Bad.csv",
                    destinationAccountID: "profile-A"
                )
                preconditionFailure("Expected \(expected)")
            } catch let found as PortableLibraryFileError {
                precondition(found == expected)
            } catch {
                preconditionFailure("Unexpected \(error)")
            }
        }
        rejected(.missingTitleColumn, Data("performer,album\nA,B".utf8))
        rejected(.invalidCSV, Data("title,artist\n\"unterminated,Artist".utf8))
        rejected(.invalidCSV, Data("title,artist\n\"Title\"broken,Artist".utf8))
        rejected(.missingRows, Data("title,artist\n".utf8))
        rejected(.invalidEncoding, Data([0xFF, 0xFE]))
        rejected(.fileTooLarge, Data(repeating: 0x41, count: PortableLibraryCSVImporter.maximumBytes + 1))

        // File content never runs arbitrary remote code or initiates requests.
        // This unit test consumes local fixture bytes only.
        print("Portable library CSV import checks passed")
    }
}
