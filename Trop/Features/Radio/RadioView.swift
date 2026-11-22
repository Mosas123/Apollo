import SwiftUI

/// Internet radio (Radio Browser). Sits in the tab bar in place of Explore,
/// matching the Apple Music layout: Home · Radio · Library · Search.
struct RadioView: View {
    @Environment(\.settingsStore) private var settings

    @State private var stations: [RadioStation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var query = ""
    @State private var selectedTag = "Top"
    @AppStorage("trop.library.v2.previewEnabled")
    private var libraryV2PreviewEnabled = false
    @State private var savedStations: [TropLibraryV2RadioStore.Favorite] = []
    @State private var radioFavoriteError: String?

    private let tags = [
        "Top", "Pop", "Rock", "Jazz", "Classical", "Electronic",
        "Hip-Hop", "Chillout", "Latin", "News"
    ]

    var body: some View {
        NavigationStack {
            List {
                if libraryV2PreviewEnabled {
                    Section("My Stations") {
                        if savedStations.isEmpty {
                            Text("Save a station using the heart button below.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(savedStations) { favorite in
                            savedStationRow(favorite)
                        }
                    }
                }
                Section {
                    tagChips
                }
                if let radioFavoriteError {
                    Text(radioFavoriteError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Try again") { Task { await load() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                } else if isLoading && stations.isEmpty {
                    Section {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } else if stations.isEmpty {
                    Section {
                        Text("No stations found.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(stations) { station in
                            stationRow(station)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Radio")
            .searchable(text: $query, prompt: "Search stations")
            .miniPlayerTracksScroll()
        }
        .task {
            if libraryV2PreviewEnabled { await loadSavedStations() }
        }
        .onChange(of: libraryV2PreviewEnabled) { _, enabled in
            Task {
                if enabled {
                    await loadSavedStations()
                } else {
                    savedStations = []
                }
            }
        }
        .task(id: loadKey) {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
    }

    private var loadKey: String {
        let term = query.trimmingCharacters(in: .whitespaces)
        return term.isEmpty ? "tag:\(selectedTag)" : "search:\(term)"
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    let isOn = selectedTag == tag && query.isEmpty
                    Button {
                        selectedTag = tag
                        query = ""
                    } label: {
                        Text(tag)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isOn ? settings.accentColor.opacity(0.22) : Color(uiColor: .tertiarySystemFill),
                                in: Capsule()
                            )
                            .foregroundStyle(isOn ? settings.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func stationRow(_ station: RadioStation) -> some View {
        HStack(spacing: 8) {
            Button {
                play(station)
            } label: {
                HStack(spacing: 12) {
                    AsyncImageView(url: station.iconURL)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(station.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(settings.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if libraryV2PreviewEnabled {
                let isSaved = savedStations.contains {
                    $0.stationUUID == station.stationuuid.lowercased()
                }
                Button {
                    Task { await toggleFavorite(station, isSaved: isSaved) }
                } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .foregroundStyle(isSaved ? Color.red : settings.accentColor)
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isSaved ? "Remove saved station" : "Save station")
            }
        }
    }

    private func savedStationRow(
        _ favorite: TropLibraryV2RadioStore.Favorite
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    do {
                        try await RadioPlaybackCoordinator.playSaved(
                            stationUUID: favorite.stationUUID
                        )
                        radioFavoriteError = nil
                    } catch {
                        radioFavoriteError = "This station cannot be reached right now."
                    }
                }
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favorite.name)
                        if !favorite.subtitle.isEmpty {
                            Text(favorite.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                Task { await removeFavorite(favorite.stationUUID) }
            } label: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove saved station")
        }
    }

    @MainActor
    private func loadSavedStations() async {
        do {
            savedStations = try await TropLibraryV2RadioStore.favorites()
            radioFavoriteError = nil
        } catch {
            radioFavoriteError = "Could not load saved stations."
        }
    }

    @MainActor
    private func toggleFavorite(_ station: RadioStation, isSaved: Bool) async {
        do {
            if isSaved {
                try await TropLibraryV2RadioStore.remove(stationUUID: station.stationuuid)
            } else {
                try await TropLibraryV2RadioStore.save(station: station)
            }
            await loadSavedStations()
            NotificationCenter.default.post(
                name: Notification.Name("trop.radioFavoritesChanged"),
                object: nil
            )
        } catch {
            radioFavoriteError = "Could not update the saved station."
        }
    }

    @MainActor
    private func removeFavorite(_ stationUUID: String) async {
        do {
            try await TropLibraryV2RadioStore.remove(stationUUID: stationUUID)
            await loadSavedStations()
            NotificationCenter.default.post(
                name: Notification.Name("trop.radioFavoritesChanged"),
                object: nil
            )
        } catch {
            radioFavoriteError = "Could not remove the saved station."
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        let term = query.trimmingCharacters(in: .whitespaces)
        do {
            let loaded: [RadioStation]
            if !term.isEmpty {
                loaded = try await RadioBrowser.search(term)
            } else if selectedTag == "Top" {
                loaded = try await RadioBrowser.topStations()
            } else {
                loaded = try await RadioBrowser.stations(tag: selectedTag.lowercased())
            }
            stations = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func play(_ station: RadioStation) {
        Task { await RadioPlaybackCoordinator.play(station) }
    }

}
