//
//  PlayerSettingsView.swift
//  Trop
//
//  Created by 686udjie on 20/08/2026.
//

import SwiftUI

struct PlayerSettingsView: View {
    @Environment(\.settingsStore) private var settings

    private var addonCapabilities: AddonCapabilities {
        MusicAddonsStore.shared.availableAudioCapabilities
    }

    private var addonQualityOptions: [MusicQualityMode] {
        var options: [MusicQualityMode] = [.off, .auto]
        if addonCapabilities.hasLossless {
            options.append(.cd)
            options.append(.lossless)
        }
        return options
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
                Text("Music, Podcasts and Live Radio have independent beta switches. Changes apply to the next selection. Podcasts keep their saved position and use finite audio playback; live radio uses Apolo's continuous transport. MPVKit remains the fallback if Apolo cannot load a source.")
            }

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
                    "Add-on Quality",
                    icon: "opticaldisc",
                    options: addonQualityOptions,
                    isEnabled: true,
                    selection: Binding(
                        get: {
                            let mode = settings.musicQualityMode
                            if mode == .high { return .auto }
                            if !addonQualityOptions.contains(mode) { return .auto }
                            return mode
                        },
                        set: { settings.musicQualityMode = $0 }
                    )
                )
                if addonCapabilities.hiRes,
                   settings.musicQualityMode == .auto || settings.musicQualityMode == .lossless {
                    SettingsToggleRow("Allow Hi-Res (24-bit)", icon: "waveform.path.ecg", isOn: $settings.preferHiRes)
                }
                if settings.hasMusicAddons,
                   settings.musicQualityMode == .auto || settings.musicQualityMode == .lossless {
                    SettingsToggleRow("Prefer Dolby Atmos when available", icon: "spatial.audio", isOn: $settings.preferAtmos)
                }
                SettingsToggleRow("Upgrade to best quality during playback", icon: "arrow.up.circle", isOn: $settings.upgradeDuringPlayback)
                SettingsToggleRow("Audio Normalization", icon: "speaker.wave.2", isOn: $settings.audioNormalization)
                SettingsToggleRow("Gapless Playback", icon: "arrow.right.arrow.left", isOn: $settings.gaplessPlayback)
            } header: {
                Text("Audio")
            } footer: {
                Text(LocalizedStringKey(settings.hasMusicAddons
                     ? "Add-on Quality picks which copy to look for in your add-ons: Auto takes the best FLAC available and falls back to JioSaavn/AAC 320 then YouTube; CD forces 16-bit / 44.1 kHz; Best FLAC keeps FLAC only (no 320 fallback). \"Allow Hi-Res\" unlocks 24-bit copies; with it off they are neither downloaded nor played (the iPhone DAC tops out at 24/48 and hi-res needs an external DAC). \"Prefer Dolby Atmos\" plays the add-on's E-AC3 5.1 copy when it exists and falls back to FLAC/CD otherwise; it plays spatially on AirPods/AVR and the iPhone speaker downmixes it. Audio Quality picks the lossy pool: with Auto or High it races YouTube, JioSaavn and add-on AAC 320 and keeps the best; Standard and Low stay on YouTube and only use JioSaavn/AAC if YouTube has no stream. If \"Upgrade to best quality during playback\" is on, the app may switch mid-song with a short fade."
                     : "Off and Auto work with YouTube alone. CD, Best FLAC and Dolby Atmos need an installed music add-on, because the add-on is the search engine for those qualities. Add one in Settings → Integrations → Music Addons to unlock them."))
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
