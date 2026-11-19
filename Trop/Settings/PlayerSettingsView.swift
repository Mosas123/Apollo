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
                    "ApoloEngine Beta (Music Only)",
                    icon: "waveform.path",
                    isOn: $settings.apoloBetaEnabled
                )
            } header: {
                Text("Experimental Playback")
            } footer: {
                Text("Apolo plays music on the next track. Video mode is disabled while the beta is enabled; mpv is used if a source fails. Ten-band EQ support is not yet migrated.")
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
                if addonCapabilities.atmos, settings.musicQualityMode != .off {
                    SettingsToggleRow("Dolby Atmos only (E-AC3 5.1)", icon: "spatial.audio", isOn: $settings.preferAtmos)
                }
                SettingsToggleRow("Upgrade to best quality during playback", icon: "arrow.up.circle", isOn: $settings.upgradeDuringPlayback)
                SettingsToggleRow("Audio Normalization", icon: "speaker.wave.2", isOn: $settings.audioNormalization)
                SettingsToggleRow("Gapless Playback", icon: "arrow.right.arrow.left", isOn: $settings.gaplessPlayback)
            } header: {
                Text("Audio")
            } footer: {
                Text(LocalizedStringKey(settings.hasMusicAddons
                     ? "Add-on Quality picks which copy to look for in your add-ons: Auto takes the best FLAC available and falls back to JioSaavn/AAC 320 then YouTube; CD forces 16-bit / 44.1 kHz; Best FLAC keeps FLAC only (no 320 fallback). \"Allow Hi-Res\" unlocks 24-bit copies; with it off they are neither downloaded nor played (the iPhone DAC tops out at 24/48 and hi-res needs an external DAC). Dolby Atmos (E-AC3 5.1) plays spatially on AirPods/AVR; the iPhone speaker downmixes it. It needs an installed add-on and a Dolby track. Audio Quality picks the lossy pool: with Auto or High it races YouTube, JioSaavn and add-on AAC 320 and keeps the best; Standard and Low stay on YouTube and only use JioSaavn/AAC if YouTube has no stream. If \"Upgrade to best quality during playback\" is on, the app may switch mid-song with a short fade."
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
