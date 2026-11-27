import Foundation
import SwiftUI

struct RadioDiagnosticsView: View {
    @State private var metrics: [RadioStationMetric] = []
    @State private var weights: [String: RadioWeights] = [:]
    @State private var isLoading = true

    private let styles = ["similar", "variety", "deepCuts"]

    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView()
                }
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
                        metricRow(metric)
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

            Section {
                ForEach(styles, id: \.self) { style in
                    if let weight = weights[style] {
                        weightRow(style: style, weight: weight)
                    }
                }
                Button("Reset learned weights", role: .destructive) {
                    Task {
                        await RadioLearningStore.shared.clear()
                        await loadWeights()
                    }
                }
            } header: {
                Text("Learning-to-rank")
            } footer: {
                Text("Weights move with real completions and skips. Embeddings are computed on-device.")
            }
        }
        .navigationTitle("Radio diagnostics")
        .task {
            metrics = await RadioMetricsStore.shared.recent()
            await loadWeights()
            isLoading = false
        }
    }

    private func metricRow(_ metric: RadioStationMetric) -> some View {
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

    private func weightRow(style: String, weight: RadioWeights) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(style)
                .font(.subheadline.weight(.semibold))
            Text("affinity \(format(weight.affinity)) · profile \(format(weight.profile)) · embedding \(format(weight.embedding))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("artist \(format(weight.seedTop)) · album \(format(weight.album)) · related \(format(weight.related))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func loadWeights() async {
        var loaded: [String: RadioWeights] = [:]
        for style in styles {
            loaded[style] = await RadioLearningStore.shared.weights(for: style)
        }
        weights = loaded
    }
}
