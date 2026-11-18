import AVFoundation

/// Offline renderer: decodes each local file to 44.1 kHz stereo float, mixes
/// slots with linear crossfades into one buffer, and writes a WAV. AVFoundation
/// only; never touches mpv or streaming.
enum DJMixRenderer {
    static let sampleRate: Double = 44_100

    static func render(plan: DJMixPlan, to outputURL: URL) async throws -> URL {
        guard !plan.slots.isEmpty else { throw DJRenderError.emptyPlan }
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!
        var output: [Float] = []

        for (index, slot) in plan.slots.enumerated() {
            try Task.checkCancellation()
            guard let samples = try decode(slot.track.fileURL, format: format) else { continue }
            let fadeIn = index == 0 ? 0 : plan.slots[index - 1].crossfadeSeconds
            let fadeOut = slot.crossfadeSeconds
            let fadeInFrames = Int(fadeIn * sampleRate)
            let fadeOutFrames = Int(fadeOut * sampleRate)
            let overlapStart = max(0, output.count / 2 - fadeInFrames)
            var mixed = output + [Float](repeating: 0, count: samples.count)

            for frame in 0..<(samples.count / 2) {
                let left = samples[frame * 2]
                let right = samples[frame * 2 + 1]
                var gain: Float = 1
                if fadeInFrames > 0, frame < fadeInFrames {
                    gain = Float(frame) / Float(fadeInFrames)
                }
                if fadeOutFrames > 0, frame >= (samples.count / 2 - fadeOutFrames) {
                    gain = min(gain, Float(samples.count / 2 - frame) / Float(fadeOutFrames))
                }
                let base = overlapStart * 2 + frame * 2
                if base + 1 < mixed.count {
                    mixed[base] = mixed[base] * (1 - gain) + left * gain
                    mixed[base + 1] = mixed[base + 1] * (1 - gain) + right * gain
                }
            }
            output = mixed
        }

        guard !output.isEmpty else { throw DJRenderError.emptyPlan }
        let frameCount = AVAudioFrameCount(output.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            throw DJRenderError.writeFailed
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            channelData[0][frame] = output[frame * 2]
            channelData[1][frame] = output[frame * 2 + 1]
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]
        let file = try AVAudioFile(forWriting: outputURL, settings: settings)
        try file.write(from: buffer)
        return outputURL
    }

    private static func decode(_ url: URL, format: AVAudioFormat) throws -> [Float]? {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        let capacity = AVAudioFrameCount(file.length)
        guard capacity > 0,
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: capacity) else {
            return nil
        }
        try file.read(into: input)
        guard inputFormat == format else {
            guard let converter = AVAudioConverter(from: inputFormat, to: format) else { return nil }
            let ratio = format.sampleRate / inputFormat.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(capacity) * ratio) + 1024
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
                return nil
            }
            var error: NSError?
            var supplied = false
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .endOfStream; return nil }
                supplied = true
                status.pointee = .haveData
                return input
            }
            guard error == nil, let data = output.floatChannelData else { return nil }
            let frames = Int(output.frameLength)
            var samples = [Float](repeating: 0, count: frames * 2)
            for frame in 0..<frames {
                samples[frame * 2] = data[0][frame]
                samples[frame * 2 + 1] = data[1][frame]
            }
            return samples
        }
        guard let data = input.floatChannelData else { return nil }
        let frames = Int(input.frameLength)
        var samples = [Float](repeating: 0, count: frames * 2)
        let channels = min(2, Int(inputFormat.channelCount))
        for frame in 0..<frames {
            samples[frame * 2] = data[0][frame]
            samples[frame * 2 + 1] = data[channels > 1 ? 1 : 0][frame]
        }
        return samples
    }
}

enum DJRenderError: Error { case emptyPlan, writeFailed }
