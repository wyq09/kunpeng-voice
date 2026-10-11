import Accelerate
import AVFoundation
import SpeechEnhancement

/// Turns a raw recording into a dry voice sample for cloning: removes rumble and background
/// noise, trims silence and evens out loudness. Artifacts from over-processing get cloned
/// along with the timbre, so every stage is deliberately gentle.
enum VoiceCleaner {
    enum Method {
        /// DeepFilterNet3 neural noise suppression.
        case neural
        /// Spectral gating fallback when the neural model isn't available.
        case basic
    }

    struct Result {
        let url: URL
        let method: Method
    }

    static let sampleRate = 48_000
    /// Share of the untouched signal mixed back in; caps noise reduction near 20 dB
    /// and masks the "underwater" artifacts aggressive suppression leaves on the voice.
    private static let dryMix: Float = 0.1
    private static let targetRMS: Float = 0.1 // ≈ -20 dBFS over speech
    private static let peakCeiling: Float = 0.95

    /// Starts fetching the small denoiser model so it's ready by the time a recording ends.
    static func prepare() {
        Task.detached(priority: .utility) { _ = try? await Denoiser.shared.enhancer(waitingAtMost: nil) }
    }

    static func clean(_ source: URL) async throws -> Result {
        let samples = try MonoAudioLoader.load(source, sampleRate: Double(sampleRate))
        // A slow network must never hold up voice creation; fall back to the basic denoiser.
        let enhancer = try? await Denoiser.shared.enhancer(waitingAtMost: .seconds(15))
        return try await Task.detached(priority: .userInitiated) {
            var audio = highPassed(samples, cutoff: 75)
            var method = Method.basic
            if let enhancer, let denoised = try? await Denoiser.shared.enhance(audio, with: enhancer),
               denoised.count == audio.count {
                audio = zip(denoised, audio).map { $0 + dryMix * ($1 - $0) }
                method = .neural
            } else {
                audio = spectralGated(audio)
            }
            audio = leveled(compactingSilence(audio))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleaned-\(UUID().uuidString).wav")
            try write(audio, to: url)
            return Result(url: url, method: method)
        }.value
    }

    // MARK: - High-pass

    /// 4th-order Butterworth high-pass (two biquads): removes desk thumps, handling rumble and
    /// most 50/60 Hz mains hum (about -14 dB at 50 Hz) while leaving low male voices (85 Hz+) intact.
    static func highPassed(_ x: [Float], cutoff: Double) -> [Float] {
        // Q values of the two sections of a 4th-order Butterworth.
        biquadHighPass(biquadHighPass(x, cutoff: cutoff, q: 0.5412), cutoff: cutoff, q: 1.3066)
    }

    private static func biquadHighPass(_ x: [Float], cutoff: Double, q: Double) -> [Float] {
        let w0 = 2 * Double.pi * cutoff / Double(sampleRate)
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        let b0 = Float((1 + cosw) / 2 / a0), b1 = Float(-(1 + cosw) / a0), b2 = b0
        let a1 = Float(-2 * cosw / a0), a2 = Float((1 - alpha) / a0)
        var y = [Float](repeating: 0, count: x.count)
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in x.indices {
            let out = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x[i]; y2 = y1; y1 = out
            y[i] = out
        }
        return y
    }

    // MARK: - Spectral gating fallback

    /// Estimates the noise spectrum from the quietest frames and attenuates bins that sit
    /// near it. Handles steady noise (fans, hiss, hum) well; a floor of about -15 dB keeps
    /// the "musical noise" that full suppression produces out of the voice.
    static func spectralGated(_ x: [Float]) -> [Float] {
        let n = 1024, hop = 256, bins = n / 2 + 1
        guard x.count > n * 4,
              let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD),
              let inverse = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .INVERSE)
        else { return x }
        defer { vDSP_DFT_DestroySetup(forward); vDSP_DFT_DestroySetup(inverse) }

        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        let padded = [Float](repeating: 0, count: n) + x + [Float](repeating: 0, count: n)
        let frameCount = (padded.count - n) / hop + 1
        let zeros = [Float](repeating: 0, count: n)

        var spectra: [(re: [Float], im: [Float])] = []
        var power = [[Float]]()
        spectra.reserveCapacity(frameCount)
        for frame in 0..<frameCount {
            let start = frame * hop
            let windowed = vDSP.multiply(padded[start..<start + n], window)
            var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
            vDSP_DFT_Execute(forward, windowed, zeros, &re, &im)
            spectra.append((re, im))
            power.append((0..<bins).map { re[$0] * re[$0] + im[$0] * im[$0] })
        }

        // Noise profile: mean power of the quietest 10% of frames.
        let energies = power.map { $0.reduce(0, +) }
        let quiet = energies.indices.sorted { energies[$0] < energies[$1] }.prefix(max(4, frameCount / 10))
        var noise = [Float](repeating: 0, count: bins)
        for index in quiet { noise = vDSP.add(noise, power[index]) }
        noise = vDSP.divide(noise, Float(quiet.count))

        let floor: Float = 0.18, overSubtraction: Float = 1.5
        var previousGain = [Float](repeating: 1, count: bins)
        var output = [Float](repeating: 0, count: padded.count)
        var norm = [Float](repeating: 0, count: padded.count)
        for frame in 0..<frameCount {
            var gain = (0..<bins).map { k -> Float in
                let p = power[frame][k]
                return p > 0 ? max(floor, 1 - overSubtraction * noise[k] / p) : floor
            }
            // Smooth across neighbouring bins, then over time: fast attack, slower release.
            gain = (0..<bins).map { k in (gain[max(0, k - 1)] + gain[k] + gain[min(bins - 1, k + 1)]) / 3 }
            for k in 0..<bins {
                let rate: Float = gain[k] > previousGain[k] ? 0.7 : 0.3
                gain[k] = previousGain[k] + rate * (gain[k] - previousGain[k])
            }
            previousGain = gain

            var (re, im) = spectra[frame]
            for k in 0..<n {
                let g = gain[k < bins ? k : n - k]
                re[k] *= g
                im[k] *= g
            }
            var outRe = [Float](repeating: 0, count: n), outIm = [Float](repeating: 0, count: n)
            vDSP_DFT_Execute(inverse, re, im, &outRe, &outIm)
            let start = frame * hop
            for i in 0..<n {
                output[start + i] += outRe[i] / Float(n) * window[i]
                norm[start + i] += window[i] * window[i]
            }
        }
        return (0..<x.count).map { i in
            let w = norm[i + n]
            return w > 1e-6 ? output[i + n] / w : 0
        }
    }

    // MARK: - Silence

    /// Trims leading/trailing silence and shortens long pauses; long gaps in the reference
    /// teach the model a dragging rhythm.
    static func compactingSilence(_ x: [Float]) -> [Float] {
        let frame = sampleRate / 100 // 10 ms
        guard x.count > frame * 50 else { return x }
        let rms: [Float] = stride(from: 0, to: x.count - frame + 1, by: frame).map { start in
            x.withUnsafeBufferPointer { var v: Float = 0; vDSP_rmsqv($0.baseAddress! + start, 1, &v, vDSP_Length(frame)); return v }
        }
        let sorted = rms.sorted()
        let loud = sorted[Int(Double(rms.count - 1) * 0.95)]
        guard loud > 1e-4 else { return x }
        // Silence is whatever sits near the residual noise floor (+8 dB), kept between 35 and
        // 20 dB below the loud speech so soft consonants are never mistaken for it.
        let floor = sorted[sorted.count / 10]
        let threshold = min(max(loud * 0.018, floor * 2.5), loud * 0.1)
        let voiced = rms.map { $0 > threshold }
        guard let first = voiced.firstIndex(of: true), let last = voiced.lastIndex(of: true) else { return x }

        let pad = 15, maxGap = 60, keptGap = 40, fade = sampleRate / 100
        var ranges: [Range<Int>] = []
        var segmentStart = max(0, first - pad)
        var index = first
        while index <= last {
            if voiced[index] { index += 1; continue }
            var gapEnd = index
            while gapEnd <= last, !voiced[gapEnd] { gapEnd += 1 }
            if gapEnd - index > maxGap {
                ranges.append(segmentStart..<index + keptGap / 2)
                segmentStart = gapEnd - keptGap / 2
            }
            index = gapEnd
        }
        ranges.append(segmentStart..<min(rms.count, last + 1 + pad))

        var result: [Float] = []
        for range in ranges {
            let piece = Array(x[range.lowerBound * frame..<min(x.count, range.upperBound * frame)])
            if result.count >= fade, piece.count >= fade {
                // Short crossfade so joins don't click.
                for i in 0..<fade {
                    let t = Float(i) / Float(fade)
                    result[result.count - fade + i] = result[result.count - fade + i] * (1 - t) + piece[i] * t
                }
                result += piece[fade...]
            } else {
                result += piece
            }
        }
        return result
    }

    // MARK: - Loudness

    /// Brings speech to a consistent RMS without letting peaks clip.
    static func leveled(_ x: [Float]) -> [Float] {
        let frame = sampleRate / 50
        guard x.count > frame else { return x }
        let rms: [Float] = stride(from: 0, to: x.count - frame + 1, by: frame).map { start in
            x.withUnsafeBufferPointer { var v: Float = 0; vDSP_rmsqv($0.baseAddress! + start, 1, &v, vDSP_Length(frame)); return v }
        }
        let loud = rms.sorted()[Int(Double(rms.count - 1) * 0.9)]
        let speech = rms.filter { $0 > loud * 0.25 }
        guard !speech.isEmpty else { return x }
        let speechRMS = sqrt(speech.map { $0 * $0 }.reduce(0, +) / Float(speech.count))
        let peak = vDSP.maximumMagnitude(x)
        guard speechRMS > 1e-5, peak > 0 else { return x }
        let gain = min(targetRMS / speechRMS, peakCeiling / peak)
        return vDSP.multiply(gain, x)
    }

    // MARK: - Output

    private static func write(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }
}

/// Downloads (once) and holds the DeepFilterNet3 model. Weights live outside the TTS model
/// folder so the model manager's cleanup doesn't treat them as stray files.
actor Denoiser {
    static let shared = Denoiser()
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CloneVoice/Enhancer/DeepFilterNet3-MLX", isDirectory: true)

    private var loading: Task<SpeechEnhancer, Error>?

    /// Returns the model, downloading it if needed; `nil` timeout waits as long as it takes.
    nonisolated func enhancer(waitingAtMost timeout: Duration?) async throws -> SpeechEnhancer {
        let task = await loadTask()
        guard let timeout else { return try await task.value }
        return try await withThrowingTaskGroup(of: SpeechEnhancer?.self) { group in
            group.addTask { try await task.value }
            group.addTask { try await Task.sleep(for: timeout); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let enhancer = first else { throw CancellationError() }
            return enhancer
        }
    }

    /// The model keeps streaming state, so calls are serialised here.
    func enhance(_ audio: [Float], with enhancer: SpeechEnhancer) throws -> [Float] {
        let result = try enhancer.enhance(audio: audio, sampleRate: VoiceCleaner.sampleRate)
        releaseGPUMemory()
        return result
    }

    private func loadTask() -> Task<SpeechEnhancer, Error> {
        if let loading { return loading }
        let task = Task<SpeechEnhancer, Error> {
            let directory = Self.directory
            let complete = directory.appendingPathComponent(".complete")
            if !FileManager.default.fileExists(atPath: complete.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try await ResumableDownloader(
                    repo: SpeechEnhancer.defaultMLXModelId,
                    patterns: ["model.safetensors", "auxiliary.npz", "config.json"],
                    destination: directory
                ) { _ in }.run()
                FileManager.default.createFile(atPath: complete.path, contents: nil)
            }
            return try SpeechEnhancer.load(from: directory)
        }
        loading = task
        Task { await self.forgetIfFailed(task) }
        return task
    }

    /// A failed download shouldn't stick; the next recording tries again.
    private func forgetIfFailed(_ task: Task<SpeechEnhancer, Error>) async {
        if (try? await task.value) == nil, loading == task { loading = nil }
    }
}
