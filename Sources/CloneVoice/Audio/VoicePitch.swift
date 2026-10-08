import Accelerate
import Foundation

/// Median speaking pitch, used to catch generations that drift away from the cloned speaker
/// (e.g. a male voice suddenly rendered an octave higher).
enum VoicePitch {
    static func median(of samples: [Float], sampleRate: Int) -> Float? {
        let factor = max(1, sampleRate / 8_000)
        let rate = Float(sampleRate / factor)
        let signal = stride(from: 0, to: samples.count - factor + 1, by: factor).map { start in
            var sum: Float = 0
            for offset in 0..<factor { sum += samples[start + offset] }
            return sum / Float(factor)
        }

        let frame = Int(rate * 0.04), hop = Int(rate * 0.02)
        let minLag = Int(rate / 400), maxLag = Int(rate / 60)
        guard signal.count > frame + maxLag else { return nil }
        let starts = Array(stride(from: 0, to: signal.count - frame - maxLag, by: hop))

        let energies: [Float] = starts.map { start in
            signal.withUnsafeBufferPointer { var value: Float = 0; vDSP_rmsqv($0.baseAddress! + start, 1, &value, vDSP_Length(frame)); return value }
        }
        let loudness = energies.sorted()[Int(Double(energies.count - 1) * 0.9)]
        guard loudness > 0 else { return nil }

        var pitches: [Float] = []
        signal.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for (start, energy) in zip(starts, energies) where energy > loudness * 0.3 {
                var zeroLag: Float = 0
                vDSP_dotpr(base + start, 1, base + start, 1, &zeroLag, vDSP_Length(frame))
                var bestLag = 0, best: Float = 0
                for lag in minLag...maxLag {
                    var value: Float = 0
                    vDSP_dotpr(base + start, 1, base + start + lag, 1, &value, vDSP_Length(frame))
                    if value > best { best = value; bestLag = lag }
                }
                if bestLag > 0, best > zeroLag * 0.45 { pitches.append(rate / Float(bestLag)) }
            }
        }
        guard pitches.count >= 10 else { return nil }
        return pitches.sorted()[pitches.count / 2]
    }

    static func semitones(_ pitch: Float, from reference: Float) -> Float {
        abs(12 * log2(pitch / reference))
    }
}
