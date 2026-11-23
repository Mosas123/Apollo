import Foundation

@main
struct TropLibraryV2PrelinkBatchPolicyChecks {
    static func main() {
        let ids = (0..<23).map {
            String(format: "00000000-0000-0000-0000-%012d", $0)
        }
        precondition(ids.allSatisfy(TropLibraryV2IdentityPolicy.isCanonicalID))

        let first = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: Array(ids.reversed()) + Array(ids.prefix(5)), after: nil
        )
        precondition(first.recordingIDs == Array(ids[0..<8]))
        precondition(first.completedBefore == 0)
        precondition(first.total == 23)
        precondition(first.hasMore)

        let second = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: ids, after: first.recordingIDs.last
        )
        precondition(second.recordingIDs == Array(ids[8..<16]))
        precondition(second.completedBefore == 8)
        precondition(second.hasMore)

        let third = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: ids, after: second.recordingIDs.last
        )
        precondition(third.recordingIDs == Array(ids[16..<23]))
        precondition(!third.hasMore)

        let complete = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: ids, after: third.recordingIDs.last
        )
        precondition(complete.recordingIDs.isEmpty)
        precondition(complete.completedBefore == 23)
        precondition(complete.total == 23)

        // A recording deleted between runs cannot strand the cursor.
        let removedCursor = ids.filter { $0 != ids[7] }
        let afterDeleted = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: removedCursor, after: ids[7]
        )
        precondition(afterDeleted.recordingIDs.first == ids[8])

        // Inserting a new ID after the cursor is picked up in a future page.
        let inserted = "00000000-0000-0000-0000-000000000099"
        let withNew = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: ids + [inserted], after: ids.last
        )
        precondition(withNew.recordingIDs == [inserted])

        // Malformed and legacy source IDs may never be persisted as cursors.
        let invalid = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: ids + ["YT-videoId", "addon:bad"], after: "YT-videoId"
        )
        precondition(invalid.total == 23)
        precondition(invalid.recordingIDs == Array(ids.prefix(8)))
        precondition(
            TropLibraryV2PrelinkBatchPolicy.status(
                savedIDs: ids, after: third.recordingIDs.last
            ).completed == 23
        )
        print("Library V2 prelink batches passed: bounded, stable, resumable, deduplicated")
    }
}
