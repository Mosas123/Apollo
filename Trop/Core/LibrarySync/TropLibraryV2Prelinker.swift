import Foundation

/// Opportunistic, foreground-only provider associations for SAVED Library V2
/// recordings. Home, Search and Explore do not call this service. A saved Trop
/// UUID remains valid even if every provider is unavailable or times out.
@MainActor
final class TropLibraryV2Prelinker {
    static let shared = TropLibraryV2Prelinker()

    private var pendingIDs: [String] = []
    private var queuedIDs = Set<String>()
    private var lastAttempt: [String: Date] = [:]
    private var worker: Task<Void, Never>?
    private var isManualBatchRunning = false

    private init() {}

    /// Called only AFTER a successful saved-library database transaction.
    /// Enqueuing never waits for a network search or changes playback state.
    func schedule(recordingID: String) {
        guard TropLibraryV2IdentityPolicy.isCanonicalID(recordingID),
              !queuedIDs.contains(recordingID),
              pendingIDs.count < TropLibraryV2PrelinkPolicy.maximumQueuedRecordings
        else { return }
        if let last = lastAttempt[recordingID],
           Date().timeIntervalSince(last) <
            TropLibraryV2PrelinkPolicy.retryInterval {
            return
        }
        queuedIDs.insert(recordingID)
        pendingIDs.append(recordingID)
        startWorkerIfNeeded()
    }

    /// The most recent few saved songs receive a best-effort prelink when the
    /// Library opens. Never resolve a whole changing Home feed or a 480-song
    /// restored archive in one uncontrolled network burst.
    func scheduleVisibleLibrary(
        _ recordings: [TropLibraryV2Store.RecordingSummary]
    ) {
        for recording in recordings.prefix(
            TropLibraryV2PrelinkPolicy.visibleLibraryBudget
        ) where TropLibraryV2PrelinkPolicy.hasSufficientMetadata(
            title: recording.title,
            artist: recording.artist,
            durationSeconds: recording.durationSeconds
        ) {
            schedule(recordingID: recording.id)
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil, !isManualBatchRunning,
              !pendingIDs.isEmpty else { return }
        worker = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.drain()
        }
    }

    private func drain() async {
        defer { worker = nil }
        while !Task.isCancelled, !pendingIDs.isEmpty {
            let id = pendingIDs.removeFirst()
            queuedIDs.remove(id)
            lastAttempt[id] = Date()
            await inspectOneSavedRecording(id)
        }
    }

    struct BatchProgress: Sendable {
        let processed: Int
        let total: Int
        let hasMore: Bool
    }

    enum BatchError: Error, LocalizedError {
        case alreadyRunning

        var errorDescription: String? {
            "A saved-music matching batch is already running."
        }
    }

    /// Only called from an explicit Library V2 Settings action.
    /// One tap inspects at most eight SAVED recordings; cursor state is saved
    /// after each completed attempt so an app restart never restarts a long
    /// batch from scratch. No background scan or automatic bulk import.
    func scanNextBatch() async throws -> BatchProgress {
        guard !isManualBatchRunning else { throw BatchError.alreadyRunning }
        isManualBatchRunning = true
        defer {
            isManualBatchRunning = false
            startWorkerIfNeeded()
        }
        // Prevent two independent search pipelines from hammering providers.
        if let worker { await worker.value }
        try Task.checkCancellation()
        let recordings = try await TropLibraryV2Store.recordings()
        let cursor = UserDefaults.standard.string(
            forKey: TropLibraryV2PrelinkBatchPolicy.cursorKey
        )
        let page = TropLibraryV2PrelinkBatchPolicy.page(
            savedIDs: recordings.map(\.id), after: cursor
        )
        var processed = page.completedBefore
        for id in page.recordingIDs {
            try Task.checkCancellation()
            lastAttempt[id] = Date()
            await inspectOneSavedRecording(id)
            try Task.checkCancellation()
            UserDefaults.standard.set(
                id, forKey: TropLibraryV2PrelinkBatchPolicy.cursorKey
            )
            processed += 1
            // Add breathing room between searches even on fast networks.
            if processed < page.total {
                try await Task.sleep(nanoseconds: 350_000_000)
            }
        }
        return BatchProgress(
            processed: processed, total: page.total,
            hasMore: processed < page.total
        )
    }

    func batchProgress() async throws -> BatchProgress {
        let recordings = try await TropLibraryV2Store.recordings()
        let cursor = UserDefaults.standard.string(
            forKey: TropLibraryV2PrelinkBatchPolicy.cursorKey
        )
        let state = TropLibraryV2PrelinkBatchPolicy.status(
            savedIDs: recordings.map(\.id), after: cursor
        )
        return BatchProgress(
            processed: state.completed, total: state.total,
            hasMore: state.completed < state.total
        )
    }

    /// Re-run already examined recordings only after a user confirmation.
    func restartManualScan() {
        guard !isManualBatchRunning else { return }
        UserDefaults.standard.removeObject(
            forKey: TropLibraryV2PrelinkBatchPolicy.cursorKey
        )
    }

    private func inspectOneSavedRecording(_ id: String) async {
        do {
            guard let recording = try await TropLibraryV2Store.recording(
                withID: id
            ), TropLibraryV2PrelinkPolicy.hasSufficientMetadata(
                title: recording.title, artist: recording.artist,
                durationSeconds: recording.durationSeconds
            ) else { return }

            let aliases = try await TropLibraryV2Store.sourceAliases(
                forRecordingID: id
            )
            let availableSlots = TropLibraryV2PrelinkPolicy.maximumIndependentAliases
                - aliases.filter {
                    ["addon", "qobuz", "audius", "jiosaavn"].contains(
                        $0.provider
                    ) && $0.scope == "global"
                }.count
            guard availableSlots > 0, !Task.isCancelled else { return }

            // Always inspect metadata in unrestricted quality mode: a saved
            // recording can later switch quality without changing its UUID.
            // Actual codec/bit depth is checked by the playback engine.
            let results = await TropLibraryV2AudioDiscovery.inspect(
                for: recording, requiresLossless: false
            )
            guard !Task.isCancelled else { return }
            let selected = TropLibraryV2PrelinkPolicy.eligibleNewLinks(
                title: recording.title, artist: recording.artist,
                durationSeconds: recording.durationSeconds,
                existingAliases: aliases, candidates: results.exact
            )
            var linked = 0
            for candidate in selected {
                guard !Task.isCancelled else { break }
                do {
                    // This re-reads the CURRENT recording and owner inside
                    // a GRDB write transaction. A stale search cannot mutate
                    // the identity, like, playlist or downloaded file.
                    try await TropLibraryV2Store.linkConfirmedAudioSource(
                        toRecordingID: id, track: candidate,
                        requiresLossless: false
                    )
                    linked += 1
                } catch {
                    // Provider ownership collisions, deleted songs and
                    // changing metadata are benign prelink misses.
                    continue
                }
            }
            Log.libraryView.debug(
                "TROP_MATCH_PRELINK completed linked=\(linked) exactCandidates=\(results.exact.count)"
            )
        } catch {
            // No app-wide error or user-facing modal: an unavailable provider
            // must never prevent the saved library from opening normally.
            Log.libraryView.debug("TROP_MATCH_PRELINK unavailable")
        }
    }
}
