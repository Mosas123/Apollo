//
//  PlayerSettingsView.swift
//  Apollo
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct PlayerSettingsView: View {
    @Environment(\.settingsStore) private var settings

    private var audioQualitySummary: String {
        settings.wifiStreamingTier.displayName
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsToggleRow(
                    "ApoloEngine Beta (Music)",
                    icon: "waveform.path",
                    isOn: $settings.apoloBetaEnabled
                )
                SettingsToggleRow(
                    "ApoloEngine Beta (Podcasts)",
                    icon: "mic",
                    isOn: $settings.apoloPodcastsBetaEnabled
                )
                SettingsToggleRow(
                    "ApoloEngine Beta (Live Radio)",
                    icon: "dot.radiowaves.left.and.right",
                    isOn: $settings.apoloRadioBetaEnabled
                )
            } header: {
                Text("Experimental Playback")
            } footer: {
                Text(LocalizedStringKey(
                    "Music, Podcasts and Live Radio have independent beta switches. Changes apply to the next selection. Podcasts keep their saved position and use " +
                        "finite audio playback; live radio uses Apolo's continuous transport. MPVKit remains the fallback if Apolo cannot load a source."
                ))
            }

            Section {
                SettingsNavigationRow(
                    "Dolby Atmos",
                    icon: "spatial.audio",
                    detail: settings.atmosMode.displayName
                ) {
                    AtmosSettingsView()
                }
                SettingsNavigationRow(
                    "Audio Quality",
                    icon: "waveform",
                    detail: audioQualitySummary
                ) {
                    AudioQualitySettingsView()
                }
                SettingsNavigationRow("Equalizer", icon: "slider.vertical.3") {
                    EqualizerView()
                }
                SettingsToggleRow(
                    "Sound Check",
                    icon: "checkmark.circle",
                    isOn: $settings.audioNormalization
                )
                SettingsNavigationRow(
                    "Song Transitions",
                    icon: "arrow.right.arrow.left",
                    detail: settings.gaplessPlayback ? "Gapless" : "Off"
                ) {
                    SongTransitionsSettingsView()
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("Dolby Atmos and Lossless Audio need a music add-on. Automatic Atmos uses it only with capable outputs.")
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
