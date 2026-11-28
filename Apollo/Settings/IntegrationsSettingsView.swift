//
//  IntegrationsSettingsView.swift
//  Apollo
//

import SwiftUI

struct IntegrationsSettingsView: View {
    var body: some View {
        List {
            Section {
                SettingsNavigationRow("Music Addons", icon: "puzzlepiece.extension") {
                    MusicAddonsSettingsView()
                }
                SettingsNavigationRow("Qobuz", icon: "waveform") {
                    QobuzSettingsView()
                }
                SettingsNavigationRow("SponsorBlock", icon: "forward.end") {
                    SponsorBlockSettingsView()
                }
                SettingsNavigationRow("Import playlist", icon: "square.and.arrow.down") {
                    PlaylistImportView()
                }
            } footer: {
                Text("Connect external services and bring your library from other platforms.")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
