import AVFoundation
import SwiftUI

/// Interlaced cyan/gold sine strands, shown while a voice is being synthesized.
struct GeneratingWave: View {
    var isActive = true
    @Environment(\.accessibilityReduceMotion) private var isReduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || isReduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.blendMode = .plusLighter
                let strands: [(Color, Double, Double)] = [(.kpCyan, 1, 0), (.kpGold, 0.7, 2.1), (.kpTeal, 0.55, 4.2)]
                for (color, amplitude, offset) in strands {
                    var path = Path()
                    var x = 0.0
                    while x <= size.width {
                        let u = x / size.width
                        let envelope = sin(u * .pi)
                        let y = size.height / 2
                            + sin(u * .pi * 4 + t * 5 + offset) * size.height * 0.42 * amplitude * envelope
                            * (0.6 + 0.4 * sin(t * 2.3 + offset))
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                        x += 1.5
                    }
                    context.stroke(path, with: .color(color.opacity(0.9)), lineWidth: 1.4)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Scrolling mirrored bars fed by a live input level (the microphone while recording).
struct LevelWave: View {
    var level: Double
    var isActive: Bool
    @State private var history = LevelHistory()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive)) { timeline in
            Canvas { context, size in
                history.push(isActive ? level : 0, at: timeline.date)
                let count = history.values.count
                let step = size.width / CGFloat(count)
                for (i, value) in history.values.enumerated() {
                    let height = max(2, CGFloat(value) * size.height)
                    let rect = CGRect(x: CGFloat(i) * step, y: (size.height - height) / 2, width: max(1.5, step - 1.5), height: height)
                    let fade = Double(i) / Double(count)
                    let color: Color = i % 7 == 3 ? .kpGold : .kpCyan
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.25 + fade * 0.75)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private final class LevelHistory {
    private(set) var values = [Double](repeating: 0, count: 56)
    private var lastPush = Date.distantPast

    func push(_ level: Double, at date: Date) {
        guard date.timeIntervalSince(lastPush) >= 1.0 / 30 else { return }
        lastPush = date
        values.removeFirst()
        let wobble = level > 0.05 ? Double.random(in: 0.75...1.15) : 1
        values.append(min(1, level * wobble))
    }
}

/// A clip's real waveform; while it plays the played part lights up and pulses with the audio.
struct ClipWaveform: View {
    let url: URL
    @Environment(Player.self) private var player
    @State private var peaks: [Float] = []

    var body: some View {
        let isPlaying = player.isPlaying(url)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isPlaying)) { _ in
            let progress = isPlaying ? player.progress : 0
            let pulse = isPlaying ? player.level : 0
            Canvas { context, size in
                guard !peaks.isEmpty else { return }
                let step = size.width / CGFloat(peaks.count)
                for (i, peak) in peaks.enumerated() {
                    let position = Double(i) / Double(peaks.count)
                    let isPlayed = position < progress
                    let isHead = isPlaying && abs(position - progress) < 0.06
                    let boost = isHead ? 1 + pulse * 0.6 : 1
                    let height = max(2, CGFloat(Double(peak) * boost) * size.height)
                    let rect = CGRect(x: CGFloat(i) * step, y: (size.height - height) / 2, width: max(1, step - 1.2), height: height)
                    let color: Color = isPlayed ? (i % 9 == 4 ? .kpGold : .kpCyan) : .white.opacity(isPlaying ? 0.22 : 0.16)
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color))
                }
            }
        }
        .task(id: url) { peaks = await WaveformPeaks.peaks(for: url) }
        .accessibilityHidden(true)
    }
}

/// Loudness envelopes, computed off the main thread by streaming the file in small chunks.
@MainActor
enum WaveformPeaks {
    private static var cache: [URL: [Float]] = [:]
    nonisolated static let bucketCount = 48

    static func peaks(for url: URL) async -> [Float] {
        if let cached = cache[url] { return cached }
        let peaks = await Task.detached(priority: .utility) { compute(url) }.value
        if cache.count > 300 { cache.removeAll() }
        cache[url] = peaks
        return peaks
    }

    nonisolated private static func compute(_ url: URL) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url) else { return [] }
        let total = file.length
        guard total > 0 else { return [] }
        let framesPerBucket = max(1, total / AVAudioFramePosition(bucketCount))
        let chunk: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) else { return [] }
        var sums = [Float](repeating: 0, count: bucketCount)
        var counts = [Float](repeating: 0, count: bucketCount)
        var position: AVAudioFramePosition = 0
        while position < total {
            buffer.frameLength = 0
            guard (try? file.read(into: buffer, frameCount: chunk)) != nil, buffer.frameLength > 0,
                  let samples = buffer.floatChannelData?[0] else { break }
            for i in 0..<Int(buffer.frameLength) {
                let bucket = min(bucketCount - 1, Int((position + AVAudioFramePosition(i)) / framesPerBucket))
                sums[bucket] += samples[i] * samples[i]
                counts[bucket] += 1
            }
            position += AVAudioFramePosition(buffer.frameLength)
        }
        let rms = zip(sums, counts).map { $1 > 0 ? ($0 / $1).squareRoot() : 0 }
        let loudest = max(rms.max() ?? 1, 0.001)
        return rms.map { 0.1 + 0.9 * pow($0 / loudest, 1.6) }
    }
}
