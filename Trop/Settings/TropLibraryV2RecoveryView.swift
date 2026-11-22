import SwiftUI
import UniformTypeIdentifiers

/// Read-only V2 metadata archive. A real import action is deliberately NOT
/// exposed until the legacy and V2 recovery flows pass on-device QA.
struct TropLibraryV2RecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw TropLibraryV2RecoveryError.invalidData
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TropLibraryV2RecoveryView: View {
    @State private var document: TropLibraryV2RecoveryDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var isPreparing = false
    @State private var isInspectingLocal = false
    @State private var localVerificationAlert = false
    @State private var localVerificationMessage = ""
    @State private var preview: TropLibraryV2RecoveryStore.Preview?
    @State private var feedback: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("Experimental V2 snapshot", systemImage: "externaldrive")
                    .font(.headline)
                Text(
                    "A manual metadata-only copy of your Trop Library V2. "
                        + "It does not include your old library, audio files, "
                        + "downloads or account credentials."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Section("Export") {
                Button {
                    Task { await prepareExport() }
                } label: {
                    Label(
                        isPreparing ? "Preparing snapshot…" : "Export V2 snapshot to Files",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .disabled(isPreparing)
                Text(
                    "This is not yet a full rescue backup. Keep Trop installed "
                        + "and preserve your original data while restore is in testing."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Verify saved file without picker") {
                Button {
                    Log.libraryView.info("V2_LOCAL_VERIFY button pressed")
                    feedback = "Checking the most recent V2 snapshot in Thrum…"
                    errorMessage = nil
                    Task { await inspectLocalSnapshot() }
                } label: {
                    Label(
                        isInspectingLocal ? "Checking saved file…" : "Verify snapshot in Trop app folder",
                        systemImage: "checkmark.shield"
                    )
                }
                .disabled(isInspectingLocal)
                Text(
                    "This checks the newest V2 snapshot immediately and shows a result. "
                        + "It does not open another screen. The file must be in "
                        + "Files → On My iPhone → Thrum."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Verify from another location") {
                Button {
                    Log.libraryView.info("V2_FILE_IMPORTER open requested")
                    showImporter = true
                } label: {
                    Label("Inspect V2 snapshot from Files", systemImage: "checkmark.shield")
                }
                Text(
                    "Verification checks the archive and displays counts only. "
                        + "No library data is imported, replaced or deleted."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let preview {
                Section("Snapshot contents") {
                    LabeledContent("Recordings", value: "\(preview.recordings)")
                    LabeledContent("Playlists", value: "\(preview.playlists)")
                    LabeledContent("Playlist entries", value: "\(preview.entries)")
                    LabeledContent("Saved radio stations", value: "\(preview.radioFavorites)")
                    LabeledContent(
                        "Private addon aliases withheld",
                        value: "\(preview.omittedPrivateAliases)"
                    )
                    if preview.omittedPrivateAliases > 0 {
                        Text(
                            "Some saved songs will need to be reconnected to "
                                + "their add-on after future restoration."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Label("The file is not encrypted", systemImage: "lock.open")
                Text(
                    "Save it in a private location. SHA-256 detects accidental "
                        + "corruption but does not verify who created the file."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let feedback {
                Section {
                    Text(feedback).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("V2 Snapshot")
        .alert("V2 snapshot verification", isPresented: $localVerificationAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(localVerificationMessage)
        }
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .fileExporter(
            isPresented: $showExporter,
            document: document,
            contentType: .json,
            defaultFilename: "Trop-V2-Experimental-Snapshot"
        ) { result in
            switch result {
            case .success:
                feedback = "V2 snapshot exported. This is not yet a restorable full backup."
                errorMessage = nil
            case .failure:
                errorMessage = "Unable to export the snapshot. No data was changed."
            }
        }
        .sheet(isPresented: $showImporter) {
            TropLibraryV2DocumentPicker(
                onPick: { url in
                    inspectExternalSnapshot(url)
                    showImporter = false
                },
                onCancel: {
                    showImporter = false
                }
            )
        }
    }

    @MainActor
    private func inspectExternalSnapshot(_ url: URL) {
        Log.libraryView.info("V2_FILE_IMPORTER UIKit selection handoff")
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if let byteCount, byteCount > TropLibraryV2RecoveryArchive.maximumBytes {
                throw TropLibraryV2RecoveryError.oversized
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(
                upToCount: TropLibraryV2RecoveryArchive.maximumBytes + 1
            ) ?? Data()
            guard data.count <= TropLibraryV2RecoveryArchive.maximumBytes else {
                throw TropLibraryV2RecoveryError.oversized
            }
            preview = try TropLibraryV2RecoveryStore.preview(data)
            Log.libraryView.info("V2_FILE_IMPORTER UIKit archive verified")
            feedback = "Archive integrity verified; nothing was restored."
            errorMessage = nil
            localVerificationMessage = "Archive integrity verified. " +
                "The file was read, not restored."
            localVerificationAlert = true
        } catch TropLibraryV2RecoveryError.oversized {
            preview = nil
            errorMessage = "This file is too large for a V2 snapshot. Nothing was changed."
            localVerificationMessage = errorMessage ?? "Verification failed"
            localVerificationAlert = true
        } catch TropLibraryV2RecoveryError.checksumMismatch {
            preview = nil
            errorMessage = "Snapshot checksum mismatch. Nothing was changed."
            localVerificationMessage = errorMessage ?? "Verification failed"
            localVerificationAlert = true
        } catch {
            preview = nil
            errorMessage = "This file is not a valid Trop V2 snapshot. Nothing was changed."
            localVerificationMessage = errorMessage ?? "Verification failed"
            localVerificationAlert = true
            Log.libraryView.warning("V2_FILE_IMPORTER validation or file access failed")
        }
    }

    @MainActor
    private func inspectLocalSnapshot() async {
        guard !isInspectingLocal else { return }
        isInspectingLocal = true
        defer { isInspectingLocal = false }
        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try TropLibraryV2LocalSnapshotFinder.latest()
            }.value
            preview = try TropLibraryV2RecoveryStore.preview(found.bytes)
            let message = "Archive integrity verified from Thrum. "
                + "\(preview?.recordings ?? 0) recordings, "
                + "\(preview?.playlists ?? 0) playlists, "
                + "\(preview?.entries ?? 0) playlist entries, "
                + "\(preview?.radioFavorites ?? 0) radio favorites. "
                + "Nothing was restored."
            Log.libraryView.info("V2_LOCAL_VERIFY completed successfully")
            feedback = message
            errorMessage = nil
            localVerificationMessage = message
            localVerificationAlert = true
        } catch TropLibraryV2LocalSnapshotFinder.LookupError.noSnapshot {
            preview = nil
            errorMessage = "No exported V2 snapshot was found in the app folder. "
                + "Save it under On My iPhone → Thrum and try again."
            Log.libraryView.warning("V2_LOCAL_VERIFY no matching snapshot")
            localVerificationMessage = errorMessage ?? "No snapshot found"
            localVerificationAlert = true
        } catch TropLibraryV2RecoveryError.checksumMismatch {
            preview = nil
            errorMessage = "The saved snapshot checksum does not match. Nothing was changed."
            Log.libraryView.warning("V2_LOCAL_VERIFY checksum mismatch")
            localVerificationMessage = errorMessage ?? "Verification failed"
            localVerificationAlert = true
        } catch {
            preview = nil
            errorMessage = "Could not verify the saved snapshot. Nothing was changed."
            Log.libraryView.warning("V2_LOCAL_VERIFY failed")
            localVerificationMessage = errorMessage ?? "Verification failed"
            localVerificationAlert = true
        }
    }

    @MainActor
    private func prepareExport() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let bytes = try await TropLibraryV2RecoveryStore.export()
            preview = try TropLibraryV2RecoveryStore.preview(bytes)
            document = TropLibraryV2RecoveryDocument(data: bytes)
            errorMessage = nil
            feedback = nil
            showExporter = true
        } catch {
            document = nil
            preview = nil
            errorMessage = "Could not create a V2 snapshot. Your library was not modified."
        }
    }
}
