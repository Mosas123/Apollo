//
//  ContentSettingsView.swift
//  Apollo
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct ContentSettingsView: View {
    @Environment(\.settingsStore) private var settings

    private static let countries = ["US", "GB", "CA", "AU", "FR", "DE", "ES", "IT", "PT", "JP", "KR", "MX", "BR", "IN"]

    @State private var revealKey = false
    @State private var showCustomModel = false
    @State private var keyTest: KeyTest = .idle

    private enum KeyTest: Equatable {
        case idle
        case testing
        case ok
        case failed(String)
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsToggleRow("Hide Explicit Content", icon: "eye.slash", isOn: $settings.hideExplicit)
            } header: {
                Text("Content Filtering")
            }

            Section {
                SettingsToggleRow("Show Quick Picks", icon: "sparkles", isOn: $settings.showQuickPicks)
                Stepper(value: $settings.topListsLength, in: 4...20, step: 2) {
                    HStack(spacing: 0) {
                        Label("Top Lists Length", systemImage: "list.number")
                        Text(": \(settings.topListsLength)")
                    }
                }
            } header: {
                Text("Home Feed")
            }

            Section {
                Picker("Country", selection: $settings.contentCountry) {
                    ForEach(Self.countries, id: \.self) { code in
                        Text(countryName(for: code)).tag(code)
                    }
                }
            } header: {
                Text("Region")
            } footer: {
                Text("Controls the region used for YouTube Music requests.")
            }

            Section {
                Picker("AI Provider", selection: $settings.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(LocalizedStringKey(provider.title)).tag(provider.rawValue)
                    }
                }
                .onChange(of: settings.aiProvider) { _, _ in
                    settings.aiModel = ""
                    showCustomModel = false
                    keyTest = .idle
                }

                if settings.aiProvider != AIProvider.off.rawValue {
                    HStack {
                        Group {
                            if revealKey {
                                TextField("API Key", text: $settings.aiKey)
                            } else {
                                SecureField("API Key", text: $settings.aiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        Text("Model")
                        Spacer()
                        Menu {
                            Button(AppStrings.format("Default (%@)", provider.defaultModel)) {
                                settings.aiModel = ""
                                showCustomModel = false
                            }
                            ForEach(modelOptions.filter { $0 != provider.defaultModel }, id: \.self) { model in
                                Button(model) {
                                    settings.aiModel = model
                                    showCustomModel = false
                                }
                            }
                            Button("Custom…") {
                                showCustomModel = true
                                if modelOptions.contains(settings.aiModel) {
                                    settings.aiModel = ""
                                }
                            }
                        } label: {
                            Text(currentModelLabel)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if showCustomModel || isCustomStored {
                        TextField("Custom model", text: $settings.aiModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Button {
                            testConnection()
                        } label: {
                            Label("Test key", systemImage: "checkmark.seal")
                        }
                        .disabled(settings.aiKey.isEmpty || keyTest == .testing)

                        Spacer()

                        switch keyTest {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                        case .ok:
                            Label("Works", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        case .failed(let message):
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(2)
                        }
                    }
                }
            } header: {
                Text("For You (AI)")
            } footer: {
                Text("Optional. An AI model suggests songs from your history; each suggestion is verified on YouTube Music before it appears. Uses your own API key.")
            }

            Section {
                TextField("API Key", text: $settings.podcastIndexKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Secret", text: $settings.podcastIndexSecret)
            } header: {
                Text("Podcasts (Podcast Index)")
            } footer: {
                Text("Optional. Create a free key at podcastindex.org to enrich podcast art and metadata. Without it, the app falls back to iTunes podcast search.")
            }

            Section {
                SettingsToggleRow("Track Search History", icon: "magnifyingglass", isOn: $settings.trackSearchHistory)
                SettingsToggleRow("Track Play History", icon: "clock.arrow.circlepath", isOn: $settings.trackPlayHistory)
            } header: {
                Text("Privacy")
            } footer: {
                Text("When off, searches and playback are not recorded locally.")
            }

        }
        .navigationTitle("Content")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }

    private func countryName(for code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private var provider: AIProvider {
        AIProvider(rawValue: settings.aiProvider) ?? .off
    }

    private var modelOptions: [String] {
        switch provider {
        case .off: return []
        case .gemini: return ["gemini-3.6-flash", "gemini-3.5-pro"]
        case .deepSeek: return ["deepseek-flash", "deepseek-v4-pro"]
        case .openRouter: return ["qwen/qwen3.7-flash", "openai/gpt-5-mini"]
        }
    }

    private var currentModelLabel: String {
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? provider.defaultModel : model
    }

    private var isCustomStored: Bool {
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return !model.isEmpty && !modelOptions.contains(model)
    }

    @MainActor
    private func testConnection() {
        guard let client = AIProviderClient.configured() else {
            keyTest = .failed("Enter a key first")
            return
        }
        keyTest = .testing
        Task {
            do {
                try await client.verify()
                keyTest = .ok
            } catch {
                keyTest = .failed(error.localizedDescription)
            }
        }
    }
}
