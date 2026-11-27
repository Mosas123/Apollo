//
//  DownloadsView.swift
//  Apollo
//

import SwiftUI
import UniformTypeIdentifiers

struct DownloadsView: View {
    @Environment(SettingsStore.self) private var settings
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var pendingRoute: DetailRoute?
    @State private var showMoreSheet = false
    @State private var showingAudioImporter = false
    @State private var importErrorMessage = ""
    @State private var showingImportError = false

    private var tracks: [DownloadedTrackEntity] { downloadManager.tracks }
    private var songs: [SongItem] { tracks.map { SongItem(entity: $0) } }
    private var activeDownloads: [(videoId: String, progress: Double)] {
        downloadManager.activeDownloads
    }

    var body: some View {
        Group {
            if !downloadManager.isLoaded {
                LoadingStateView("Loading downloads…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty && activeDownloads.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAudioImporter = true
                } label: {
                    Label("Import Audio", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("Import audio from Files")
            }
        }
        .fileImporter(
            isPresented: $showingAudioImporter,
            allowedContentTypes: [.audio, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { @MainActor in
                    for url in urls {
                        do {
                            try await downloadManager.importLocalAudio(from: url)
                        } catch {
                            importErrorMessage = error.localizedDescription
                            showingImportError = true
                            break
                        }
                    }
                }
            case .failure(let error):
                importErrorMessage = error.localizedDescription
                showingImportError = true
            }
        }
        .alert("Could not import audio", isPresented: $showingImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        .refreshable { await downloadManager.reload() }
        .task {
            if !downloadManager.isLoaded {
                await downloadManager.reload()
            }
        }
        .detailRouteSheet(item: $pendingRoute)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Downloads Yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Save songs for offline listening from the player menu, or enable auto-download when you like a track.")
        } actions: {
            NavigationLink {
                DownloadSettingsView()
            } label: {
                Text("Download Settings")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(settings.accentColor)
            Button("Import Audio from Files") {
                showingAudioImporter = true
            }
            .buttonStyle(.bordered)
        }
        .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                    .padding(.bottom, 8)

                if !activeDownloads.isEmpty {
                    activeDownloadsSection
                }

                if !songs.isEmpty {
                    songList
                }
            }
        }
        .scrollDisabled(!downloadManager.isLoaded)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .miniPlayerTracksScroll().scrollEdgeEffectHidden(true, for: .bottom)
    }

    private var header: some View {
        PlaylistHeaderView(
            title: "Downloads",
            thumbnails: Array(tracks.prefix(4).compactMap(\.thumbnailUrl)),
            songCount: tracks.count,
            duration: tracks.reduce(0) { $0 + $1.duration },
            accentColor: settings.accentColor,
            onPlay: playAll,
            onShuffle: shufflePlay,
            onMore: { showMoreSheet = true }
        )
        .sheet(isPresented: $showMoreSheet) {
            DownloadsMoreSheet(songs: songs)
        }
    }

    private var activeDownloadsSection: some View {
        VStack(spacing: 0) {
            SectionLabel(title: "Downloading", systemImage: "arrow.down.circle")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            ForEach(activeDownloads, id: \.videoId) { item in
                ActiveDownloadRow(videoId: item.videoId, progress: item.progress)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var songList: some View {
        // Direct LazyVStack children → rows build lazily.
        ForEach(Array(songs.enumerated()), id: \.element.videoId) { index, song in
            SongRowView(
                song: song,
                artSize: 48,
                artRadius: 8,
                onTap: { playSong(song) },
                onNavigate: { pendingRoute = $0 }
            )
            .id(song.videoId)

            if index < songs.count - 1 {
                Divider()
                    .padding(.leading, 76)
            }
        }
    }

    private func playAll() {
        let songs = songs
        guard !songs.isEmpty else { return }
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        NowPlaying.shared.update(with: songs[0])
        let intent = NowPlaying.shared.playbackGeneration
        Task { await playLocal(songs[0], intent: intent) }
    }

    private func shufflePlay() {
        let songs = songs.shuffled()
        guard !songs.isEmpty else { return }
        NowPlaying.shared.setQueue(songs, startIndex: 0)
        NowPlaying.shared.update(with: songs[0])
        let intent = NowPlaying.shared.playbackGeneration
        Task { await playLocal(songs[0], intent: intent) }
    }

    private func playSong(_ song: SongItem) {
        let songs = songs
        if let index = songs.firstIndex(where: { $0.videoId == song.videoId }) {
            NowPlaying.shared.setQueue(songs, startIndex: index)
        } else {
            NowPlaying.shared.setQueue([song], startIndex: 0)
        }
        NowPlaying.shared.update(with: song)
        let intent = NowPlaying.shared.playbackGeneration
        Task { await playLocal(song, intent: intent) }
    }

    private func playLocal(_ song: SongItem, intent: Int) async {
        guard let localURL = await downloadManager.localURL(for: song.videoId) else {
            guard NowPlaying.shared.playbackGeneration == intent,
                  NowPlaying.shared.videoId == song.videoId else { return }
            NowPlaying.shared.isPlaying = false
            Log.downloadManager.warning("Local audio not found for \(song.videoId)")
            importErrorMessage = "This local audio file is no longer available. Try refreshing Downloads or importing it again."
            showingImportError = true
            return
        }
        // A file lookup may suspend while the user chooses another song.
        // Never let the older result start playback or override its metadata.
        guard NowPlaying.shared.playbackGeneration == intent,
              NowPlaying.shared.videoId == song.videoId else { return }
        let artists = song.artists
        let displayArtist = artists.map(\.name).joined(separator: ", ")
        await PlayerController.shared.play(
            url: localURL.absoluteString,
            title: song.title,
            artist: displayArtist,
            videoId: song.videoId,
            duration: TimeInterval(song.duration),
            artists: artists,
            intentGeneration: intent,
            sourceMIMEType: LocalAudioFilePolicy.mimeHint(for: localURL)
        )
        guard NowPlaying.shared.playbackGeneration == intent,
              NowPlaying.shared.videoId == song.videoId else { return }
        NowPlaying.shared.currentSourceName = "Downloaded"
        NowPlaying.shared.updateVideoAvailability()
    }
}
