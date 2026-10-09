import AppKit
import SwiftUI

/// The app icon's kunpeng rebuilt from a few thousand particles. Hovering parts its feathers,
/// clicking sends out a shockwave, and `energy` (e.g. microphone level) makes the wings beat.
struct KunpengParticles: View {
    var energy: Double = 0

    @Environment(\.accessibilityReduceMotion) private var isReduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var field = ParticleField()

    var body: some View {
        let isFrozen = isReduceMotion || activeState == .inactive
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isFrozen)) { timeline in
            Canvas { context, size in
                field.render(&context, size: size, date: timeline.date, energy: energy, isFrozen: isFrozen)
            }
            .drawingGroup()
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point): field.hover(point)
            case .ended: field.hover(nil)
            }
        }
        .onTapGesture(coordinateSpace: .local) { field.shock(at: $0) }
        .accessibilityHidden(true)
    }
}

private final class ParticleField {
    /// Icon pixels bright enough to keep, in 0...1 coordinates, grouped by quantized color so a frame
    /// is ~30 path fills rather than thousands.
    private struct Samples {
        var u: [Float] = []
        var v: [Float] = []
        var groups: [(color: Color, range: Range<Int>)] = []
    }

    private static var cachedSamples: Samples?

    private static func resolvedSamples() -> Samples {
        if let cachedSamples, !cachedSamples.u.isEmpty { return cachedSamples }
        let fresh = sampleIcon(from: AppBrandIcon.image())
        if !fresh.u.isEmpty { cachedSamples = fresh }
        return fresh
    }

    private var homeX: [Float] = [], homeY: [Float] = []
    private var x: [Float] = [], y: [Float] = []
    private var vx: [Float] = [], vy: [Float] = []
    private var wing: [Float] = [], phase: [Float] = []
    private var builtSize: CGSize = .zero
    private var bornAt = Date()
    private var lastDate: Date?
    private var time: Float = 0
    private var energy: Float = 0
    private var pointer: CGPoint?
    private var pointerVelocity = CGVector.zero
    private var pendingShock: CGPoint?
    private var shocks: [(center: CGPoint, start: Date)] = []

    func hover(_ point: CGPoint?) {
        if let point, let pointer {
            pointerVelocity = CGVector(dx: point.x - pointer.x, dy: point.y - pointer.y)
        }
        pointer = point
    }

    func shock(at point: CGPoint) { pendingShock = point }

    func render(_ context: inout GraphicsContext, size: CGSize, date: Date, energy target: Double, isFrozen: Bool) {
        let samples = Self.resolvedSamples()
        guard !samples.u.isEmpty, size.width > 10 else { return }
        if size != builtSize { build(size: size, isAssembled: isFrozen) }
        // A paused timeline shows this single frame, so it must be the finished bird.
        if isFrozen { settle() }

        let dt = Float(min(0.1, lastDate.map { date.timeIntervalSince($0) } ?? 1.0 / 30))
        lastDate = date
        time += dt
        energy += (Float(target) - energy) * 0.35

        if let center = pendingShock {
            pendingShock = nil
            blast(from: center)
            shocks.append((center, date))
        }

        let side = Float(min(size.width, size.height))
        let age = Float(date.timeIntervalSince(bornAt))
        let spring: Float = isFrozen ? 1 : min(0.1, 0.01 + age * 0.05)
        let radius = side * 0.2
        let radiusSquared = radius * radius
        let push = 2.2 + min(30, Float(hypot(pointerVelocity.dx, pointerVelocity.dy))) * 0.15
        pointerVelocity.dx *= 0.8
        pointerVelocity.dy *= 0.8
        let px = Float(pointer?.x ?? -9999), py = Float(pointer?.y ?? -9999)
        let beat = 1 + energy * 4
        let centerX = Float(size.width) / 2, centerY = Float(size.height) / 2

        for i in homeX.indices {
            let flutter = isFrozen ? 0 : sin(time * (1.6 + energy * 5) + phase[i]) * (1 + wing[i] * 4) * beat
            let spread = 1 + energy * 0.06 * wing[i]
            let targetX = centerX + (homeX[i] - centerX) * spread + flutter * 0.4
            let targetY = centerY + (homeY[i] - centerY) * spread + flutter
            vx[i] += (targetX - x[i]) * spring
            vy[i] += (targetY - y[i]) * spring
            let dx = x[i] - px, dy = y[i] - py
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < radiusSquared, distanceSquared > 0.01 {
                let distance = distanceSquared.squareRoot()
                let force = (1 - distance / radius) * push
                vx[i] += dx / distance * force
                vy[i] += dy / distance * force
            }
            vx[i] *= 0.8
            vy[i] *= 0.8
            x[i] += vx[i]
            y[i] += vy[i]
        }

        let halo = CGPoint(x: size.width / 2, y: size.height * 0.45)
        context.fill(
            Path(ellipseIn: CGRect(origin: .zero, size: size)),
            with: .radialGradient(
                Gradient(colors: [.kpCyan.opacity(0.12 + Double(energy) * 0.2), .kpGold.opacity(0.03), .clear]),
                center: halo, startRadius: 0, endRadius: size.width * 0.5
            )
        )

        context.blendMode = .plusLighter
        let dot = CGFloat(max(1.1, side / 230))
        for group in samples.groups {
            var path = Path()
            for i in group.range {
                path.addRect(CGRect(x: CGFloat(x[i]), y: CGFloat(y[i]), width: dot, height: dot))
            }
            context.fill(path, with: .color(group.color))
        }
        drawShocks(&context, side: CGFloat(side), date: date)
        context.blendMode = .normal
    }

    private func build(size: CGSize, isAssembled: Bool) {
        let samples = Self.resolvedSamples()
        let side = Float(min(size.width, size.height)) * 0.96
        let originX = (Float(size.width) - side) / 2, originY = (Float(size.height) - side) / 2
        let count = samples.u.count
        homeX = samples.u.map { originX + $0 * side }
        homeY = samples.v.map { originY + $0 * side }
        if isAssembled {
            x = homeX
            y = homeY
        } else {
            x = (0..<count).map { _ in Float.random(in: 0...Float(size.width)) }
            y = homeX.map { Float(size.height) * 0.5 + sin($0 * 0.05) * side * 0.12 * Float.random(in: 0...1) }
        }
        vx = Array(repeating: 0, count: count)
        vy = Array(repeating: 0, count: count)
        wing = (0..<count).map { min(1, hypot(samples.u[$0] - 0.5, samples.v[$0] - 0.5) * 2) }
        phase = (0..<count).map { samples.u[$0] * 6 + samples.v[$0] * 9 }
        builtSize = size
        bornAt = Date()
    }

    private func settle() {
        x = homeX
        y = homeY
        for i in vx.indices { vx[i] = 0; vy[i] = 0 }
    }

    private func blast(from center: CGPoint) {
        let cx = Float(center.x), cy = Float(center.y)
        for i in x.indices {
            let dx = x[i] - cx, dy = y[i] - cy
            let distance = max(1, (dx * dx + dy * dy).squareRoot())
            let force = max(0, 16 - distance * 0.07) * Float.random(in: 0.6...1.2)
            vx[i] += dx / distance * force
            vy[i] += dy / distance * force
        }
    }

    private func drawShocks(_ context: inout GraphicsContext, side: CGFloat, date: Date) {
        shocks.removeAll { date.timeIntervalSince($0.start) > 0.9 }
        for shock in shocks {
            let age = date.timeIntervalSince(shock.start) / 0.9
            for ring in 0..<3 {
                let progress = age - Double(ring) * 0.12
                guard progress > 0 else { continue }
                let r = CGFloat(progress) * side * 0.6
                let color: Color = ring == 1 ? .kpGold : .kpCyan
                context.stroke(
                    Path(ellipseIn: CGRect(x: shock.center.x - r, y: shock.center.y - r, width: r * 2, height: r * 2)),
                    with: .color(color.opacity((1 - progress) * 0.55)),
                    lineWidth: 1.4
                )
            }
        }
    }

    private static func sampleIcon(from image: NSImage?) -> Samples {
        let n = 100
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return Samples() }
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let isDrawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard isDrawn else { return Samples() }

        // The icon's rounded-square frame glows; skip it so only the bird remains.
        let inset = Int(Double(n) * 0.11)
        var buckets: [Int: [(Float, Float)]] = [:]
        for row in inset..<(n - inset) {
            for column in inset..<(n - inset) {
                let i = (row * n + column) * 4
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let luminance = 0.3 * Double(r) + 0.59 * Double(g) + 0.11 * Double(b)
                guard luminance >= 90 else { continue }
                let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
                let u = (Float(column) + Float.random(in: 0...0.6)) / Float(n)
                let v = (Float(row) + Float.random(in: 0...0.6)) / Float(n)
                buckets[key, default: []].append((u, v))
            }
        }

        var samples = Samples()
        for (key, points) in buckets.sorted(by: { $0.key < $1.key }) {
            let r = Double((key >> 6) & 7), g = Double((key >> 3) & 7), b = Double(key & 7)
            let luminance = (0.3 * r + 0.59 * g + 0.11 * b) * 32
            let start = samples.u.count
            for (u, v) in points {
                samples.u.append(u)
                samples.v.append(v)
            }
            let color = Color(red: min(1, (r * 32 + 40) / 255), green: min(1, (g * 32 + 40) / 255), blue: min(1, (b * 32 + 40) / 255))
            samples.groups.append((color.opacity(min(1, luminance / 180)), start..<samples.u.count))
        }
        return samples
    }
}
