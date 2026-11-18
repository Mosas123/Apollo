//
//  PlayerSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct PlayerSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsNavigationRow("Equalizer", icon: "slider.vertical.3") {
                    EqualizerView()
                }
            } header: {
                Text("Equalizer")
            } footer: {
                Text("Adjust the sound with presets or a custom curve.")
            }

            Section {
                SettingsPickerRow("Audio Quality", icon: "waveform", selection: $settings.audioQuality)
                SettingsPickerRow("Preferred Source", icon: "opticaldisc", selection: $settings.musicQualityMode)
                SettingsToggleRow("Prefer Dolby Atmos when available", icon: "spatial.audio", isOn: $settings.preferAtmos)
                SettingsToggleRow("Upgrade to best quality during playback", icon: "arrow.up.circle", isOn: $settings.upgradeDuringPlayback)
                SettingsToggleRow("Audio Normalization", icon: "speaker.wave.2", isOn: $settings.audioNormalization)
                SettingsToggleRow("Gapless Playback", icon: "arrow.right.arrow.left", isOn: $settings.gaplessPlayback)
            } header: {
                Text("Audio")
            } footer: {
                Text("Preferred Source picks which stream to use. CD keeps 16-bit / 44.1 kHz FLAC and skips hi-res (much smaller files); Lossless takes the best FLAC available. \"Prefer Dolby Atmos\" plays the addon's E-AC3 5.1 copy when it exists; iOS downmixes it to stereo, so it is a taste choice, not an upgrade over FLAC. If \"Upgrade to best quality during playback\" is on, the app may switch to a better source mid-song; you'll hear a very short fade (about 0.3s) while the new stream loads, then playback continues at the same position.")
            }

            Section {
                SettingsToggleRow("Autoplay Similar", icon: "infinity", isOn: $settings.autoplaySimilar)
                SettingsToggleRow("Persist Queue", icon: "clock.arrow.circlepath", isOn: $settings.persistQueue)
            } header: {
                Text("Queue")
            } footer: {
                Text("Persist Queue restores your queue, shuffle, and repeat state when the app relaunches.")
            }

            Section {
                SettingsToggleRow("Swipe Artwork to Skip", icon: "hand.draw", isOn: $settings.artworkSwipeNavigation)
            } header: {
                Text("Gestures")
            } footer: {
                Text("Swipe left or right on the artwork in the full player to play the next or previous song.")
            }
        }
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
