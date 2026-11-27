//
//  LyricsSettingsView.swift
//  Apollo
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct LyricsSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsToggleRow("Lyrics", icon: "music.quote", isOn: $settings.lyricsEnabled)
            } footer: {
                Text("When off, lyrics are not fetched or shown in the player.")
            }

            Section {
                ForEach(LyricsProviderRegistry.all, id: \.id) { provider in
                    SettingsToggleRow(
                        provider.name,
                        icon: "music.note",
                        isOn: Binding(
                            get: { !settings.disabledLyricsProviders.contains(provider.id) },
                            set: { enabled in
                                var disabled = settings.disabledLyricsProviders
                                if enabled {
                                    disabled.remove(provider.id)
                                } else {
                                    disabled.insert(provider.id)
                                }
                                settings.disabledLyricsProviders = disabled
                            }
                        )
                    )
                }
            } header: {
                Text("Providers")
            } footer: {
                Text("Disabled providers are skipped when fetching lyrics.")
            }

            Section {
                NavigationLink {
                    LyricsProviderOrderView()
                } label: {
                    Label("Provider Order", systemImage: "list.number")
                }
            }
        }
        .navigationTitle("Lyrics")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
