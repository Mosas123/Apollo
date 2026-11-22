import Foundation
import SwiftUI

/// Experimental, metadata-only recovery for a genuinely EMPTY installation.
/// File selection and archive inspection are read-only. The only actual write
/// is the explicit confirmation below, which invokes the production GRDB
/// transaction that checks emptiness again INSIDE the same write transaction.
/// No "reset library", replace, merge or deletion route is exposed here.
struct TropLibraryCombinedRestoreView: View {
    @State private var isChecking = true
    @State private var isEligible = false
    @State private var isPicking = false
    @State private var isReading = false
    @State private var isRestoring = false
    @State private var showConfirmation = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var preview: TropLibraryCombinedBackupService.Preview?
    @State private var pendingArchive: Data?
    @State private var completed = false

    private var canSelectFile: Bool {
        isEligible && !isChecking && !isReading && !isRestoring
            && !completed
    }

    var body: some View {
        List {
            Section {
                Label("Restore metadata to a new library", systemImage: "arrow.uturn.backward.circle")
                    .font(.headline)
                Text(
                    "Choose a combined Trop backup from Files, iCloud Drive, "
                        + "or another Files location. This restores saved music "
                        + "metadata, playlists, likes, radio and supported podcast "
                        + "relationships. It does not restore downloaded audio, "
                        + "credentials, history or private provider connections."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Safety check") {
                if isChecking {
                    Label("Checking that this library is empty…", systemImage: "clock")
                } else if completed {
                    Label("Metadata restored to this library", systemImage: "checkmark.seal")
                } else if isEligible {
                    Label("Empty library: eligible to import a backup", systemImage: "checkmark.shield")
                } else {
                    Label("This library is not eligible for restore", systemImage: "lock.shield")
                    Text(
                        "To protect existing music and downloads, Trop refuses "
                            + "to import a backup into an occupied or unavailable "
                            + "database. There is no reset or overwrite option."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Button("Check empty-library eligibility again") {
                    Task { await checkEligibility() }
                }
                .disabled(isReading || isRestoring || isChecking || completed)
            }

            Section("Choose a backup") {
                Button {
                    isPicking = true
                } label: {
                    Label(
                        isReading ? "Checking backup…" : "Choose combined backup in Files",
                        systemImage: "doc.badge.arrow.up"
                    )
                }
                .disabled(!canSelectFile)
                Text(
                    "Only metadata archives in the combined Trop format are accepted. "
                        + "A selected archive is verified before you can confirm."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let preview {
                Section("Ready to restore · metadata only") {
                    LabeledContent("Legacy recordings", value: "\(preview.legacyTracks)")
                    LabeledContent("V2 recordings", value: "\(preview.v2Recordings)")
                    LabeledContent("V2 playlists", value: "\(preview.v2Playlists)")
                    LabeledContent("Playlist entries",
                        value: "\(preview.legacyPlaylistEntries + preview.v2PlaylistEntries)")
                    LabeledContent("Radio favorites", value: "\(preview.radioFavorites)")
                    LabeledContent("Podcast-episode links",
                        value: "\(preview.podcastEpisodeMemberships)")
                    Button("Confirm restore into empty library") {
                        showConfirmation = true
                    }
                    .disabled(!canSelectFile || pendingArchive == nil)
                    .buttonStyle(.borderedProminent)
                }
            }

            Section {
                Label("Your existing library will never be erased",
                    systemImage: "lock.shield")
                Text(
                    "This experimental feature does not create a full iPhone "
                        + "backup. Never uninstall Trop or delete the only copy "
                        + "of your music to make restore available. Keep a copy "
                        + "of your archive in a safe location."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Restore Library")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await checkEligibility() }
        .sheet(isPresented: $isPicking) {
            TropLibraryV2DocumentPicker(
                onPick: { url in
                    isPicking = false
                    Task { await prepareRestore(from: url) }
                },
                onCancel: { isPicking = false }
            )
        }
        .confirmationDialog(
            "Restore metadata into this empty library?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore metadata", role: .destructive) {
                Task { await restoreConfirmed() }
            }
            Button("Cancel", role: .cancel) {
                clearSelection()
            }
        } message: {
            Text(
                "Only the empty local library will receive metadata. "
                    + "This is not an audio-file backup, and private "
                    + "source connections may need to be linked again. "
                    + "Trop will check the destination again before any write."
            )
        }
        .alert("Library restoration", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @MainActor
    private func checkEligibility() async {
        guard !isRestoring, !isReading, !completed else { return }
        isChecking = true
        isEligible = false
        clearSelection()
        defer { isChecking = false }
        guard DatabaseService.shared.usesPersistentStore else { return }
        do {
            try await DatabaseService.shared.read { db in
                try TropLibraryCombinedRestorePreflight.requireEmpty(db)
            }
            isEligible = true
        } catch {
            // Report no table names, IDs, audio titles or sqlite details.
            isEligible = false
        }
    }

    @MainActor
    private func prepareRestore(from url: URL) async {
        guard canSelectFile else { return }
        isReading = true
        clearSelection()
        defer { isReading = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let maximum = TropLibraryCombinedBackupArchive.maximumBytes
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if let size, size > maximum {
                    throw TropLibraryCombinedBackupError.oversized
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: maximum + 1) ?? Data()
                guard data.count <= maximum else {
                    throw TropLibraryCombinedBackupError.oversized
                }
                let counts = try TropLibraryCombinedBackupService.preview(data)
                return (data, counts)
            }.value

            // Early UX preflight only. The production restore repeats it
            // inside its atomic write transaction and must refuse occupancy.
            try await DatabaseService.shared.read { db in
                try TropLibraryCombinedRestorePreflight.requireEmpty(db)
            }
            pendingArchive = result.0
            preview = result.1
        } catch {
            clearSelection()
            showMessage(
                "The archive could not be prepared or this library is no longer "
                    + "empty. Nothing was restored."
            )
            await checkEligibility()
        }
    }

    @MainActor
    private func restoreConfirmed() async {
        guard canSelectFile, let archive = pendingArchive,
              preview != nil else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            // Revalidates source and destination inside ONE GRDB write.
            // No hidden synchronization, database reset, or merge.
            let result = try await TropLibraryCombinedRestoreStore
                .restoreIntoEmptyLibrary(archive)
            completed = true
            isEligible = false
            clearSelection()
            NotificationCenter.default.post(
                name: Notification.Name("trop.libraryChanged"), object: nil
            )
            await LikeStore.shared.refresh()
            showMessage(
                "Metadata restore succeeded: \(result.v2Recordings) V2 songs, "
                    + "\(result.v2Playlists) V2 playlists, "
                    + "\(result.v2PlaylistEntries) V2 playlist entries. "
                    + "Downloaded audio and private provider connections "
                    + "were not restored."
            )
            Log.libraryView.info("COMBINED_RESTORE metadata transaction committed")
        } catch TropLibraryCombinedRestorePreflight.Blocker.occupiedDestination {
            clearSelection()
            isEligible = false
            showMessage(
                "Restore blocked: this library already contains data. "
                    + "Nothing was overwritten."
            )
        } catch {
            clearSelection()
            showMessage(
                "Metadata restoration was rejected or did not finish. "
                    + "The transaction was rolled back; keep the backup file."
            )
            Log.libraryView.warning("COMBINED_RESTORE transaction failed")
        }
    }

    @MainActor
    private func clearSelection() {
        pendingArchive = nil
        preview = nil
        showConfirmation = false
    }

    @MainActor
    private func showMessage(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
