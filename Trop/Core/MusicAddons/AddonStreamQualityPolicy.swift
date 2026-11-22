import Foundation

/// The user's add-on quality settings are limits, not suggestions.
///
/// Providers can return a different tier than requested. Validate the actual
/// response on BOTH automatic discovery and direct Search → Add-ons playback;
/// the URL's claimed format is not proof of its decoded PCM bit depth.
struct AddonStreamQualityPolicy: Sendable {
    let mode: MusicQualityMode
    let allowHiRes: Bool
    let allowAtmos: Bool

    init(mode: MusicQualityMode, preferHiRes: Bool, preferAtmos: Bool) {
        self.mode = mode
        let permitsAdvanced = mode == .auto || mode == .lossless
        allowHiRes = permitsAdvanced && preferHiRes
        allowAtmos = permitsAdvanced && preferAtmos
    }

    /// Ask for CD unless the user explicitly unlocked an advanced tier.
    var requestedQuality: AddonStreamQuality {
        if mode == .high { return .high }
        if allowAtmos { return .max }
        if allowHiRes { return .hires }
        return .lossless
    }

    static func isAtmos(_ stream: AddonStream) -> Bool {
        let tier = stream.qualityTier.lowercased()
        let mime = stream.mimeType.lowercased()
        return tier.contains("atmos") || tier.contains("dolby")
            || mime.contains("eac3") || mime.contains("e-ac-3")
            || mime.contains("ec+3") || mime.contains("ec-3")
    }

    static func isHiRes(_ stream: AddonStream) -> Bool {
        stream.isHiRes || (stream.bitDepth ?? 0) >= 24
            || (stream.sampleRateHz ?? 0) > 48_000
            || stream.qualityTier.lowercased().contains("hi-res")
            || stream.qualityTier.lowercased().contains("hires")
    }

    /// True only when this declared stream stays within the user's setting.
    /// The media probe may later expose wrongly labelled high-resolution
    /// content: this check must NOT be presented as a decoded-format audit.
    func accepts(_ stream: AddonStream) -> Bool {
        if Self.isAtmos(stream) { return allowAtmos }
        if Self.isHiRes(stream) && !allowHiRes { return false }

        let lossless = stream.qualityTier.caseInsensitiveCompare("Lossless") == .orderedSame
        switch mode {
        case .cd:
            // 16/44.1 only when the provider supplies this metadata. An
            // unspecified stream is still provisional until audio probing.
            if let bits = stream.bitDepth, bits != 16 { return false }
            if let hz = stream.sampleRateHz, hz != 44_100 { return false }
            return lossless && !Self.isHiRes(stream)
        case .lossless:
            return lossless
        case .high:
            return !lossless // High caps requested quality below FLAC.
        case .auto, .off:
            return true // Off disables automatic search, not explicit selection.
        }
    }

    /// Rank *accepted* sources. Atmos and Hi-Res are never implicitly better
    /// unless allowed by their own opt-in controls.
    func rank(_ stream: AddonStream) -> Int {
        guard accepts(stream) else { return -1 }
        if Self.isAtmos(stream) { return 5 }
        if Self.isHiRes(stream) { return 4 }
        switch stream.qualityTier {
        case "Lossless": return 3
        case "High": return 2
        default: return 1
        }
    }

    /// Stremio returns several sources in one response, unlike Eclipse.
    /// Select among the *offered* sources by the same policy.
    static func stremio(
        requested quality: AddonStreamQuality,
        preferAtmos: Bool,
        allowHiRes: Bool,
        requireLossless: Bool
    ) -> Self {
        // "quality=lossless" is a provider request hint, not the user's
        // quality mode. Auto may still accept High if a provider has no FLAC.
        let mode: MusicQualityMode = requireLossless ? .lossless : .auto
        switch quality {
        case .max:
            return .init(mode: mode, preferHiRes: allowHiRes, preferAtmos: preferAtmos)
        case .hires:
            return .init(mode: mode, preferHiRes: true, preferAtmos: preferAtmos)
        case .lossless:
            return .init(mode: mode, preferHiRes: false, preferAtmos: false)
        case .high:
            return .init(mode: .high, preferHiRes: false, preferAtmos: false)
        }
    }
}
