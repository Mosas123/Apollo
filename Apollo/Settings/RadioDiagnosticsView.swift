import SwiftUI

struct RadioDiagnosticsView: View {
    @State private var metrics: [RadioStationMetric] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section { ProgressView() }
            } else if metrics.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No stations yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Start a radio from a song or artist to see its metrics here.")
                    )
                }
            } else {
                Section {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(metric.seedTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(metric.style)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(metric.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            HStack(spacing: 12) {
                                Label("\(metric.selectedCount)/\(metric.candidateCount)", systemImage: "music.note.list")
                                Label("\(metric.uniqueArtists) artists", systemImage: "person.2")
                                Label("\(metric.latencyMS) ms", systemImage: "timer")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                            if !metric.sourceMix.isEmpty {
                                Text(metric.sourceMix
                                    .sorted { $0.value > $1.value }
                                    .map { "\($0.key) \($0.value)" }
                                    .joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if metric.maxArtistRepeat > 1 {
                                Text("Max repeat: \(metric.maxArtistRepeat) tracks from one artist")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Recent stations")
                } footer: {
                    Text("Local diagnostics only. Nothing leaves the device.")
                }

                Section {
                    Button("Clear diagnostics", role: .destructive) {
                        Task {
                            await RadioMetricsStore.shared.clear()
                            metrics = []
                        }
                    }
                }
            }
        }
        .navigationTitle("Radio diagnostics")
        .task {
            metrics = await RadioMetricsStore.shared.recent()
            isLoading = false
        }
    }
}
