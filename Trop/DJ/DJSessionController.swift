import Foundation
import Observation

/// Owns an online DJ session: loads the whole pool (full audio), analyses every
/// track, asks the AI for the whole-set plan and deletes everything when the
/// session ends. The mixing engine comes later.
@MainActor
@Observable
final class DJSessionController {
    static let shared = DJSessionController()

    enum State: Equatable {
        case idle
        case preparing(done: Int, total: Int, current: String)
        case analyzing(current: String)
        case planning
        case ready
        case failed(String)
    }

    struct PreparedTrack: Equatable {
        let song: SongItem
        let source: DJSourceTrack
        let analysis: DJTrackAnalysis
        let createdBySession: Bool
    }

    private(set) var state: State = .idle
    private(set) var plan: DJMixPlan?
    private(set) var tracks: [PreparedTrack] = []
    private(set) var totalBytes: Int64 = 0
    private(set) var estimatedBytes: Int64 = 0
    private(set) var skipped: [String] = []
    private var createdVideoIDs: Set<String> = []
    private var sessionDirectory: URL?
    private var currentVideoID: String?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?

    var isBusy: Bool {
        switch state {
        case .preparing, .analyzing, .planning: return true
        case .idle, .ready, .failed: return false
        }
    }

    private init() {}

    /// Starts preparation in the background so the view can show progress and
    /// cancel it.
    func startPreparation(pool: [SongItem], instruction: String?) {
        guard !isBusy else { return }
        guard pool.count >= 4 else {
            state = .failed("Add at least 4 tracks to start a DJ set.")
            return
        }
        estimatedBytes = Self.estimatedBytes(for: pool)
        preparationTask?.cancel()
        preparationTask = Task { [weak self] in
            await self?.prepare(pool: pool, instruction: instruction)
        }
    }

    func cancelPreparation() async {
        preparationTask?.cancel()
        preparationTask = nil
        if let currentVideoID,
           await DownloadManager.shared.localURL(for: currentVideoID) == nil {
            // Only stop an in-flight session download; never delete a file the
            // user already had.
            await DownloadManager.shared.delete(videoId: currentVideoID)
        }
        await discardSession()
        state = .idle
    }

    /// Approximate size for the confirmation: CD FLAC averages ~900 kbps.
    static func estimatedBytes(for pool: [SongItem]) -> Int64 {
        pool.reduce(Int64(0)) { total, song in
            total + Int64(Double(max(song.duration, 0)) * 112_500)
        }
    }

    /// Downloads and analyses the whole pool, then waits for the AI plan. No
    /// audio starts here; the engine will consume `plan` when it exists.
    private func prepare(pool: [SongItem], instruction: String? = nil) async {
        await discardSession()
        skipped = []
        do {
            sessionDirectory = try Self.makeSessionDirectory()
        } catch {
            state = .failed("Could not create the DJ cache: \(error.localizedDescription)")
            return
        }
        guard pool.count >= 4 else {
            state = .failed("Add at least 4 tracks to start a DJ set.")
            return
        }

        // The mixing engine will not handle Atmos; keep the session on FLAC/CD
        // so every file opens with AVAudioFile.
        let previousAtmos = SettingsStore.shared.preferAtmos
        SettingsStore.shared.preferAtmos = false
        defer { SettingsStore.shared.preferAtmos = previousAtmos }

        var prepared: [PreparedTrack] = []
        state = .preparing(done: 0, total: pool.count, current: pool[0].title)

        do {
            for (index, song) in pool.enumerated() {
                try Task.checkCancellation()
                state = .preparing(done: index, total: pool.count, current: song.title)
                do {
                    let file = try await ensureLocalFile(song)
                    try Task.checkCancellation()
                    let source = DJSourceTrack(
                        id: song.videoId,
                        title: song.title,
                        artist: song.artists.map(\.name).joined(separator: ", "),
                        fileURL: file.url,
                        duration: TimeInterval(song.duration)
                    )
                    state = .analyzing(current: song.title)
                    let analysis = try await Task.detached(priority: .userInitiated) {
                        try await DJAnalyzer.analyze(source)
                    }.value
                    totalBytes += fileSize(file.url)
                    prepared.append(PreparedTrack(
                        song: song,
                        source: source,
                        analysis: analysis,
                        createdBySession: file.created
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    skipped.append("\(song.title): \(error.localizedDescription)")
                }
            }
            guard prepared.count >= 4 else {
                throw DJSessionError.notEnoughTracks(
                    prepared.count,
                    skipped: skipped
                )
            }

            state = .planning
            let pairs = prepared.map { ($0.source, $0.analysis) }
            let request = DJAIPlanner.Request(instruction: instruction)
            let aiPlan = await planWithTimeout(tracks: pairs, request: request)
            let plan = aiPlan ?? DJMixPlanner.plan(tracks: pairs)
            guard !plan.slots.isEmpty else { throw DJSessionError.emptyPlan }

            self.plan = plan
            self.tracks = prepared
            state = .ready
            persistManifest(createdVideoIDs)
        } catch is CancellationError {
            await discard(created: createdVideoIDs)
            state = .idle
        } catch {
            await discard(created: createdVideoIDs)
            state = .failed(error.localizedDescription)
        }
    }

    /// Ends the session: removes the temporary audio and analysis.
    func finish() async {
        await discardSession()
        state = .idle
    }

    func cancel() async { await finish() }

    // MARK: - Files

    /// The AI gets a generous but bounded window; without a plan the local
    /// deterministic planner keeps the set usable.
    private func planWithTimeout(
        tracks: [(DJSourceTrack, DJTrackAnalysis)],
        request: DJAIPlanner.Request,
        seconds: Double = 60
    ) async -> DJMixPlan? {
        await withTaskGroup(of: DJMixPlan?.self) { group in
            group.addTask { await DJAIPlanner.plan(tracks: tracks, request: request) }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func ensureLocalFile(_ song: SongItem) async throws -> (url: URL, created: Bool) {
        currentVideoID = song.videoId
        if let url = await DownloadManager.shared.localURL(for: song.videoId) {
            return (url, false)
        }

        // Track the id before downloading so a force-quit cannot leave an
        // orphan download in the library.
        createdVideoIDs.insert(song.videoId)
        persistManifest(createdVideoIDs)
        await DownloadManager.shared.download(song: song, confirmedLarge: true)
        guard let downloaded = await DownloadManager.shared.localURL(for: song.videoId) else {
            createdVideoIDs.remove(song.videoId)
            persistManifest(createdVideoIDs)
            if case .failed(let message) = DownloadManager.shared.state(for: song.videoId) {
                throw DJSessionError.downloadFailed(message)
            }
            throw DJSessionError.downloadFailed("Could not download \(song.title).")
        }

        guard let sessionDirectory else { throw DJSessionError.downloadFailed("Missing DJ cache.") }
        let destination = sessionDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(downloaded.pathExtension.isEmpty ? "m4a" : downloaded.pathExtension)
        try FileManager.default.copyItem(at: downloaded, to: destination)
        // The session owns its copy: remove the library download and its row.
        await DownloadManager.shared.delete(videoId: song.videoId)
        createdVideoIDs.remove(song.videoId)
        persistManifest(createdVideoIDs)
        return (destination, true)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func discardSession() async {
        await discard(created: createdVideoIDs)
        if let sessionDirectory {
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        sessionDirectory = nil
        plan = nil
        tracks = []
        totalBytes = 0
        skipped = []
        currentVideoID = nil
    }

    private func discard(created: Set<String>) async {
        for id in created {
            await DownloadManager.shared.delete(videoId: id)
        }
        createdVideoIDs.removeAll()
        clearManifest()
    }

    // MARK: - Orphan cleanup

    /// If the app died mid-session, remove the files it downloaded last time.
    static func purgeOrphanedSession() async {
        if let manifest = readManifest() {
            for id in manifest.videoIDs {
                await DownloadManager.shared.delete(videoId: id)
            }
        }
        try? FileManager.default.removeItem(at: sessionsRoot)
        try? FileManager.default.removeItem(at: manifestURL)
    }

    private static var sessionsRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DJSessions", isDirectory: true)
    }

    private static func makeSessionDirectory() throws -> URL {
        let url = sessionsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var manifestURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DJSessionManifest.json")
    }

    private struct SessionManifest: Codable {
        let createdAt: Date
        var videoIDs: [String]
    }

    private func persistManifest(_ ids: Set<String>) {
        let manifest = SessionManifest(createdAt: Date(), videoIDs: Array(ids))
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? FileManager.default.createDirectory(
            at: Self.manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.manifestURL, options: .atomic)
    }

    private func clearManifest() {
        try? FileManager.default.removeItem(at: Self.manifestURL)
    }

    private static func readManifest() -> SessionManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(SessionManifest.self, from: data)
    }

}

enum DJSessionError: LocalizedError {
    case downloadFailed(String)
    case emptyPlan
    case notEnoughTracks(Int, skipped: [String])

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return message
        case .emptyPlan:
            return "The DJ plan came back empty."
        case .notEnoughTracks(let count, let skipped):
            let detail = skipped.isEmpty ? "" : " Skipped: " + skipped.prefix(3).joined(separator: " · ")
            return "Only \(count) tracks were ready (minimum 4).\(detail)"
        }
    }
}
