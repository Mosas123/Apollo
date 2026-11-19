import Foundation
import SwiftUI

/// Beta entry point for the online DJ session. It loads and analyses the whole
/// pool, asks the AI for the set plan and cleans up when the session ends. The
/// mixing engine is the next step.
struct DJSessionView: View {
    @State private var controller = DJSessionController.shared
    @State private var instruction = ""
    @State private var showSizeWarning = false

    private var pool: [SongItem] { NowPlaying.shared.queueSongs }
    private var estimate: Int64 { DJSessionController.estimatedBytes(for: pool) }

    var body: some View {
        List {
            Section {
                Text("\(pool.count) tracks in the current queue")
                    .foregroundStyle(.secondary)
                Button("Prepare DJ set") {
                    if estimate > 600 * 1_048_576 {
                        showSizeWarning = true
                    } else {
                        controller.startPreparation(
                            pool: pool,
                            instruction: instruction.isEmpty ? nil : instruction
                        )
                    }
                }
                .disabled(controller.isBusy || pool.count < 4)
                if let _ = controller.plan {
                    Button("End session and delete cache", role: .destructive) {
                        Task { await controller.finish() }
                    }
                }
                if controller.isBusy {
                    Button("Cancel preparation", role: .cancel) {
                        Task { await controller.cancelPreparation() }
                    }
                }
                if pool.count < 4 {
                    Text("Queue at least 4 songs first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Estimated download: ~\(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) (CD estimate; Hi-Res sets can be much larger)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Pool")
            } footer: {
                Text("The whole queue is downloaded to a temporary cache, analysed and sent (metadata only) to your AI provider.")
            }

            Section {
                TextField("Optional instruction (e.g. “smooth sunset set”)", text: $instruction, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Direction")
            }

            Section {
                stateView
            } header: {
                Text("Preparation")
            }

            if let plan = controller.plan {
                Section {
                    ForEach(Array(plan.slots.enumerated()), id: \.offset) { index, slot in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(slot.track.title)")
                                .font(.subheadline.weight(.semibold))
                            Text(slot.track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let transition = slot.transition {
                                Text("Enter: \(transition.kind.rawValue) · \(String(format: "%.1f", transition.seconds))s\(effectsLabel(transition.effects))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    if let notes = plan.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI plan")
                } footer: {
                    Text("The engine that mixes this plan is coming next. Nothing is playing yet.")
                }
            }

            if !controller.skipped.isEmpty {
                Section {
                    ForEach(controller.skipped, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Skipped tracks")
                }
            }
        }
        .navigationTitle("DJ Session (Beta)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Large DJ cache", isPresented: $showSizeWarning) {
            Button("Cancel", role: .cancel) {}
            Button("Download anyway") {
                controller.startPreparation(
                    pool: pool,
                    instruction: instruction.isEmpty ? nil : instruction
                )
            }
        } message: {
            Text("This set will download about \(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) of audio. Use Wi-Fi if possible.")
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch controller.state {
        case .idle:
            Text("Idle")
                .foregroundStyle(.secondary)
        case .preparing(let done, let total, let current):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Downloading \(done)/\(total): \(current)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .analyzing(let current):
            HStack(spacing: 8) {
                ProgressView()
                Text("Analysing \(current)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .planning:
            HStack(spacing: 8) {
                ProgressView()
                Text("Asking the AI for the set plan…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            VStack(alignment: .leading, spacing: 4) {
                Text("Ready · \(controller.tracks.count) tracks")
                    .font(.subheadline.weight(.semibold))
                Text(ByteCountFormatter.string(fromByteCount: controller.totalBytes, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func effectsLabel(_ effects: [DJEffect]) -> String {
        guard !effects.isEmpty else { return "" }
        return " · " + effects.map(\.name).joined(separator: ", ")
    }
}
