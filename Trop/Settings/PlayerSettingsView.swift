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
                SettingsPickerRow(
                    "Preferred Source",
                    icon: "opticaldisc",
                    options: settings.hasMusicAddons ? [.off, .auto, .cd, .lossless] : [.off, .auto],
                    isEnabled: true,
                    selection: Binding(
                        get: {
                            let mode = settings.musicQualityMode
                            if mode == .high { return .auto }
                            if !settings.hasMusicAddons, mode == .cd || mode == .lossless {
                                return .auto
                            }
                            return mode
                        },
                        set: { settings.musicQualityMode = $0 }
                    )
                )
                if settings.hasMusicAddons, settings.musicQualityMode == .auto {
                    SettingsToggleRow("Prefer lossless over CD", icon: "waveform.path.ecg", isOn: $settings.preferLossless)
                    SettingsToggleRow("Prefer Dolby Atmos when available", icon: "spatial.audio", isOn: $settings.preferAtmos)
                }
                SettingsToggleRow("Upgrade to best quality during playback", icon: "arrow.up.circle", isOn: $settings.upgradeDuringPlayback)
                SettingsToggleRow("Audio Normalization", icon: "speaker.wave.2", isOn: $settings.audioNormalization)
                SettingsToggleRow("Gapless Playback", icon: "arrow.right.arrow.left", isOn: $settings.gaplessPlayback)
            } header: {
                Text("Audio")
            } footer: {
                Text(settings.hasMusicAddons
                     ? "Auto picks the best FLAC copy the add-ons offer; CD forces 16-bit / 44.1 kHz and Lossless prefers the highest FLAC. The toggles only refine Auto: prefer lossless when both CD and hi-res exist, or prefer Dolby Atmos (E-AC3 5.1, downmixed to stereo by iOS). If \"Upgrade to best quality during playback\" is on, the app may switch mid-song with a short fade."
                     : "Off and Auto work with YouTube alone. CD, Lossless and Dolby Atmos need an installed music add-on, because the add-on is the search engine for those qualities. Add one in Settings → Integrations → Music Addons to unlock them.")
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
