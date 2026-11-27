//
//  SettingsView.swift
//  Apollo
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        List {
            Section {
                SettingsNavigationRow("Appearance", icon: "paintpalette.fill") {
                    AppearanceSettingsView()
                }
                SettingsNavigationRow("Tab Bar", icon: "rectangle.bottomthird.inset.filled") {
                    TabBarSettingsView()
                }
                SettingsNavigationRow("Player", icon: "play.circle.fill") {
                    PlayerSettingsView()
                }
                SettingsNavigationRow("Storage", icon: "internaldrive.fill") {
                    StorageSettingsView()
                }
                SettingsNavigationRow("Downloads", icon: "arrow.down.circle.fill") {
                    DownloadSettingsView()
                }
            }

            Section {
                SettingsNavigationRow("Content", icon: "globe") {
                    ContentSettingsView()
                }
                SettingsNavigationRow("Lyrics", icon: "text.quote") {
                    LyricsSettingsView()
                }
                SettingsNavigationRow("Integrations", icon: "puzzlepiece.extension.fill") {
                    IntegrationsSettingsView()
                }
            }

            Section {
                SettingsNavigationRow("History", icon: "clock.arrow.circlepath") {
                    HistoryScreenView()
                }
                SettingsNavigationRow("Radio diagnostics", icon: "waveform.path.ecg") {
                    RadioDiagnosticsView()
                }
            }

            Section {
                SettingsNavigationRow("About", icon: "info.circle.fill") {
                    AboutSettingsView()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
