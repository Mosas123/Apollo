import Foundation

// The real SettingsStore owns this protocol, but only its marker conformance
// is needed when compiling MusicQualityMode independently in the test runner.
protocol SettingsOption {}

// Protocol-only fixtures: compile the production policy without a private
// addon, real URL or iOS framework. The iOS Nightly compiles actual sources.
enum AddonStreamQuality: String, Sendable {
    case max
    case hires
    case lossless
    case high
}

struct AddonStream: Sendable {
    let qualityTier: String
    let mimeType: String
    var isHiRes = false
    var bitDepth: Int? = nil
    var sampleRateHz: Int? = nil
}

@main
struct AddonQualityPolicyChecks {
    static func main() {
        let cd = AddonStream(qualityTier: "Lossless", mimeType: "audio/flac")
        let hiRes = AddonStream(
            qualityTier: "Lossless", mimeType: "audio/flac", isHiRes: true,
            bitDepth: 24, sampleRateHz: 96_000
        )
        let metadataHiRes = AddonStream(
            qualityTier: "Lossless", mimeType: "audio/flac",
            bitDepth: 24
        )
        let highRateHiRes = AddonStream(
            qualityTier: "Lossless", mimeType: "audio/flac",
            sampleRateHz: 96_000
        )
        let atmos = AddonStream(qualityTier: "Atmos", mimeType: "audio/mp4")
        let eac3 = AddonStream(qualityTier: "High", mimeType: "audio/eac3")
        let high = AddonStream(qualityTier: "High", mimeType: "audio/mp4")
        let standard = AddonStream(qualityTier: "Standard", mimeType: "audio/mpeg")

        let defaults = AddonStreamQualityPolicy(
            mode: .auto, preferHiRes: false, preferAtmos: false
        )
        precondition(defaults.requestedQuality == .lossless)
        precondition(defaults.accepts(cd))
        precondition(defaults.accepts(high))
        precondition(defaults.accepts(standard))
        for forbidden in [hiRes, metadataHiRes, highRateHiRes, atmos, eac3] {
            precondition(!defaults.accepts(forbidden), "Advanced stream leaked past opt-out")
        }

        let hiResOnly = AddonStreamQualityPolicy(
            mode: .auto, preferHiRes: true, preferAtmos: false
        )
        precondition(hiResOnly.requestedQuality == .hires)
        precondition(hiResOnly.accepts(cd))
        precondition(hiResOnly.accepts(hiRes))
        precondition(!hiResOnly.accepts(atmos))
        precondition(!hiResOnly.accepts(eac3))

        let atmosOnly = AddonStreamQualityPolicy(
            mode: .auto, preferHiRes: false, preferAtmos: true
        )
        precondition(atmosOnly.requestedQuality == .max)
        precondition(atmosOnly.accepts(atmos))
        precondition(atmosOnly.accepts(eac3))
        precondition(!atmosOnly.accepts(hiRes))

        let both = AddonStreamQualityPolicy(
            mode: .lossless, preferHiRes: true, preferAtmos: true
        )
        precondition(both.accepts(atmos))
        precondition(both.accepts(hiRes))
        precondition(both.accepts(cd))
        precondition(!both.accepts(high))
        precondition(both.rank(atmos) > both.rank(hiRes))
        precondition(both.rank(hiRes) > both.rank(cd))

        let cdOnly = AddonStreamQualityPolicy(
            mode: .cd, preferHiRes: true, preferAtmos: true
        )
        precondition(!cdOnly.allowHiRes && !cdOnly.allowAtmos)
        precondition(cdOnly.requestedQuality == .lossless)
        precondition(cdOnly.accepts(cd))
        for forbidden in [hiRes, metadataHiRes, highRateHiRes, atmos, eac3, high] {
            precondition(!cdOnly.accepts(forbidden), "CD mode leaked an incompatible stream")
        }

        let highOnly = AddonStreamQualityPolicy(
            mode: .high, preferHiRes: true, preferAtmos: true
        )
        precondition(!highOnly.allowHiRes && !highOnly.allowAtmos)
        precondition(highOnly.requestedQuality == .high)
        precondition(highOnly.accepts(high) && highOnly.accepts(standard))
        precondition(!highOnly.accepts(cd) && !highOnly.accepts(hiRes))
        precondition(!highOnly.accepts(atmos))

        let flacOnly = AddonStreamQualityPolicy(
            mode: .lossless, preferHiRes: false, preferAtmos: false
        )
        precondition(flacOnly.accepts(cd) && !flacOnly.accepts(high))
        precondition(!flacOnly.accepts(hiRes) && !flacOnly.accepts(atmos))

        // Stremio offers multiple URLs in a single response: toggling Dolby
        // cannot implicitly turn on Hi-Res, even for quality=max.
        let stremioAtmosOnly = AddonStreamQualityPolicy.stremio(
            requested: .max, preferAtmos: true, allowHiRes: false,
            requireLossless: true
        )
        precondition(stremioAtmosOnly.accepts(atmos))
        precondition(!stremioAtmosOnly.accepts(hiRes))
        let stremioCD = AddonStreamQualityPolicy.stremio(
            requested: .lossless, preferAtmos: true, allowHiRes: true,
            requireLossless: true
        )
        precondition(stremioCD.accepts(cd))
        precondition(!stremioCD.accepts(hiRes))
        precondition(!stremioCD.accepts(atmos))
        let stremioHigh = AddonStreamQualityPolicy.stremio(
            requested: .high, preferAtmos: true, allowHiRes: true,
            requireLossless: false
        )
        precondition(!stremioHigh.accepts(cd))
        precondition(stremioHigh.accepts(high))

        // Auto may fall back to High; Best FLAC only accepts FLAC.
        let stremioAuto = AddonStreamQualityPolicy.stremio(
            requested: .lossless, preferAtmos: false, allowHiRes: false,
            requireLossless: false
        )
        precondition(stremioAuto.accepts(high) && stremioAuto.accepts(cd))
        precondition(!stremioAuto.accepts(hiRes) && !stremioAuto.accepts(atmos))

        print("Independent Hi-Res / Dolby addon quality policy checks passed")
    }
}
