import SwiftUI

/// Non-destructive preflight for replacing YouTube-account library storage.
/// Only aggregate counts are displayed; no track titles or credentials.
struct TropLibraryMigrationPreviewView: View {
    @State private var preview: TropLibraryMigrationPreview?
    @State private var dryRun: TropLibraryV2MigrationDryRun.Report?
    @State private var dryRunError: String?
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

            Section("Migration dry-run · no changes") {
                if let dryRun {
                    LabeledContent("New Trop items", value: "\(dryRun.newItems)")
                    LabeledContent("Already imported items", value: "\(dryRun.reusedItems)")
                    LabeledContent("New playlist entries", value: "\(dryRun.newEntries)")
                    LabeledContent("Already imported entries", value: "\(dryRun.existingEntries)")
                    LabeledContent(
                        "User-removed entries kept removed",
                        value: "\(dryRun.userRemovedEntries)"
                    )
                    if dryRun.hasBlockers {
                        Label("Import blocked until conflicts are resolved", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        LabeledContent(
                            "Unresolved playlist entries",
                            value: "\(dryRun.unresolvedMemberships)"
                        )
                        LabeledContent("Invalid source items", value: "\(dryRun.invalidItems)")
                        LabeledContent(
                            "Conflicting source aliases",
                            value: "\(dryRun.conflictingAliases)"
                        )
                        LabeledContent(
                            "Conflicting relationships",
                            value: "\(dryRun.conflictingRelations)"
                        )
                        LabeledContent(
                            "Broken import history",
                            value: "\(dryRun.brokenLedgerEntries)"
                        )
                    } else {
                        Label("No structural blockers found in this snapshot", systemImage: "checkmark.shield")
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "This is an estimate from a single read of the local database. "
                            + "It does not import anything, verify a restorable backup, "
                            + "or guarantee that saved songs have playable audio."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else if let dryRunError {
                    Text(dryRunError).foregroundStyle(.secondary)
                } else if isLoading {
                    ProgressView("Checking migration")
                }
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
            do {
                dryRun = try await TropLibraryV2MigrationDryRun.load()
                dryRunError = nil
            } catch {
                dryRun = nil
                dryRunError = "The dry-run check is unavailable. Nothing was imported."
            }
        } catch {
            errorMessage = "Could not read the local library. No changes were made."
        }
    }
}
