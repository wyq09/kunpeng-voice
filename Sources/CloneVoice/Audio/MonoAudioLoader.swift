import AVFoundation

enum MonoAudioLoader {
    /// Reads any audio file as peak-normalized mono float samples at `sampleRate`.
    static func load(_ url: URL, sampleRate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw CocoaError(.fileReadCorruptFile) }
        try file.read(into: input)

        let capacity = AVAudioFrameCount(Double(input.frameLength) * sampleRate / file.processingFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw CocoaError(.fileReadCorruptFile)
        }
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
        if let error { throw error }
        return AudioEffects.normalized(
            Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))))
    }
}
