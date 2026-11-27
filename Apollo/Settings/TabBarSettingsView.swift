import SwiftUI

/// Mini-menu for choosing which tabs appear in the tab bar.
struct TabBarSettingsView: View {
    @Environment(\.settingsStore) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                SettingsToggleRow(
                    "Show Radio tab",
                    icon: "dot.radiowaves.left.and.right",
                    isOn: $settings.showRadioTab
                )
                SettingsToggleRow(
                    "Show Explore tab",
                    icon: "flame",
                    isOn: $settings.showExploreTab
                )
            } header: {
                Text("Visible Tabs")
            } footer: {
                Text("Home, Library and Search are always shown.")
            }
        }
        .navigationTitle("Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
    }
}
