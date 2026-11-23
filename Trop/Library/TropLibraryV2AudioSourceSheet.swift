import SwiftUI

/// Manual review is available from a saved song's menu; normal Play uses
/// Trop Match automatically and never presents this sheet.
struct TropLibraryV2AudioSourceRequest: Identifiable {
    let recording: TropLibraryV2Store.RecordingSummary
    var id: String { recording.id }
}

struct TropLibraryV2AudioSourceSheet: View {
    let recording: TropLibraryV2Store.RecordingSummary

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [MusicCatalogTrack] = []
    @State private var alternates: [MusicCatalogTrack] = []
    @State private var pendingAlternate: MusicCatalogTrack?
    @State private var isSearching = true
    @State private var isLinking = false
    @State private var message: String?

    private var requiresLossless: Bool {
        SettingsStore.shared.musicQualityMode.prefersLossless
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Saved in your library") {
                    LabeledContent("Song", value: recording.title)
                    if let artist = recording.artist {
                        LabeledContent("Artist", value: artist)
                    }
                    Text(
                        "The original song, favorites, and playlist entries "
                            + "stay intact. Choosing an alternate links audio "
                            + "without replacing the saved recording."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Verified matches") {
                    if isSearching {
                        HStack {
                            ProgressView()
                            Text("Checking enabled audio providers…")
                        }
                    } else if candidates.isEmpty {
                        Text(
                            "No exact match found at the selected quality. "
                                + "The original song stays in your library."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.id) { track in
                            Button {
                                Task { await select(track, approvedAlternate: false) }
                            } label: {
                                candidateRow(track, alternate: false)
                            }
                            .disabled(isLinking)
                        }
                    }
                }

                if !alternates.isEmpty {
                    Section("Review Alternatives") {
                        Text(
                            "These may be live, remix, different-length, or "
                                + "other editions. None are linked automatically."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        ForEach(alternates, id: \.id) { track in
                            Button {
                                pendingAlternate = track
                            } label: {
                                candidateRow(track, alternate: true)
                            }
                            .disabled(isLinking)
                        }
                    }
                }
                Section {
                    Text(
                        "Exact recording identity is checked before linking. "
                            + "An alternate needs your explicit approval. "
                            + "Provider stream availability is checked at play. "
                            + "YouTube is not used as a mandatory music "
                            + "catalogue, and private addon links are excluded "
                            + "from portable backups."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Review Audio Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLinking)
                }
            }
            .confirmationDialog(
                "Use a different recording?",
                isPresented: Binding(
                    get: { pendingAlternate != nil },
                    set: { if !$0 { pendingAlternate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Link this alternate version") {
                    if let track = pendingAlternate {
                        Task { await select(track, approvedAlternate: true) }
                    }
                }
                Button("Keep original without linking", role: .cancel) {}
            } message: {
                Text(
                    "This may not be the same studio recording. Your original "
                        + "song metadata and playlists will NOT be replaced."
                )
            }
            .task(id: recording.id) {
                isSearching = true
                let matches = await TropLibraryV2AudioDiscovery.inspect(
                    for: recording, requiresLossless: requiresLossless
                )
                guard !Task.isCancelled else { return }
                candidates = matches.exact
                alternates = matches.review
                isSearching = false
            }
        }
    }

    private func candidateRow(
        _ track: MusicCatalogTrack, alternate: Bool
    ) -> some View {
        HStack(spacing: 12) {
            AsyncImageView(url: track.artworkURL?.absoluteString)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).foregroundStyle(.primary)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    sourceName(for: track)
                        + " · " + durationLabel(track.durationSeconds)
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                if let album = track.albumTitle {
                    Text(album)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: alternate ? "chevron.right" : "link")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    @MainActor
    private func select(
        _ track: MusicCatalogTrack, approvedAlternate: Bool
    ) async {
        guard !isLinking else { return }
        isLinking = true
        defer { isLinking = false }
        do {
            try await TropLibraryV2Store.linkConfirmedAudioSource(
                toRecordingID: recording.id,
                track: track,
                requiresLossless: requiresLossless,
                userApprovedAlternate: approvedAlternate
            )
            try await TropLibraryV2PlaybackRouter.playSaved(recording)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Display a human-friendly enabled addon name, not its private
    /// installation key, manifest URL, or encoded source ID.
    private func sourceName(for track: MusicCatalogTrack) -> String {
        if track.id.source == .addon,
           let ref = AddonPlaybackID.decode(
               AddonPlaybackID.prefix + track.id.rawValue
           ),
           let installation = MusicAddonsStore.shared.installation(key: ref.k) {
            return installation.manifest.name
        }
        switch track.id.source {
        case .qobuz: return "Qobuz"
        case .audius: return "Audius"
        case .jiosaavn: return "JioSaavn"
        case .addon: return "Music Add-on"
        default: return track.id.source.rawValue.capitalized
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return "\(safe / 60):\(String(format: "%02d", safe % 60))"
    }
}
