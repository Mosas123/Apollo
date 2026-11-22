import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let tropLibraryBackup = UTType(
        exportedAs: "org.apoloengine.tropbackup",
        conformingTo: .json
    )
}

/// All file access is user-initiated through iOS Files. Installed File
/// Provider extensions may offer Google Drive, OneDrive or other locations;
/// no provider credentials or CloudKit entitlement are needed to export.
struct TropLibraryBackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tropLibraryBackup] }
    static var writableContentTypes: [UTType] { [.tropLibraryBackup] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw TropLibraryBackupError.invalidPayload
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct TropLibraryBackupView: View {
    @State private var exportDocument: TropLibraryBackupFileDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isPreparing = false
    @State private var summary: TropLibraryBackupSummary?
    @State private var lastMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("Your library, in a portable file", systemImage: "externaldrive")
                    .font(.headline)
                Text("Export saved music metadata and playlist order without needing a YouTube login or iCloud Drive. Choose a destination in Files, including supported third-party storage providers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Create backup") {
                Button {
                    Task { await prepareExport() }
                } label: {
                    if isPreparing {
                        Label("Preparing backup…", systemImage: "hourglass")
                    } else {
                        Label("Export .tropbackup", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparing)
                Text("Includes saved songs, playlists and their entries, saved albums, followed artists and podcasts, and saved episodes. No downloaded audio, local paths, streaming links, passwords, cookies or YouTube mutation tokens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("This file is NOT encrypted. Store it in a private, trusted location.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Inspect backup") {
                Button {
                    isImporting = true
                } label: {
                    Label("Verify backup from Files", systemImage: "checkmark.shield")
                }
                Text("Read-only verification. This version does not restore or replace any data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let summary {
                Section("Verified archive") {
                    LabeledContent("Saved songs", value: "\(summary.likedSongs)")
                    LabeledContent("Tracks with metadata", value: "\(summary.tracks)")
                    LabeledContent("Saved albums", value: "\(summary.albums)")
                    LabeledContent("Followed artists", value: "\(summary.artists)")
                    LabeledContent("Saved playlists", value: "\(summary.playlists)")
                    LabeledContent("Playlist entries", value: "\(summary.playlistEntries)")
                    LabeledContent("Followed podcasts", value: "\(summary.podcasts)")
                    LabeledContent("Saved episodes", value: "\(summary.episodes)")
                    LabeledContent("Unresolved playlist entries", value: "\(summary.unresolvedEntries)")
                    Label("SHA-256 integrity verified", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
            }

            if let lastMessage {
                Section {
                    Text(lastMessage).foregroundStyle(.secondary)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Library Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .tropLibraryBackup,
            defaultFilename: "Trop-Library"
        ) { result in
            switch result {
            case .success:
                lastMessage = "Export completed. Keep the backup somewhere safe."
                errorMessage = nil
            case .failure:
                errorMessage = "Could not save the backup to that destination."
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.tropLibraryBackup, .json]
        ) { result in
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if let size, size > TropLibraryBackupArchive.maximumBytes {
                    throw TropLibraryBackupError.tooLarge
                }
                let data = try Data(contentsOf: url)
                summary = try TropLibraryBackupArchive.inspect(data)
                errorMessage = nil
                lastMessage = "Archive verified. No data was imported or changed."
            } catch {
                summary = nil
                errorMessage = "Could not verify this backup. Nothing was changed."
            }
        }
    }

    @MainActor
    private func prepareExport() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            let data = try await TropLibraryBackupService.export()
            // Verify the exact bytes before offering a destination in Files.
            summary = try TropLibraryBackupArchive.inspect(data)
            exportDocument = TropLibraryBackupFileDocument(data: data)
            errorMessage = nil
            lastMessage = nil
            isExporting = true
        } catch {
            exportDocument = nil
            summary = nil
            errorMessage = "Could not prepare a safe backup. No database changes were made."
        }
    }
}
