import SwiftUI

/// Non-destructive preflight for replacing YouTube-account library storage.
/// Only aggregate counts are displayed; no track titles or credentials.
struct TropLibraryMigrationPreviewView: View {
    @State private var preview: TropLibraryMigrationPreview?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Label("Your library belongs to Trop", systemImage: "music.note.list")
                    .font(.headline)
                Text("These are the items currently saved on this iPhone. This screen only counts local records. It does not import, move, delete, or upload anything.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Live iCloud syncing is not enabled yet. Downloads will stay on this device.")
            }

            Section("Local library snapshot") {
                if let preview {
                    LabeledContent("Liked songs", value: "\(preview.likedSongs)")
                    LabeledContent("Saved albums", value: "\(preview.savedAlbums)")
                    LabeledContent("Followed artists", value: "\(preview.followedArtists)")
                    LabeledContent("Saved playlists", value: "\(preview.savedPlaylists)")
                    LabeledContent("Playlist entries", value: "\(preview.playlistMemberships)")
                    LabeledContent("Followed podcasts", value: "\(preview.followedPodcasts)")
                    LabeledContent("Saved episodes", value: "\(preview.savedEpisodes)")
                } else if isLoading {
                    ProgressView("Checking local library")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No snapshot yet")
                        .foregroundStyle(.secondary)
                }

                Button("Refresh counts") {
                    Task { await refresh() }
                }
                .disabled(isLoading)
            }

            if let preview {
                Section("Items needing extra care") {
                    LabeledContent(
                        "YouTube-linked playlists",
                        value: "\(preview.youtubeLinkedPlaylists)"
                    )
                    LabeledContent(
                        "Unresolved playlist entries",
                        value: "\(preview.orphanPlaylistMemberships)"
                    )
                    Text("Linked playlists and unresolved entries must be preserved during migration. Existing playlist storage does not yet support adding the same song twice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Label("No files will be uploaded", systemImage: "lock.icloud")
                Text("Our next stages will assign independent Trop IDs, preserve old references for recovery, and only then connect your saved metadata to private iCloud.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Library Migration")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refresh() }
    }

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            preview = try await TropLibraryMigrationPreview.load()
            errorMessage = nil
        } catch {
            errorMessage = "Could not read the local library. No changes were made."
        }
    }
}
