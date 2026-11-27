import SwiftUI

// MARK: - Dolby Atmos

struct AtmosSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                ForEach(AtmosMode.allCases) { mode in
                    Button {
                        settings.atmosMode = mode
                    } label: {
                        HStack {
                            Text(mode.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.atmosMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(settings.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(LocalizedStringKey(
                    "Play supported songs in Dolby Atmos and other Dolby Audio formats.\n\n" +
                        "Automatic plays Atmos only when connected to capable outputs like AirPods, AirPods Pro, AirPods Max (with spatial audio on), " +
                        "supported Beats headphones, Bluetooth, AirPlay or an AV receiver. On the iPhone speaker Thrum keeps the FLAC/CD copy."
                ))
            }
        }
        .navigationTitle("Dolby Atmos")
    }
}

// MARK: - Audio Quality

struct AudioQualitySettingsView: View {
    @Environment(\.settingsStore) private var settings

    private var cellularOptions: [StreamingTier] {
        settings.losslessEnabled
            ? [.highEfficiency, .highQuality, .lossless, .hiRes]
            : [.highEfficiency, .highQuality]
    }

    private var wifiOptions: [StreamingTier] {
        settings.losslessEnabled ? [.highQuality, .lossless, .hiRes] : [.highQuality]
    }

    private var sizeFooter: String {
        "A three minute song will be approximately:\n" +
            "– 1.5 MB with High Efficiency\n" +
            "– 6 MB with High Quality at 256 kbps\n" +
            "– 36 MB with Lossless at 24-bit/48 kHz\n" +
            "– 145 MB with Hi-Res Lossless at 24-bit/192 kHz\n\n" +
            "Support varies and depends on song availability, network conditions, and connected speaker or headphone capability."
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                Toggle("Lossless Audio", isOn: $settings.losslessEnabled)
                    .tint(settings.accentColor)
            } footer: {
                Text("Lossless files preserve every detail of the original audio. Turning this on will consume significantly more data.")
            }

            Section {
                NavigationLink {
                    AboutLosslessAudioView()
                } label: {
                    Text("About Lossless Audio")
                }
            }

            Section {
                NavigationLink {
                    StreamingTierPickerView(
                        title: "Cellular Streaming",
                        options: cellularOptions,
                        selection: Binding(
                            get: { settings.cellularStreaming },
                            set: { settings.cellularStreaming = $0 }
                        ),
                        footer: "Lossless streaming will consume significantly more data.\n\n" + sizeFooter,
                        hiResTitle: "Confirm Hi-Res Lossless",
                        hiResMessage: "Hi-Res Lossless streaming will consume significantly more data than High Quality and is not recommended " +
                            "for cellular connections.\n\nAutoMix and Crossfade are not available while Hi-Res Lossless is turned on."
                    )
                } label: {
                    audioRow("Cellular Streaming", settings.cellularStreaming.displayName)
                }

                NavigationLink {
                    StreamingTierPickerView(
                        title: "5G & Wi-Fi Streaming",
                        options: wifiOptions,
                        selection: Binding(
                            get: { settings.wifiStreamingTier },
                            set: { settings.wifiStreamingTier = $0 }
                        ),
                        footer: "Lossless streaming will consume significantly more data.\n\n" + sizeFooter,
                        hiResTitle: "About Hi-Res Lossless",
                        hiResMessage: "Getting the most from Hi-Res Lossless requires an external digital-to-analog converter.\n\n" +
                            "AutoMix and Crossfade are not available while Hi-Res Lossless is turned on."
                    )
                } label: {
                    audioRow("5G & Wi-Fi Streaming", settings.wifiStreamingTier.displayName)
                }

                NavigationLink {
                    DownloadTierPickerView(
                        selection: Binding(
                            get: { settings.downloadTier },
                            set: { settings.downloadTier = $0 }
                        )
                    )
                } label: {
                    audioRow("Downloads", settings.downloadTier.displayName)
                }
            } footer: {
                Text("Content downloaded previously will continue to play in the originally downloaded resolution.")
            }
        }
        .navigationTitle("Audio Quality")
    }

    private func audioRow(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Streaming tier picker

struct StreamingTierPickerView: View {
    @Environment(\.settingsStore) private var settings

    let title: String
    let options: [StreamingTier]
    @Binding var selection: StreamingTier
    let footer: String
    let hiResTitle: String
    let hiResMessage: String

    @State private var pendingHiRes = false

    var body: some View {
        List {
            Section {
                ForEach(options) { tier in
                    Button {
                        if tier == .hiRes {
                            pendingHiRes = true
                        } else {
                            selection = tier
                        }
                    } label: {
                        tierLabel(tier)
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(LocalizedStringKey(footer))
            }
        }
        .navigationTitle(title)
        .alert(hiResTitle, isPresented: $pendingHiRes) {
            Button("Continue in Hi-Res Lossless") { selection = .hiRes }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(LocalizedStringKey(hiResMessage))
        }
    }

    private func tierLabel(_ tier: StreamingTier) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.displayName)
                    .foregroundStyle(.primary)
                Text(tier.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selection == tier {
                Image(systemName: "checkmark")
                    .foregroundStyle(settings.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Download tier picker

struct DownloadTierPickerView: View {
    @Environment(\.settingsStore) private var settings

    @Binding var selection: DownloadTier
    @State private var pendingHiRes = false

    var body: some View {
        List {
            Section {
                ForEach(DownloadTier.allCases) { tier in
                    Button {
                        if tier == .hiRes {
                            pendingHiRes = true
                        } else {
                            selection = tier
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tier.displayName)
                                    .foregroundStyle(.primary)
                                Text(tier.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == tier {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(settings.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(LocalizedStringKey(
                    "Lossless files will use significantly more space on your device.\n\n" +
                        "10 GB of space could store approximately:\n" +
                        "– 3000 songs at High Quality\n" +
                        "– 1000 songs with Lossless\n" +
                        "– 200 songs with Hi-Res Lossless"
                ))
            }
        }
        .navigationTitle("Downloads")
        .alert("Confirm Hi-Res Downloads", isPresented: $pendingHiRes) {
            Button("Turn on Hi-Res Downloads") { selection = .hiRes }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Hi-Res Lossless files are very large and will consume significantly more data and storage. " +
                "It's not recommended to download Hi-Res Lossless using a cellular connection.")
        }
    }
}

// MARK: - About

struct AboutLosslessAudioView: View {
    var body: some View {
        List {
            Section {
                Text("Lossless Audio keeps the full CD master (16-bit / 44.1 kHz) or a studio version when your add-on offers one.")
            }
            Section {
                Text("The iPhone's built-in output handles up to 24-bit / 48 kHz. Hi-Res files (24/96 or higher) need an external DAC, so Thrum only plays them when you choose Hi-Res Lossless.")
            }
            Section {
                Text("Dolby Atmos arrives as E-AC3 5.1 from the add-on. On the iPhone speaker it is downmixed; with AirPods, Bluetooth or an AV receiver it plays spatially.")
            }
        }
        .navigationTitle("About Lossless Audio")
    }
}

// MARK: - Song Transitions

struct SongTransitionsSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsToggleRow(
                    "Gapless Playback",
                    icon: "arrow.right.arrow.left",
                    isOn: $settings.gaplessPlayback
                )
                SettingsToggleRow(
                    "Upgrade During Playback",
                    icon: "arrow.up.circle",
                    isOn: $settings.upgradeDuringPlayback
                )
            } footer: {
                Text(LocalizedStringKey(
                    "Gapless removes the silence between tracks of the same album. Upgrade During Playback may switch to a better FLAC mid-song with a short fade."
                ))
            }
        }
        .navigationTitle("Song Transitions")
    }
}
