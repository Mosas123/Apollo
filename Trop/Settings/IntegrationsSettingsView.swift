//
//  IntegrationsSettingsView.swift
//  Trop
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
                SettingsNavigationRow("PencariMusic", icon: "dot.radiowaves.left.and.right") {
                    PencariMusicSettingsView()
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
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
