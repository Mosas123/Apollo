import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class DJMixViewModel {
    struct Item: Identifiable {
        let id = UUID()
        let track: DJSourceTrack
        var analysis: DJTrackAnalysis?
    }

    var items: [Item] = []
    var useAI = false
    var isWorking = false
    var status: String?
    var outputURL: URL?

    func add(urls: [URL]) async {
        for url in urls {
            let title = url.deletingPathExtension().lastPathComponent
            let track = DJSourceTrack(
                id: url.lastPathComponent,
                title: title,
                artist: "",
                fileURL: url,
                duration: 0
            )
            items.append(Item(track: track))
        }
        await analyzePending()
    }

    func analyzePending() async {
        isWorking = true
        defer { isWorking = false }
        for index in items.indices where items[index].analysis == nil {
            do {
                let analysis = try await DJAnalyzer.analyze(items[index].track)
                var track = items[index].track
                track = DJSourceTrack(
                    id: track.id, title: track.title, artist: track.artist,
                    fileURL: track.fileURL, duration: analysis.duration
                )
                items[index] = Item(track: track, analysis: analysis)
            } catch {
                status = "No se pudo analizar \(items[index].track.title)."
            }
        }
    }

    func renderMix() async {
        let analyzed = items.compactMap { item -> (DJSourceTrack, DJTrackAnalysis)? in
            guard let analysis = item.analysis else { return nil }
            return (item.track, analysis)
        }
        guard analyzed.count >= 2 else {
            status = "Agregá al menos dos pistas analizadas."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let aiPlan = useAI
            ? await DJAIPlanner.plan(tracks: analyzed, request: DJAIPlanner.Request())
            : nil
        let plan = aiPlan ?? DJMixPlanner.plan(tracks: analyzed)
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thrum Mix \(Int(Date().timeIntervalSince1970)).wav")
        do {
            _ = try await DJMixRenderer.render(plan: plan, to: output)
            outputURL = output
            status = "Mix listo."
        } catch {
            status = "Falló el render: \(error.localizedDescription)"
        }
    }
}

struct DJMixView: View {
    @State private var model = DJMixViewModel()
    @State private var importing = false

    var body: some View {
        List {
            Section {
                Button("Add audio files") { importing = true }
                Toggle("AI plan (uses your AI key)", isOn: $model.useAI)
                if model.isWorking { ProgressView() }
                ForEach(Array(model.items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading) {
                        Text(item.track.title).lineLimit(1)
                        if let analysis = item.analysis {
                            Text(String(format: "%.0f BPM · energía %.2f · %@",
                                        analysis.bpm ?? 0, analysis.energy,
                                        analysis.duration.formattedDuration))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Analizando…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Render mix") { Task { await model.renderMix() } }
                    .disabled(model.items.count < 2 || model.isWorking)
            } header: {
                Text("Offline DJ")
            } footer: {
                Text("Solo archivos locales. El mix se genera con AVFoundation y se guarda como WAV en Documentos.")
            }
            if let status = model.status {
                Section { Text(status).font(.footnote) }
            }
            if let output = model.outputURL {
                Section { ShareLink(item: output) { Text("Share mix") } }
            }
        }
        .navigationTitle("DJ Mix")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.audio, .wav, .mpeg4Audio, UTType(filenameExtension: "flac") ?? .audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await model.add(urls: urls) }
            }
        }
    }
}
