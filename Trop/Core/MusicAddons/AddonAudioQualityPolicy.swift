import Foundation

/// Enforces user-controlled quality limits on the *returned stream*, not only
/// the requested Eclipse query. Providers may ignore quality=lossless or
/// atmos=false. Direct addon playback and background matching share this gate.
///
/// The facts here are provider-reported. A decoder/probe must check the
/// actual FLAC bit depth / sample rate before claiming verified Hi-Res or CD.
enum AddonAudioQualityPolicy {
    static func isAtmos(qualityTier: String, mimeType: String) -> Bool {
        let tier = qualityTier.lowercased()
        let mime = mimeType.lowercased()
        return tier.contains("atmos") || tier.contains("eac3")
            || tier.contains("e-ac-3") || mime.contains("eac3")
            || mime.contains("ec+3") || mime.contains("e-ac-3")
    }

    static func isHiRes(
        qualityTier: String,
        advertisedHiRes: Bool,
        bitDepth: Int?,
        sampleRateHz: Int?
    ) -> Bool {
        let tier = qualityTier.lowercased()
        return advertisedHiRes || tier.contains("hi-res") || tier.contains("hires")
            || (bitDepth ?? 0) >= 24 || (sampleRateHz ?? 0) > 48_000
    }

    static func accepts(
        qualityTier: String,
        mimeType: String,
        advertisedHiRes: Bool,
        bitDepth: Int? = nil,
        sampleRateHz: Int? = nil,
        allowHiRes: Bool,
        allowAtmos: Bool,
        requireCD: Bool = false,
        highOnly: Bool = false
    ) -> Bool {
        let atmos = isAtmos(qualityTier: qualityTier, mimeType: mimeType)
        let hiRes = isHiRes(
            qualityTier: qualityTier,
            advertisedHiRes: advertisedHiRes,
            bitDepth: bitDepth,
            sampleRateHz: sampleRateHz
        )
        // Explicit opt-ins are hard limits, even when an addon ignores our
        // request, sends an unexpected URL, or a cached match is reused.
        if atmos && !allowAtmos { return false }
        if hiRes && !allowHiRes { return false }

        let tier = qualityTier.lowercased()
        if requireCD {
            return tier == "lossless" && !atmos && !hiRes
                && (bitDepth ?? 0) <= 16 && (sampleRateHz ?? 0) <= 44_100
        }
        if highOnly {
            // "High (320)" should not silently play a giant FLAC or Atmos.
            // Standard remains an allowed fallback for an explicit addon.
            return !atmos && !hiRes && tier != "lossless"
        }
        return true
    }
}
