import AVFoundation

enum AudioEffects {
    /// Scales quiet audio up to a consistent peak; never attenuates beyond the target.
    static func normalized(_ samples: [Float], peak target: Float = 0.89) -> [Float] {
        let peak = samples.reduce(0) { max($0, abs($1)) }
        guard peak > 1e-4, abs(peak - target) > 0.01 else { return samples }
        let gain = target / peak
        return samples.map { $0 * gain }
    }

    static func resampled(_ samples: [Float], from sourceRate: Int, to targetRate: Int) -> [Float] {
        guard sourceRate != targetRate, !samples.isEmpty,
              let source = AVAudioFormat(standardFormatWithSampleRate: Double(sourceRate), channels: 1),
              let target = AVAudioFormat(standardFormatWithSampleRate: Double(targetRate), channels: 1),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(
                pcmFormat: target,
                frameCapacity: AVAudioFrameCount(samples.count * targetRate / sourceRate + 1024))
        else { return samples }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        var isConsumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if isConsumed {
                status.pointee = .endOfStream
                return nil
            }
            isConsumed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil else { return samples }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    /// Offline time-stretch and pitch shift; tempo changes keep the original pitch.
    static func process(_ samples: [Float], sampleRate: Int, rate: Float, pitchCents: Float) throws -> [Float] {
        guard rate != 1 || pitchCents != 0, !samples.isEmpty else { return samples }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return samples }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = rate
        timePitch.pitch = pitchCents
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        let chunkSize: AVAudioFrameCount = 4096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkSize)
        try engine.start()
        defer { engine.stop() }
        player.scheduleBuffer(input)
        player.play()

        guard let output = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: chunkSize) else {
            return samples
        }
        let expected = Int(Double(samples.count) / Double(rate))
        var result: [Float] = []
        result.reserveCapacity(expected)
        while result.count < expected {
            let frames = AVAudioFrameCount(min(Int(chunkSize), expected - result.count))
            guard try engine.renderOffline(frames, to: output) == .success else { break }
            result += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
        }
        return result
    }
}
