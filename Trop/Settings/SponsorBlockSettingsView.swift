//
//  SponsorBlockSettingsView.swift
//  Trop
//
//  Created by 686udjie on 23/10/2026.
//

import SwiftUI

struct SponsorBlockSettingsView: View {
    @State private var enabled = SponsorBlock.isEnabled

    var body: some View {
        List {
            Section {
                SettingsToggleRow("Skip Segments", icon: "forward.end", isOn: $enabled)
            } header: {
                Text("Segments")
            } footer: {
                Text("Skips non-music parts of music videos, like talking intros, skits and long outros.")
            }
        }
        .navigationTitle("SponsorBlock")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .onChange(of: enabled) {
            SponsorBlock.save(enabled: enabled)
        }
    }
}
