import SwiftUI
import UniformTypeIdentifiers

/// Export, local persistence and verification for combined legacy+V2 metadata.
/// Actual restore has a separate empty-only screen with transactional guards.
struct TropLibraryCombinedBackupView: View {
    @State private var document: TropLibraryV2RecoveryDocument?
    @State private var showExporter = false
    @State private var showPicker = false
    @State private var isPreparing = false
    @State private var isSavingLocal = false
    @State private var isExportingLocal = false
    @State private var isVerifying = false
    @State private var isRehearsing = false
    @State private var preview: TropLibraryCombinedBackupService.Preview?
    @State private var statusMessage: String?
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var isBusy: Bool {
        isPreparing || isSavingLocal || isExportingLocal
            || isVerifying || isRehearsing
    }

    var body: some View {
        List {
            Section {
                Label("Experimental combined metadata copy", systemImage: "externaldrive")
                    .font(.headline)
                Text(
                    "One archive of the old Trop library and Library V2. "
                        + "It saves metadata only, not audio files, downloads, "
                        + "account credentials or listening history."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Create a copy") {
                Button {
                    Task { await prepareExport() }
                } label: {
                    Label(
                        isPreparing ? "Preparing archive…" : "Export combined metadata to Files",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isBusy)

                Button {
                    Task { await saveLocalCopy() }
                } label: {
                    Label(
                        isSavingLocal ? "Saving to iPhone…" : "Save a copy on this iPhone",
                        systemImage: "iphone.gen3"
                    )
                }
                .disabled(isBusy)

                Button {
                    Task { await exportLatestLocal() }
                } label: {
                    Label(
                        isExportingLocal ? "Preparing saved copy…" : "Export latest local copy to Files",
                        systemImage: "square.and.arrow.up.on.square"
                    )
                }
                .disabled(isBusy)

                Text(
                    "Save locally first, then export a verified copy whenever you want. "
                        + "Local copies stay in Trop's Documents folder, whether or not "
                        + "the Files app shows its Thrum folder. Keep a second copy outside "
                        + "Trop before changing or removing the app."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(
                    "You choose the destination in Files. Keep Trop installed and "
                        + "do not rely on this experimental file as your only backup: "
                        + "restore is allowed only into a completely empty library."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Check a saved copy") {
                Button {
                    Task { await inspectLocal() }
                } label: {
                    Label(
                        isVerifying ? "Verifying…" : "Verify latest file in Trop app folder",
                        systemImage: "checkmark.shield"
                    )
                }
                .disabled(isBusy)

                Button {
                    showPicker = true
                } label: {
                    Label("Verify another file from Files", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(isBusy)

                Text(
                    "Local verification reads the app's Documents folder directly, "
                        + "even if On My iPhone does not display Thrum. You can also "
                        + "verify other locations with the Files picker."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Recovery rehearsal · safe test") {
                Button {
                    Task { await rehearseLocalArchive() }
                } label: {
                    Label(
                        isRehearsing
                            ? "Testing in memory…"
                            : "Test latest saved copy in isolated memory",
                        systemImage: "checkmark.shield"
                    )
                }
                .disabled(isBusy)
                Text(
                    "This creates a temporary SQLite database in memory, "
                        + "rebuilds the saved metadata, and checks the results. "
                        + "It NEVER restores into your actual library. "
                        + "Keep your original installation and backup."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Restore to a fresh library") {
                NavigationLink {
                    TropLibraryCombinedRestoreView()
                } label: {
                    Label("Restore metadata from Files", systemImage: "arrow.uturn.backward.circle")
                }
                .disabled(isBusy)
                Text(
                    "Only a completely empty installation is eligible. "
                        + "Existing songs, playlists, downloads and history "
                        + "block restoration. Never erase your current library "
                        + "just to enable this experimental action."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let preview {
                Section("Verified archive contents") {
                    LabeledContent("Legacy recordings", value: "\(preview.legacyTracks)")
                    LabeledContent("Legacy playlists", value: "\(preview.legacyPlaylists)")
                    LabeledContent(
                        "Legacy playlist entries", value: "\(preview.legacyPlaylistEntries)"
                    )
                    LabeledContent("V2 recordings", value: "\(preview.v2Recordings)")
                    LabeledContent("V2 playlists", value: "\(preview.v2Playlists)")
                    LabeledContent(
                        "V2 playlist entries", value: "\(preview.v2PlaylistEntries)"
                    )
                    LabeledContent("Radio favorites", value: "\(preview.radioFavorites)")
                    LabeledContent(
                        "Podcast-episode links", value: "\(preview.podcastEpisodeMemberships)"
                    )
                    LabeledContent(
                        "Private source aliases omitted",
                        value: "\(preview.omittedPrivateAliases)"
                    )
                    if preview.omittedPrivateAliases > 0 {
                        Text(
                            "Some tracks will need their audio provider linked "
                                + "again if recovery becomes available."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Label("Not encrypted or fully restorable", systemImage: "lock.open")
                Text(
                    "SHA-256 detects accidental corruption, not who created "
                        + "the file. Store it privately. Verification never "
                        + "modifies either library."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage).font(.footnote)
                }
            }
        }
        .navigationTitle("Combined Snapshot")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .alert("Combined snapshot check", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .fileExporter(
            isPresented: $showExporter,
            document: document,
            contentType: .json,
            defaultFilename: TropLibraryCombinedLocalSnapshotFinder.filenamePrefix
        ) { result in
            switch result {
            case .success:
                statusMessage = "File exported. It has not been restored or used to migrate data."
                Log.libraryView.info("COMBINED_EXPORT finished")
            case .failure:
                statusMessage = "The file could not be exported. No library data changed."
                Log.libraryView.warning("COMBINED_EXPORT failed")
            }
        }
        .sheet(isPresented: $showPicker) {
            TropLibraryV2DocumentPicker(
                onPick: { url in
                    showPicker = false
                    Task { await inspectExternal(url) }
                },
                onCancel: { showPicker = false }
            )
        }
    }

    @MainActor
    private func prepareExport() async {
        guard !isBusy else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let data = try await TropLibraryCombinedBackupService.export()
            let checked = try TropLibraryCombinedBackupService.preview(data)
            preview = checked
            document = TropLibraryV2RecoveryDocument(data: data)
            statusMessage = nil
            showExporter = true
            Log.libraryView.info("COMBINED_EXPORT prepared and validated")
        } catch {
            document = nil
            preview = nil
            showMessage("Could not create a combined copy. No library data changed.")
            Log.libraryView.warning("COMBINED_EXPORT preparation failed")
        }
    }

    /// Save a new, validated metadata copy in the app's Documents folder.
    /// Existing local and external files are never replaced.
    @MainActor
    private func saveLocalCopy() async {
        guard !isBusy else { return }
        isSavingLocal = true
        defer { isSavingLocal = false }
        do {
            let data = try await TropLibraryCombinedBackupService.export()
            let checked = try TropLibraryCombinedBackupService.preview(data)
            let saved = try await Task.detached(priority: .userInitiated) {
                try TropLibraryCombinedLocalSnapshotStore.saveVerified(data)
            }.value
            preview = checked
            showMessage(
                "Verified metadata copy saved on this iPhone: "
                    + saved.lastPathComponent
                    + ". Use Export latest local copy to Files to keep another "
                    + "copy outside Trop. No library data changed."
            )
            Log.libraryView.info("COMBINED_LOCAL_SAVE verified")
        } catch {
            showMessage(
                "Could not save the local metadata copy. Existing files and "
                    + "library data were not replaced."
            )
            Log.libraryView.warning("COMBINED_LOCAL_SAVE failed")
        }
    }

    /// Export the latest saved local archive without re-reading the library.
    /// This continues working when Files does not surface the Thrum folder.
    @MainActor
    private func exportLatestLocal() async {
        guard !isBusy else { return }
        isExportingLocal = true
        defer { isExportingLocal = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let file = try TropLibraryCombinedLocalSnapshotFinder.latest()
                let checked = try TropLibraryCombinedBackupService.preview(file.bytes)
                return (file.bytes, checked)
            }.value
            document = TropLibraryV2RecoveryDocument(data: result.0)
            preview = result.1
            statusMessage = nil
            showExporter = true
            Log.libraryView.info("COMBINED_LOCAL_EXPORT prepared")
        } catch TropLibraryCombinedLocalSnapshotFinder.LookupError.noSnapshot {
            showMessage(
                "No combined metadata copy is saved in Trop's Documents folder. "
                    + "Use Save a copy on this iPhone first."
            )
        } catch {
            showMessage(
                "The saved local copy could not be verified for export. "
                    + "Nothing was deleted or restored."
            )
            Log.libraryView.warning("COMBINED_LOCAL_EXPORT failed")
        }
    }

    @MainActor
    private func inspectLocal() async {
        guard !isBusy else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let file = try TropLibraryCombinedLocalSnapshotFinder.latest()
                return try TropLibraryCombinedBackupService.preview(file.bytes)
            }.value
            verified(result)
            Log.libraryView.info("COMBINED_LOCAL_VERIFY success")
        } catch TropLibraryCombinedLocalSnapshotFinder.LookupError.noSnapshot {
            failed("No combined file was found in Trop's internal Documents folder.")
        } catch {
            failed("The combined file could not be verified. Nothing was restored.")
        }
    }

    @MainActor
    private func rehearseLocalArchive() async {
        guard !isBusy else { return }
        isRehearsing = true
        defer { isRehearsing = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let found = try TropLibraryCombinedLocalSnapshotFinder.latest()
                return try TropLibraryCombinedRestoreRehearsal.rehearse(found.bytes)
            }.value
            showMessage(
                "Isolated recovery rehearsal PASSED. Rebuilt "
                    + "\(result.v2Recordings) V2 recordings, "
                    + "\(result.v2Playlists) V2 playlists and "
                    + "\(result.v2PlaylistEntries) playlist entries. "
                    + "The actual library was not modified."
            )
            Log.libraryView.info("COMBINED_REHEARSAL succeeded in isolated memory")
        } catch TropLibraryCombinedLocalSnapshotFinder.LookupError.noSnapshot {
            showMessage(
                "No combined metadata file was found in Trop's internal Documents folder. "
                    + "Nothing changed in your library."
            )
        } catch let issue as TropLibraryCombinedRestoreRehearsal.Failure {
            showMessage(
                "Isolated recovery rehearsal stopped at "
                    + issue.diagnosticCode
                    + ". Your actual library was not modified. "
                    + "Keep your backup and report this diagnostic code."
            )
            Log.libraryView.warning(
                "COMBINED_REHEARSAL stopped: \(issue.diagnosticCode)"
            )
        } catch {
            showMessage(
                "Isolated recovery rehearsal stopped at FILE_READ. "
                    + "Your actual library was not modified."
            )
            Log.libraryView.warning("COMBINED_REHEARSAL stopped at FILE_READ")
        }
    }

    @MainActor
    private func inspectExternal(_ url: URL) async {
        guard !isBusy else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if let size, size > TropLibraryCombinedBackupArchive.maximumBytes {
                    throw TropLibraryCombinedBackupError.oversized
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let bytes = try handle.read(
                    upToCount: TropLibraryCombinedBackupArchive.maximumBytes + 1
                ) ?? Data()
                guard bytes.count <= TropLibraryCombinedBackupArchive.maximumBytes else {
                    throw TropLibraryCombinedBackupError.oversized
                }
                return try TropLibraryCombinedBackupService.preview(bytes)
            }.value
            verified(result)
            Log.libraryView.info("COMBINED_FILE_VERIFY success")
        } catch {
            failed("Could not verify this combined file. Nothing was restored.")
        }
    }

    @MainActor
    private func verified(_ summary: TropLibraryCombinedBackupService.Preview) {
        preview = summary
        showMessage(
            "Archive integrity and format verified: "
                + "\(summary.legacyTracks) legacy recordings, "
                + "\(summary.v2Recordings) V2 recordings, "
                + "\(summary.legacyPlaylistEntries + summary.v2PlaylistEntries) "
                + "playlist entries. No data was restored."
        )
    }

    @MainActor
    private func failed(_ message: String) {
        preview = nil
        showMessage(message)
        Log.libraryView.warning("COMBINED_VERIFY validation or file access failed")
    }

    @MainActor
    private func showMessage(_ message: String) {
        statusMessage = message
        alertMessage = message
        showAlert = true
    }
}
