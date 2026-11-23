import SwiftUI

/// Foreground, opt-in scanning for music already saved to Library V2.
/// This does not search or prelink dynamic Home/Explore/Search cards.
struct TropLibraryV2BatchMatchView: View {
    @State private var processed = 0
    @State private var total = 0
    @State private var isRunning = false
    @State private var showingRestartConfirmation = false
    @State private var message: String?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Saved recordings examined", systemImage: "music.note.list")
                    Spacer()
                    Text("\(processed) / \(total)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if isRunning {
                    HStack {
                        ProgressView()
                        Text("Matching saved songs…")
                            .foregroundStyle(.secondary)
                    }
                    Button("Stop after current song", role: .cancel) {
                        scanTask?.cancel()
                    }
                } else {
                    Button {
                        beginScan()
                    } label: {
                        Label("Scan Next 8 Saved Songs", systemImage: "magnifyingglass")
                    }
                    .disabled(total == 0 || processed >= total)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Trop Match")
            } footer: {
                Text(
                    "Only songs saved to your own Library V2 are scanned. "
                        + "Progress is saved after each attempt and can resume "
                        + "after reopening Thrum. Each tap scans at most eight "
                        + "recordings, one at a time. Missing providers and "
                        + "uncertain editions never delete or replace a song."
                )
            }

            Section {
                Button("Restart Scan from Beginning") {
                    showingRestartConfirmation = true
                }
                .disabled(isRunning || processed == 0)
            } footer: {
                Text(
                    "Restart only clears the matching scan cursor, not your "
                        + "songs, playlists, likes, downloads or verified audio links."
                )
            }
        }
        .navigationTitle("Match Saved Music")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refresh() }
        .onDisappear { scanTask?.cancel() }
        .confirmationDialog(
            "Recheck your saved recordings?",
            isPresented: $showingRestartConfirmation
        ) {
            Button("Restart Matching Scan") {
                TropLibraryV2Prelinker.shared.restartManualScan()
                message = "Matching progress reset. Your saved music was not changed."
                Task { await refresh() }
            }
        } message: {
            Text(
                "Previously confirmed audio sources remain linked. "
                    + "Only the manual scanning position starts over."
            )
        }
    }

    @MainActor
    private func refresh() async {
        do {
            let state = try await TropLibraryV2Prelinker.shared.batchProgress()
            processed = state.processed
            total = state.total
        } catch {
            message = "Could not read your saved Library V2 recordings."
        }
    }

    @MainActor
    private func beginScan() {
        guard !isRunning else { return }
        isRunning = true
        message = nil
        scanTask = Task {
            do {
                let state = try await TropLibraryV2Prelinker.shared.scanNextBatch()
                processed = state.processed
                total = state.total
                message = state.hasMore
                    ? "Batch finished. Continue when you choose."
                    : "All currently saved recordings have been examined."
            } catch is CancellationError {
                message = "Stopped. Completed work is saved; resume whenever you like."
            } catch {
                message = "Matching paused. Your saved music is safe; try again later."
            }
            await refresh()
            isRunning = false
            scanTask = nil
        }
    }
}
