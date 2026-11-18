//
//  PencariMusicSettingsView.swift
//  Trop
//

import SwiftUI

/// PencariMusic is the bundled lossless source: it can point at the public
/// addon or at a self-hosted server (for example http://127.0.0.1:8088).
struct PencariMusicSettingsView: View {
    @Environment(\.settingsStore) private var settings
    @State private var status: String?
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Addon URL", text: $settings.pencariMusicBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(isTesting ? "Testing…" : "Test connection") {
                    test()
                }
                .disabled(isTesting)
                Button("Restore default server") {
                    settings.pencariMusicBaseURL = PencariMusicClient.defaultBase
                    status = "Restored the public PencariMusic server."
                }
            } header: {
                Text("Server")
            } footer: {
                Text("Paste the addon base or its manifest URL, e.g. http://127.0.0.1:8088/music/manifest.json. Lossless search, playback and downloads use this server.")
            }

            if let status {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("PencariMusic")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    private func test() {
        isTesting = true
        status = nil
        Task {
            let base = settings.pencariMusicBaseURL
            guard let client = PencariMusicClient(base: base) else {
                status = "That doesn't look like a valid URL."
                isTesting = false
                return
            }
            do {
                let tracks = try await client.searchTracks(query: "bad bunny titi me pregunto", limit: 3)
                if let first = tracks.first, let info = try? await client.resolveStreamInfoFast(for: first.id.rawValue) {
                    status = "Connected · \(client.baseURL.absoluteString) · \(tracks.count) result(s) · \(info.qualityLabel) \(info.sizeBytes.map { "\($0 / 1_048_576) MB" } ?? "")"
                } else {
                    status = "Connected to \(client.baseURL.absoluteString), but no playable results."
                }
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}
