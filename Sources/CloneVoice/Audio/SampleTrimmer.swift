import AVFoundation

/// Copies the first seconds of any audio file into a WAV the model can read.
/// Longer references slow generation without improving similarity.
enum SampleTrimmer {
    static let maxDuration: TimeInterval = 15

    static func prepare(_ source: URL) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let frames = AVAudioFrameCount(min(Double(input.length), maxDuration * format.sampleRate))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try input.read(into: buffer, frameCount: frames)

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: output,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ],
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        try file.write(from: buffer)
        return output
    }
}
