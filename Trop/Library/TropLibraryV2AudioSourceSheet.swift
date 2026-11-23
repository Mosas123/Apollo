import SwiftUI

/// A missing playback source starts a user-approved provider search. The
/// existing recording UUID, likes and playlist memberships are never replaced.
struct TropLibraryV2AudioSourceRequest: Identifiable {
    let recording: TropLibraryV2Store.RecordingSummary
    var id: String { recording.id }
}

struct TropLibraryV2AudioSourceSheet: View {
    let recording: TropLibraryV2Store.RecordingSummary

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [MusicCatalogTrack] = []
    @State private var isSearching = true
    @State private var isLinking = false
    @State private var message: String?

    private var requiresLossless: Bool {
        let quality = SettingsStore.shared.musicQualityMode
        return quality == .cd || quality == .lossless
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
                        "This recording keeps its Trop identity, likes and "
                            + "playlist entries. Only its audio source can be linked."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Matching audio sources") {
                    if isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching your available music providers…")
                        }
                    } else if candidates.isEmpty {
                        ContentUnavailableView(
                            "No verified audio match",
                            systemImage: "waveform.slash",
                            description: Text(
                                "No independent provider returned a matching "
                                    + "recording. Your song remains saved. "
                                    + "Try enabling a compatible music addon "
                                    + "or adjusting your audio quality."
                            )
                        )
                    } else {
                        ForEach(candidates, id: \.id) { track in
                            Button {
                                Task { await select(track) }
                            } label: {
                                HStack(spacing: 12) {
                                    AsyncImageView(
                                        url: track.artworkURL?.absoluteString
                                    )
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title)
                                            .foregroundStyle(.primary)
                                        Text(track.artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(track.id.source.rawValue.capitalized
                                             + " · " + durationLabel(track.durationSeconds))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "link")
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(isLinking)
                        }
                    }
                }

                Section {
                    Text(
                        "Choose only the correct recording. Similar metadata "
                            + "does not guarantee that a provider's stream will "
                            + "work. YouTube is not searched automatically. "
                            + "Private addon links are intentionally omitted "
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
            .navigationTitle("Find audio source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isLinking)
                }
            }
            .task(id: recording.id) {
                isSearching = true
                candidates = await TropLibraryV2AudioDiscovery.find(
                    for: recording, requiresLossless: requiresLossless
                )
                isSearching = false
            }
        }
    }

    @MainActor
    private func select(_ track: MusicCatalogTrack) async {
        guard !isLinking else { return }
        isLinking = true
        defer { isLinking = false }
        do {
            try await TropLibraryV2Store.linkConfirmedAudioSource(
                toRecordingID: recording.id,
                track: track,
                requiresLossless: requiresLossless
            )
            // The source now belongs to this same UUID. Playback still goes
            // through the existing ApoloEngine source resolver and controls.
            try await TropLibraryV2PlaybackRouter.playSaved(recording)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return "\(safe / 60):\(String(format: "%02d", safe % 60))"
    }
}
