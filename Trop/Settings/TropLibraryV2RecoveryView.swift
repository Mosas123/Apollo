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

            Section("Verify") {
                Button {
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
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer {
                    if access { url.stopAccessingSecurityScopedResource() }
                }
                let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if let byteCount, byteCount > TropLibraryV2RecoveryArchive.maximumBytes {
                    throw TropLibraryV2RecoveryError.oversized
                }
                let data = try Data(contentsOf: url)
                preview = try TropLibraryV2RecoveryStore.preview(data)
                feedback = "Archive integrity verified; nothing was restored."
                errorMessage = nil
            } catch {
                preview = nil
                errorMessage = "Archive verification failed. Nothing was changed."
            }
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
