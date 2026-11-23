import SwiftUI
import UIKit

/// A user-initiated copy through the system Files picker. It never moves
/// downloads out of the app's playback directory or requires iCloud.
struct TropFilesExportView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var search = ""
    @State private var exportRequest: ExportRequest?
    @State private var stagedLogDirectory: URL?
    @State private var errorMessage: String?
    @State private var showingError = false

    private struct ExportRequest: Identifiable {
        let id = UUID()
        let files: [URL]
    }

    private var visibleTracks: [DownloadedTrackEntity] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return downloadManager.tracks }
        return downloadManager.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.artist.localizedCaseInsensitiveContains(query)
        }
    }

    private var documents: URL {
        FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
    }

    var body: some View {
        List {
            Section {
                Button {
                    exportLogs()
                } label: {
                    Label("Export Current & Previous Logs", systemImage: "doc.text")
                }
            } header: {
                Text("Diagnostic logs")
            } footer: {
                Text(
                    "Copies are sanitized to hide common sensitive values. "
                        + "Please inspect them before sharing. Nothing is "
                        + "uploaded automatically, and original logs stay in Thrum."
                )
            }

            Section {
                if !downloadManager.isLoaded {
                    ProgressView("Loading downloaded songs…")
                } else if downloadManager.tracks.isEmpty {
                    Text("No music files downloaded yet.")
                        .foregroundStyle(.secondary)
                } else if visibleTracks.isEmpty {
                    Text("No matching downloads.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleTracks, id: \.id) { track in
                        Button {
                            exportDownload(track)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title)
                                    .foregroundStyle(.primary)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Export " + track.title)
                    }
                }
            } header: {
                Text("Downloaded music")
            } footer: {
                Text(
                    "Choose a song, then choose its destination in Files. "
                        + "Only a copy is exported: the playable original "
                        + "remains in Thrum. Large FLAC files use disk space "
                        + "at the destination; no bulk copies are made."
                )
            }
        }
        .navigationTitle("Export Files")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search downloaded songs")
        .miniPlayerTracksScroll()
        .task {
            if !downloadManager.isLoaded {
                await downloadManager.reload()
            }
        }
        .sheet(item: $exportRequest, onDismiss: cleanupStagedLogs) { request in
            TropFilesDocumentExportPicker(files: request.files) {
                exportRequest = nil
            }
        }
        .alert("Could not export files", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @MainActor
    private func exportLogs() {
        cleanupStagedLogs()
        do {
            let staged = try TropFilesExportPolicy.stageSanitizedLogs(
                documents: documents,
                temporaryDirectory: FileManager.default.temporaryDirectory
            )
            stagedLogDirectory = staged.directory
            exportRequest = ExportRequest(files: staged.files)
        } catch {
            showError(error.localizedDescription)
        }
    }

    @MainActor
    private func exportDownload(_ track: DownloadedTrackEntity) {
        let directory = documents.appendingPathComponent(
            "Downloads", isDirectory: true
        )
        guard let url = TropFilesExportPolicy.safeDownloadedAudioURL(
            storedPath: track.localPath, downloadsDirectory: directory
        ) else {
            showError("This downloaded audio file is missing or cannot be exported.")
            return
        }
        exportRequest = ExportRequest(files: [url])
    }

    @MainActor
    private func cleanupStagedLogs() {
        guard let directory = stagedLogDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        stagedLogDirectory = nil
    }

    @MainActor
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

private struct TropFilesDocumentExportPicker: UIViewControllerRepresentable {
    let files: [URL]
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forExporting: files, asCopy: true
        )
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ controller: UIDocumentPickerViewController, context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onFinish()
        }
    }
}
