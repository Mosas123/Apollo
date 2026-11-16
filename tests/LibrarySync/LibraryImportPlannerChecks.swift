import Foundation

@main
struct LibraryImportPlannerChecks {
    static func main() throws {
        let account = "google-account-A"
        func ref(_ provider: String, _ itemID: String, accountID: String = account) -> LibrarySourceReference {
            LibrarySourceReference(provider: provider, accountID: accountID, remoteID: itemID)
        }
        func incoming(
            _ kind: UnifiedLibraryItemKind, _ id: String,
            _ name: String, provider: String = "youtubeMusic", isrc: String? = nil,
            accountID: String = account
        ) -> IncomingLibraryItem {
            IncomingLibraryItem(kind: kind, source: ref(provider, id, accountID: accountID),
                                title: name, isrc: isrc)
        }
        let planner = LibraryImportPlanner()
        let source = ref("youtubeMusic", "song1")
        let existing: [ExistingLibraryItem] = [
            ExistingLibraryItem(canonicalID: "local-track-01", kind: .track,
                                sources: [source], isrc: nil),
            ExistingLibraryItem(canonicalID: "local-track-02", kind: .track,
                                sources: [ref("audius", "a_444")], isrc: "US-AAA-23-00001"),
            ExistingLibraryItem(canonicalID: "podcast1", kind: .podcast,
                                sources: [ref("youtubeMusic", "pod1")], isrc: nil)
        ]

        let batch: [IncomingLibraryItem] = [
            incoming(.track, "song1", "Locally renamed by user"),
            incoming(.track, "song2", "Same Song", isrc: "usaaa2300001"),
            incoming(.track, "song3", "Same Song", isrc: "US-AAA-23-00002"),
            incoming(.track, "song4", "Same Song", isrc: "US-AAA-23-00002"),
            incoming(.playlist, "list-one", "Morning"),
            incoming(.playlist, "list-two", "Morning"),
            incoming(.podcast, "pod1", "Subscribed podcast"),
            incoming(.episode, "episode123", "Episode One"),
            incoming(.track, "song1", "Duplicate batch record")
        ]

        let plan = try planner.preview(
            incoming: batch, existing: existing,
            activeAccountID: account,
            selectedKinds: Set(UnifiedLibraryItemKind.allCases)
        )

        // Existing local items (including a user title override) are preserved.
        precondition(plan.alreadyPresent.count == 2)
        precondition(plan.links.count == 1)
        precondition(plan.links[0].canonicalID == "local-track-02")
        precondition(plan.links[0].source.remoteID == "song2")
        precondition(plan.duplicateInputs.count == 1)
        precondition(plan.inserts.count == 4)
        precondition(plan.totalNewSourceLinks == 6)
        precondition(plan.needsReview.isEmpty)

        // Two different track IDs with verified identical ISRC become ONE new
        // canonical recording with TWO provenance references.
        let joined = plan.inserts.first { $0.kind == .track }
        precondition(joined?.isrc == "USAAA2300002")
        precondition(joined?.sources.map(\.remoteID) == ["song3", "song4"])

        // Identical names are not safe evidence for merging playlists.
        let playlists = plan.inserts.filter { $0.kind == .playlist }
        precondition(playlists.count == 2)
        precondition(playlists[0].title == playlists[1].title)

        let onlyPodcasts = try planner.preview(
            incoming: batch, existing: existing,
            activeAccountID: account, selectedKinds: [.podcast, .episode]
        )
        precondition(onlyPodcasts.inserts.count == 1)
        precondition(onlyPodcasts.inserts[0].kind == .episode)
        precondition(onlyPodcasts.skippedUnselected.count == 7)

        // A change of login/account must NOT be treated as empty remote library,
        // nor silently merge another person's data.
        do {
            _ = try planner.preview(
                incoming: [incoming(.track, "abc", "Other account", accountID: "google-account-B")],
                existing: existing, activeAccountID: account,
                selectedKinds: [.track]
            )
            preconditionFailure("Account switch must fail closed")
        } catch LibraryImportError.accountChanged {}

        // Multiple local candidates for one ISRC must go to manual review:
        // choosing either would silently conflate two different records.
        let ambiguous = try planner.preview(
            incoming: [incoming(.track, "new", "Ambiguous", isrc: "USAAA2300003")],
            existing: [
                ExistingLibraryItem(canonicalID: "one", kind: .track,
                                    sources: [ref("audius", "a")], isrc: "USAAA2300003"),
                ExistingLibraryItem(canonicalID: "two", kind: .track,
                                    sources: [ref("qobuz", "q")], isrc: "USAAA2300003")
            ], activeAccountID: account, selectedKinds: [.track]
        )
        precondition(ambiguous.needsReview.count == 1)
        precondition(ambiguous.inserts.isEmpty)
        precondition(ambiguous.links.isEmpty)

        // Same title, different episode IDs are separate episodes. Never
        // infer podcast progress or episode identity from name alone.
        let episodes = try planner.preview(
            incoming: [
                incoming(.episode, "ep1", "Pilot"),
                incoming(.episode, "ep2", "Pilot")
            ], existing: [], activeAccountID: account, selectedKinds: [.episode]
        )
        precondition(episodes.inserts.count == 2)

        precondition(LibraryImportPlanner.normalizedISRC("us-aaa-23-00001") == "USAAA2300001")
        precondition(LibraryImportPlanner.normalizedISRC("some track title") == nil)
        precondition(LibraryImportPlanner.normalizedISRC("USAAAA2300001") == nil)
        precondition(LibraryImportPlanner.normalizedISRC(nil) == nil)

        // An empty/partial remote scan does not infer deletion, unliking,
        // unsubscribe or removal of local playlists.
        let empty = try planner.preview(
            incoming: [], existing: existing, activeAccountID: account,
            selectedKinds: Set(UnifiedLibraryItemKind.allCases)
        )
        precondition(empty.inserts.isEmpty && empty.links.isEmpty)

        print("Library import planner checks passed")
    }
}
