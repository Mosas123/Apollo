//
//  SponsorBlockSettingsView.swift
//  Apollo
//
//  Created by 686udjie on 23/10/2026.
//

import SwiftUI

struct SponsorBlockSettingsView: View {
    @State private var enabled = SponsorBlock.isEnabled
    @State private var skipIntro = SponsorBlock.skipsIntroAtStart

    var body: some View {
        List {
            Section {
                SettingsToggleRow("Skip Segments", icon: "forward.end", isOn: $enabled)
                SettingsToggleRow("Skip intro at start", icon: "play.circle", isOn: $skipIntro)
            } header: {
                Text("Segments")
            } footer: {
                Text("Skips non-music parts of music videos. \"Skip intro at start\" can start the song late if a segment boundary is inaccurate, so it is off by default.")
            }
        }
        .navigationTitle("SponsorBlock")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .onChange(of: enabled) {
            SponsorBlock.save(enabled: enabled)
        }
        .onChange(of: skipIntro) {
            SponsorBlock.saveSkipIntroAtStart(skipIntro)
        }
    }
}
