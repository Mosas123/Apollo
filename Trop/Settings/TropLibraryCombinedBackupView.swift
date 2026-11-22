import SwiftUI
import UniformTypeIdentifiers

/// Experimental read-only export/verification of BOTH legacy and V2 metadata.
/// No restore action is exposed until a full on-device recovery gate passes.
struct TropLibraryCombinedBackupView: View {
    @State private var document: TropLibraryV2RecoveryDocument?
    @State private var showExporter = false
    @State private var showPicker = false
    @State private var isPreparing = false
    @State private var isVerifying = false
    @State private var isRehearsing = false
    @State private var preview: TropLibraryCombinedBackupService.Preview?
    @State private var statusMessage: String?
    @State private var alertMessage = ""
    @State private var showAlert = false

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
                .disabled(isPreparing || isVerifying || isRehearsing)
                Text(
                    "You choose the destination in Files. Keep Trop installed and "
                        + "do not rely on this experimental file as your only backup: "
                        + "there is no user-facing restore yet."
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
                .disabled(isPreparing || isVerifying || isRehearsing)

                Button {
                    showPicker = true
                } label: {
                    Label("Verify another file from Files", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(isPreparing || isVerifying || isRehearsing)

                Text(
                    "Local verification reads On My iPhone → Thrum, without opening "
                        + "the Files picker. Other locations use the system document "
                        + "picker, which still needs on-device QA."
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
                .disabled(isPreparing || isVerifying || isRehearsing)
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
                .disabled(isPreparing || isVerifying || isRehearsing)
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
            defaultFilename: "Trop-Combined-Experimental-Snapshot"
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
        guard !isPreparing else { return }
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

    @MainActor
    private func inspectLocal() async {
        guard !isVerifying else { return }
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
            failed("No combined file was found in On My iPhone → Thrum.")
        } catch {
            failed("The combined file could not be verified. Nothing was restored.")
        }
    }

    @MainActor
    private func rehearseLocalArchive() async {
        guard !isRehearsing else { return }
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
                "No combined metadata file was found in On My iPhone → Thrum. "
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
        guard !isVerifying else { return }
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
