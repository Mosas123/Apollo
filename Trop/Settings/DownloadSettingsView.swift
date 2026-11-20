//
//  DownloadSettingsView.swift
//  Trop
//

import SwiftUI

struct DownloadSettingsView: View {
    @Environment(\.settingsStore) private var settings
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var storageBytes: Int64 = 0
    @State private var trackCount = 0

    private var storageLabel: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                storageCard
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                SettingsPickerRow(
                    "Download Quality",
                    icon: "waveform",
                    options: [.auto, .high, .standard],
                    selection: Binding(
                        get: {
                            settings.downloadQuality == .lossless ? .auto : settings.downloadQuality
                        },
                        set: { settings.downloadQuality = $0 }
                    )
                )
                if settings.hasMusicAddons {
                    SettingsToggleRow("Lossless When Available", icon: "waveform.path", isOn: $settings.losslessDownloads)
                }
                SettingsToggleRow("Wi-Fi Only", icon: "wifi", isOn: $settings.wifiOnlyDownloads)
                SettingsToggleRow("Auto-Download on Like", icon: "heart.fill", isOn: $settings.autoDownloadOnLike)
                SettingsToggleRow("Auto-Download New Episodes", icon: "antenna.radiowaves.left.and.right", isOn: $settings.autoDownloadNewEpisodes)
            } header: {
                Text("Preferences")
            } footer: {
                Text(LocalizedStringKey(
                    "Auto-download saves liked songs for offline playback. Lossless tries your music add-ons first and saves FLAC; without add-ons it uses the " +
                    "quality above. Wi-Fi Only blocks downloads on cellular data."
                ))
            }
        }
        .navigationTitle("Download Settings")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .task { await refreshStats() }
        .onChange(of: downloadManager.persistedDownloadCount) { _, _ in
            Task { await refreshStats() }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(storageLabel)
                        .font(.title2.weight(.bold))
                    Text(AppStrings.offlineTracks(trackCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func refreshStats() async {
        storageBytes = await downloadManager.totalStorageBytes()
        trackCount = downloadManager.persistedDownloadCount
    }
}
