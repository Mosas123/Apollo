import SwiftUI
import Nuke

/// Shows where storage goes and lets the user clear caches without touching
/// downloads. Thrum caches covers and metadata aggressively, so this makes it
/// visible and bounded.
struct StorageSettingsView: View {
    @State private var sizes = Breakdown()
    @State private var isClearing = false
    @State private var didLoad = false

    var body: some View {
        List {
            Section {
                row("Images", bytes: sizes.images)
                row("Metadata", bytes: sizes.metadata)
                row("HTTP cache", bytes: sizes.http)
                row("Logs", bytes: sizes.logs)
                row("Diagnostics", bytes: sizes.diagnostics)
                row("Downloads (not cache)", bytes: sizes.downloads)
            } footer: {
                Text("Downloads are your saved music and are never removed by clearing the cache.")
            }

            Section {
                NavigationLink {
                    TropFilesExportView()
                } label: {
                    Label("Export Logs & Downloaded Music", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    Task { await clear() }
                } label: {
                    if isClearing {
                        ProgressView()
                    } else {
                        Text("Clear Cache")
                    }
                }
                .disabled(isClearing)
                Button("Recalculate") {
                    Task { await refresh() }
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task {
            guard !didLoad else { return }
            didLoad = true
            await refresh()
        }
    }

    private func row(_ title: String, bytes: Int64) -> some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            Text(Self.format(bytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func clear() async {
        isClearing = true
        ImagePipeline.shared.configuration.dataCache?.removeAll()
        ImagePipeline.shared.configuration.imageCache?.removeAll()
        AsyncImageView.clearArtworkCache()
        URLCache.shared.removeAllCachedResponses()
        await MetadataCache.shared.clear()
        await AlbumCoverStore.shared.clear()
        Self.removeDirectory(Self.caches.appendingPathComponent("sync-debug"))
        Self.removeDirectory(Self.documents.appendingPathComponent("sync-debug"))
        await refresh()
        isClearing = false
    }

    private func refresh() async {
        sizes = await Task.detached(priority: .utility) { Self.computeSizes() }.value
    }

    // MARK: - Sizes

    private struct Breakdown {
        var images: Int64 = 0
        var metadata: Int64 = 0
        var http: Int64 = 0
        var logs: Int64 = 0
        var diagnostics: Int64 = 0
        var downloads: Int64 = 0
    }

    nonisolated private static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    nonisolated private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    nonisolated private static func computeSizes() -> Breakdown {
        var result = Breakdown()
        result.images = directorySize(caches.appendingPathComponent("com.trop.nuke"))
        result.metadata = fileSize(caches.appendingPathComponent("metadata-cache.json"))
            + fileSize(caches.appendingPathComponent("album-covers.json"))
        result.http = Int64(URLCache.shared.currentDiskUsage)
        result.logs = fileSize(documents.appendingPathComponent("log.txt"))
        result.diagnostics = directorySize(documents.appendingPathComponent("sync-debug"))
        result.downloads = directorySize(documents.appendingPathComponent("Downloads"))
        return result
    }

    nonisolated private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    nonisolated private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    nonisolated private static func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated private static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
