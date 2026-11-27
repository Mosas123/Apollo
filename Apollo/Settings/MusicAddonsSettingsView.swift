import SwiftUI

/// Music-only addon manager inspired by the *layout hierarchy* of NuvioMobile:
/// overview, URL installation and manageable provider cards. The SwiftUI
/// implementation is original, and the app executes no downloaded code.
struct MusicAddonsSettingsView: View {
    @State private var addonStore = MusicAddonsStore.shared
    @Bindable private var accountState = AccountSheetState.shared

    @State private var manifestURL = ""
    @State private var isChecking = false
    @State private var refreshingKey: String?
    @State private var pendingInstall: PendingInstall?
    @State private var pendingRemovalKey: String?
    @State private var showRemovalConfirmation = false
    @State private var message: String?
    @State private var showMessage = false

    private struct PendingInstall: Identifiable {
        let id = UUID()
        let data: Data
        let package: MusicAddonPackage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                defaultSourceCard
                overviewSection
                addSection
                installedSection
                limitationsCard
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding(16)
        }
        .navigationTitle("Music Addons")
        .navigationBarTitleDisplayMode(.inline)
        .miniPlayerTracksScroll()
        .loginSheet(state: accountState)
        .task {
            await accountState.restoreSession()
        }
        .sheet(item: $pendingInstall) { candidate in
            reviewSheet(for: candidate)
        }
        .confirmationDialog(
            "Remove this music addon?",
            isPresented: $showRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Addon", role: .destructive) {
                if let key = pendingRemovalKey {
                    do {
                        try addonStore.remove(key: key)
                    } catch {
                        show(error.localizedDescription)
                    }
                }
                pendingRemovalKey = nil
            }
            Button("Cancel", role: .cancel) { pendingRemovalKey = nil }
        } message: {
            Text("Its saved manifest and enabled status will be removed from this device.")
        }
        .alert("Music Addons", isPresented: $showMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? String(localized: "Unable to complete this action."))
        }
    }

    private func reviewSheet(for candidate: PendingInstall) -> some View {
        let manifest = candidate.package.manifest
        return NavigationStack {
            Form {
                Section("Provider") {
                    LabeledContent("Name", value: manifest.name)
                    LabeledContent("Version", value: manifest.version)
                    Text(manifest.description ?? String(localized: "No description provided."))
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(manifest.capabilities, id: \.self) { capability in
                        Label(LocalizedStringKey(capabilityTitle(capability)), systemImage: capabilityIcon(capability))
                    }
                } header: {
                    Text("Requested capabilities")
                } footer: {
                    Text("Review this provider before installing. It will start disabled.")
                }
                Section("Manifest address") {
                    Text(candidate.package.manifestURL.absoluteString)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Review Addon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { pendingInstall = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Install Disabled") {
                        install(candidate)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func install(_ candidate: PendingInstall) {
        do {
            try addonStore.install(candidate.data, from: candidate.package.manifestURL)
            pendingInstall = nil
            manifestURL = ""
        } catch {
            pendingInstall = nil
            show(error.localizedDescription)
        }
    }

    private var defaultSourceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note.house.fill")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("YouTube Music").font(.headline)
                    Text("Default")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
                Text("Primary catalog, recommendations and music library")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if accountState.isLoggedIn {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Connected")
            } else {
                Button("Sign In") {
                    accountState.isLoginSheetPresented = true
                }
                .buttonStyle(.bordered)
            }
        }
        .addonCardSurface()
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Overview")
            HStack(spacing: 0) {
                statistic(addonStore.installations.count, label: "Installed")
                Divider().frame(height: 42)
                statistic(addonStore.enabledCount, label: "Enabled")
                Divider().frame(height: 42)
                statistic(addonStore.streamCapabilityCount, label: "Audio capable")
            }
            .addonCardSurface()
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Add Music Addon")
            VStack(alignment: .leading, spacing: 14) {
                TextField("https://provider.example/manifest.json", text: $manifestURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit(checkManifest)

                Button(action: checkManifest) {
                    HStack(spacing: 8) {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text(LocalizedStringKey(isChecking ? "Checking Manifest…" : "Review & Install"))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking || manifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Add a music addon manifest. Stremio (catalog/stream) and Apollo v1 manifests are supported read-only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Try Offline Demo Addon") {
                    do {
                        try addonStore.installSample()
                    } catch MusicAddonError.alreadyInstalled {
                        show(String(localized: "The demo addon is already installed."))
                    } catch {
                        show(error.localizedDescription)
                    }
                }
                .buttonStyle(.bordered)

                Text("Demo only: lets you test install, enable, reorder and remove without playing audio or connecting to a provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .addonCardSurface()
        }
    }

    private func audioQualitySummary(_ caps: AddonCapabilities) -> String {
        var parts: [String] = []
        if caps.cd { parts.append("FLAC CD") }
        if caps.hiRes { parts.append("Hi-Res") }
        if caps.aac320 { parts.append("AAC 320") }
        if caps.atmos { parts.append("Atmos") }
        return parts.isEmpty ? String(localized: "Audio: unknown") : AppStrings.format("Audio: %@", parts.joined(separator: " · "))
    }

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Installed Addons")
            if addonStore.installations.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label("No music addons installed", systemImage: "puzzlepiece.extension")
                        .font(.headline)
                    Text("Install a compatible music addon to manage it here.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .addonCardSurface()
            } else {
                ForEach(
                    Array(addonStore.installations.enumerated()),
                    id: \.element.key
                ) { pair in
                    installedCard(pair.element, position: pair.offset)
                }
            }
        }
    }

    private func installedCard(_ entry: MusicAddonInstallation, position: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.manifest.name)
                        .font(.headline)
                    Text(AppStrings.format("Version %@", entry.manifest.version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Toggle(
                    AppStrings.format("Enable %@", entry.manifest.name),
                    isOn: Binding(
                        get: {
                            addonStore.installations.first(where: { $0.key == entry.key })?.isEnabled ?? false
                        },
                        set: { enabled in
                            do {
                                try addonStore.setEnabled(enabled, key: entry.key)
                            } catch {
                                show(error.localizedDescription)
                            }
                        }
                    )
                )
                .labelsHidden()
            }

            if let description = entry.manifest.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(entry.manifest.capabilities.map { NSLocalizedString(capabilityTitle($0), comment: "Music add-on capability") }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(audioQualitySummary(entry.audioCapabilities))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 16) {
                Button {
                    addonStore.move(from: position, to: position - 1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(position == 0)
                .accessibilityLabel(AppStrings.format("Move %@ up", entry.manifest.name))

                Button {
                    addonStore.move(from: position, to: position + 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(position >= addonStore.installations.count - 1)
                .accessibilityLabel(AppStrings.format("Move %@ down", entry.manifest.name))

                Button {
                    refresh(entry.key)
                } label: {
                    if refreshingKey == entry.key {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(refreshingKey != nil || isChecking || MusicAddonsStore.isSample(entry))
                .accessibilityLabel("Check updates for \(entry.manifest.name)")

                Spacer()

                Button(role: .destructive) {
                    pendingRemovalKey = entry.key
                    showRemovalConfirmation = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
        .addonCardSurface()
    }

    private var limitationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Music sources", systemImage: "info.circle")
                .font(.subheadline.bold())
            Text("YouTube Music is the main catalog. Enabled add-ons can provide additional search results and playback sources.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .addonCardSurface()
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(LocalizedStringKey(title))
            .textCase(.uppercase)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 5)
    }

    private func statistic(_ count: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text(count.formatted())
                .font(.title2.bold())
                .monospacedDigit()
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }

    private func capabilityTitle(_ capability: MusicAddonCapability) -> String {
        switch capability {
        case .search: return "Search"
        case .catalog: return "Catalogs"
        case .stream: return "Audio"
        case .lyrics: return "Lyrics"
        case .metadata: return "Metadata"
        case .history: return "History"
        }
    }

    private func capabilityIcon(_ capability: MusicAddonCapability) -> String {
        switch capability {
        case .search: return "magnifyingglass"
        case .catalog: return "square.stack"
        case .stream: return "waveform"
        case .lyrics: return "text.quote"
        case .metadata: return "info.circle"
        case .history: return "clock.arrow.circlepath"
        }
    }

    private func checkManifest() {
        guard !isChecking else { return }
        let input = manifestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input) else {
            show(String(localized: "Enter a valid HTTPS manifest URL."))
            return
        }
        isChecking = true
        Task {
            do {
                let (data, canonical) = try await MusicAddonManifestDownloader().download(from: url)
                let package = try MusicAddonPackage.parse(data, from: canonical)
                pendingInstall = PendingInstall(data: data, package: package)
            } catch {
                show(error.localizedDescription)
            }
            isChecking = false
        }
    }

    private func refresh(_ key: String) {
        guard refreshingKey == nil else { return }
        refreshingKey = key
        Task {
            do {
                try await addonStore.refresh(key: key)
            } catch {
                show(error.localizedDescription)
            }
            refreshingKey = nil
        }
    }

    private func show(_ text: String) {
        message = text
        showMessage = true
    }
}

private struct MusicAddonCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

private extension View {
    func addonCardSurface() -> some View {
        modifier(MusicAddonCardSurface())
    }
}
