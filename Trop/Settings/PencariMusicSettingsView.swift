import SwiftUI

/// Enables the PencariMusic addon (Eclipse/BitChord music surface).
///
/// The base is a tokenized addon URL like
/// `https://stream.pencarimovie.com/<token>`. Search hits `/music/search`
/// (FLAC rows) and playback resolves `/music/stream/<short-code>`.
struct PencariMusicSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var base = ""
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                TextField("Addon URL", text: $base)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Save") { save() }
                    .disabled(base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !settings.pencariMusicBaseURL.isEmpty {
                    Button("Remove", role: .destructive) { remove() }
                }
            } header: {
                Text("PencariMusic addon")
            } footer: {
                Text(
                    "Paste the addon base (the part up to the token) or its "
                    + "/music/manifest.json URL. Search returns FLAC when the index "
                    + "has it. Playback may briefly queue while their origin resolves "
                    + "the file from Telegram; the app retries automatically."
                )
            }

            Section {
                LabeledContent("Status", value: settings.pencariMusicBaseURL.isEmpty ? "Not configured" : "Configured")
            }

            if let status {
                Section {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("PencariMusic")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { base = settings.pencariMusicBaseURL }
    }

    private func save() {
        guard let url = PencariMusicClient.normalize(base) else {
            status = "That URL isn't valid. Use the addon base or its /music/manifest.json."
            return
        }
        settings.pencariMusicBaseURL = url.absoluteString
        base = url.absoluteString
        status = "Saved. Search again to see PencariMusic tracks."
    }

    private func remove() {
        settings.pencariMusicBaseURL = ""
        base = ""
        status = "Removed."
    }
}
