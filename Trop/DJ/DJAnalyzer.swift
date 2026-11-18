import AVFoundation

/// On-device analysis for offline DJ: duration, RMS energy and an approximate
/// BPM from the energy-flux autocorrelation. No external deps, no network.
enum DJAnalyzer {
    static func analyze(_ track: DJSourceTrack) async throws -> DJTrackAnalysis {
        let file = try AVAudioFile(forReading: track.fileURL)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw DJAnalyzerError.unreadable
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw DJAnalyzerError.unreadable }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channelCount { sum += channels[channel][frame] }
            mono[frame] = sum / Float(channelCount)
        }
        let duration = Double(file.length) / sampleRate
        let energy = rms(mono)
        let bpm = estimateBPM(mono, sampleRate: sampleRate)
        return DJTrackAnalysis(
            trackID: track.id,
            bpm: bpm,
            energy: energy,
            duration: duration
        )
    }

    static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for value in samples { sum += Double(value * value) }
        let rms = sqrt(sum / Double(samples.count))
        // Map to a practical 0…1 scale (≈ -60 dB…0 dB).
        let db = 20 * log10(max(rms, 1e-6))
        return min(max((db + 60) / 60, 0), 1)
    }

    /// Energy-flux onset envelope + autocorrelation over 60–180 BPM.
    static func estimateBPM(_ samples: [Float], sampleRate: Double) -> Double? {
        let hop = 1024
        let limit = min(samples.count, Int(sampleRate * 60))
        guard limit > hop * 8 else { return nil }
        var flux: [Double] = []
        flux.reserveCapacity(limit / hop)
        var previous: Double = 0
        var index = 0
        while index + hop < limit {
            var sum: Double = 0
            for i in index..<(index + hop) {
                let v = Double(samples[i])
                sum += v * v
            }
            let energy = sqrt(sum / Double(hop))
            flux.append(max(0, energy - previous))
            previous = energy
            index += hop
        }
        guard flux.count > 40 else { return nil }
        let frameRate = sampleRate / Double(hop)
        let minLag = Int((60.0 / 180.0) * frameRate)
        let maxLag = Int((60.0 / 60.0) * frameRate)
        guard minLag >= 1, maxLag > minLag, maxLag < flux.count else { return nil }
        var bestLag = 0
        var bestScore = 0.0
        for lag in minLag...maxLag {
            var score: Double = 0
            for i in 0..<(flux.count - lag) { score += flux[i] * flux[i + lag] }
            score /= Double(flux.count - lag)
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestLag > 0, bestScore > 1e-9 else { return nil }
        return (60.0 * frameRate) / Double(bestLag)
    }
}

enum DJAnalyzerError: Error { case unreadable }
