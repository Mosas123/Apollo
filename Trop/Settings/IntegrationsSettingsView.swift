//
//  IntegrationsSettingsView.swift
//  Trop
//

import SwiftUI

struct IntegrationsSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                SettingsNavigationRow("Music Addons", icon: "puzzlepiece.extension") {
                    MusicAddonsSettingsView()
                }
                SettingsNavigationRow("Qobuz", icon: "waveform") {
                    QobuzSettingsView()
                }
                SettingsNavigationRow("Last.fm", icon: "music.note") {
                    LastFMSettingsView()
                }
                SettingsNavigationRow("Canvas", icon: "film") {
                    CanvasSettingsView()
                }
                SettingsNavigationRow("SponsorBlock", icon: "forward.end") {
                    SponsorBlockSettingsView()
                }
            } footer: {
                Text("Connect external services to enhance your experience.")
            }

            Section {
                Toggle("Apple Music artwork (experimental)", isOn: $settings.experimentalAppleArtwork)
            } header: {
                Text("Experimental")
            } footer: {
                Text("Uses Apple Music's catalogue and artist photos for high-resolution covers. If anything misbehaves, turn it off to return to YouTube-only artwork.")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
