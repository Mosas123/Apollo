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

    var body: some View {
        List {
            accountSection

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
                SettingsNavigationRow("DJ Session (Beta)", icon: "waveform.path.ecg.rectangle") {
                    DJSessionView()
                }
                SettingsNavigationRow("Storage", icon: "internaldrive.fill") {
                    StorageSettingsView()
                }
                SettingsNavigationRow("Downloads", icon: "arrow.down.circle.fill") {
                    DownloadSettingsView()
                }
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
