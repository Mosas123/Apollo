import SwiftUI
import UniformTypeIdentifiers

struct PlaylistImportView: View {
    @State private var isPickingFile = false
    @State private var isImporting = false
    @State private var summary: PlaylistImportSummary?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Export a playlist from Spotify with Exportify, or use any CSV with song title and artist columns. Nothing is uploaded; Apollo only reads the file.")
                    .font(.footnote)
                Link(destination: URL(string: "https://exportify.app")!) {
                    Label("Open Exportify (free, open source)", systemImage: "safari")
                }
            } header: {
                Text("From another platform")
            } footer: {
                Text("For Apple Music or YouTube Music, move the playlist to Spotify with a free transfer tool first, then export it as CSV.")
            }

            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label(isImporting ? "Importing…" : "Choose CSV file", systemImage: "doc.badge.plus")
                }
                .disabled(isImporting)
            }

            if let summary {
                Section("Imported") {
                    LabeledContent("Playlist", value: summary.playlistName)
                    LabeledContent("Songs", value: "\(summary.imported)")
                    if summary.skipped > 0 {
                        LabeledContent("Skipped", value: "\(summary.skipped)")
                    }
                    NavigationLink("Open playlist") {
                        PlaylistDetailView(playlistId: summary.playlistID)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Import playlist")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
        .miniPlayerTracksScroll()
    }

    private func handle(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isImporting = true
            errorMessage = nil
            summary = nil
            Task {
                do {
                    let imported = try await PlaylistImportService().importFile(at: url)
                    await MainActor.run {
                        summary = imported
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        isImporting = false
                    }
                }
            }
        }
    }
}
