//
//  SettingsView.swift
//  Trop
//
//  Created by 686udjie on 16/07/2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Bindable private var accountState = AccountSheetState.shared
    @AppStorage("trop.library.v2.previewEnabled")
    private var libraryV2PreviewEnabled = false
    @AppStorage("trop.match.youtubeAudioEnabled")
    private var youtubeAudioProviderEnabled = false

    var body: some View {
        List {
            if !libraryV2PreviewEnabled {
                accountSection
            }

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
                SettingsNavigationRow("Library Migration", icon: "arrow.triangle.2.circlepath") {
                    TropLibraryMigrationPreviewView()
                }
                SettingsNavigationRow("Downloads", icon: "arrow.down.circle.fill") {
                    DownloadSettingsView()
                }
            }

            Section("Experimental library") {
                Toggle("Use Trop Library V2", isOn: $libraryV2PreviewEnabled)
                Toggle(
                    "YouTube as optional audio source",
                    isOn: $youtubeAudioProviderEnabled
                )
                Text(
                    "When enabled, saved YouTube track IDs may supply audio. "
                        + "This never restores a YouTube Music library, account "
                        + "login or mandatory music catalogue."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                // The combined copy is needed BEFORE migration, including
                // when the user has never enabled the V2 preview.
                SettingsNavigationRow(
                    "Combined Metadata Snapshot", icon: "externaldrive.badge.plus"
                ) {
                    TropLibraryCombinedBackupView()
                }
                if libraryV2PreviewEnabled {
                    SettingsNavigationRow("Experimental V2 Snapshot", icon: "externaldrive") {
                        TropLibraryV2RecoveryView()
                    }
                }
                Text(
                    "V2 starts empty and saves locally without YouTube. "
                        + "Your old library remains untouched. The player heart "
                        + "and catalogue pages are not migrated yet."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        .loginSheet(state: accountState)
        .task {
            // Library V2 needs no YouTube login, polling or account badge.
            guard !libraryV2PreviewEnabled else { return }
            await accountState.restoreSession()
            await accountState.fetchAccountInfo()
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                AccountButtonView(
                    isLoggedIn: accountState.isLoggedIn,
                    accountImageUrl: accountState.accountImageUrl,
                    onTap: {}
                )
                .scaleEffect(1.7)
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountState.isLoggedIn ? accountState.accountName : String(localized: "Guest"))
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if accountState.isLoggedIn {
                    Button("Logout", action: accountState.signOut)
                        .buttonStyle(.bordered)
                        .tint(settings.accentColor)
                } else {
                    Button("Login") { accountState.isLoginSheetPresented = true }
                        .buttonStyle(.borderedProminent)
                        .tint(settings.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
