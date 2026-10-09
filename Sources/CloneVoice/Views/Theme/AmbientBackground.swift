import SwiftUI

/// Night-sky backdrop with flowing cyan/gold sound ribbons and drifting stardust.
/// Calm when idle, surges while generating, and breathes with the audio that is playing.
struct AmbientBackground: View {
    @Environment(Generator.self) private var generator
    @Environment(Player.self) private var player
    @Environment(\.accessibilityReduceMotion) private var isReduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var motion = AmbientMotion()

    var body: some View {
        let isGenerating = !generator.active.isEmpty
        let isPaused = isReduceMotion || activeState == .inactive
        let isEnergetic = isGenerating || player.playingURL != nil
        ZStack {
            Color.kpBackground
            RadialGradient(colors: [.kpTeal.opacity(0.18), .clear], center: UnitPoint(x: 0.9, y: -0.1), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [.kpGold.opacity(0.06), .clear], center: UnitPoint(x: -0.1, y: 0.4), startRadius: 0, endRadius: 520)
            Canvas { context, size in Self.drawStars(&context, size: size) }
            GeometryReader { proxy in
                TimelineView(.animation(minimumInterval: isEnergetic ? 1.0 / 30 : 1.0 / 20, paused: isPaused)) { timeline in
                    let target = max(isGenerating ? 0.5 : 0, player.level)
                    Canvas { context, size in
                        motion.advance(to: timeline.date, target: target)
                        Self.drawGlow(&context, size: size, energy: motion.energy)
                        Self.drawRibbons(&context, size: size, phase: motion.phase, energy: motion.energy)
                        Self.drawDust(&context, size: size, phase: motion.phase)
                    }
                    .drawingGroup()
                }
                .frame(height: proxy.size.height * Self.bandHeight)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)))
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Mountains()
                .fill(LinearGradient(colors: [Color(red: 0.03, green: 0.2, blue: 0.22).opacity(0.55), .kpBackground], startPoint: .top, endPoint: .bottom))
                .frame(height: 90)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    /// Only the lower part of the window animates; the rest is a static gradient.
    private static let bandHeight = 0.55

    private static let ribbons: [(y: Double, amplitude: Double, frequency: Double, speed: Double, color: Color, width: Double)] = [
        (0.70, 46, 1.6, 0.9, .kpCyan, 1.1),
        (0.74, 64, 1.1, 0.6, .kpCyan, 0.7),
        (0.68, 34, 2.2, 1.1, .kpGold, 0.9),
        (0.78, 54, 1.4, 0.75, .kpGold, 0.6),
        (0.72, 80, 0.8, 0.5, .kpTeal, 0.6),
    ]

    private static func drawRibbons(_ context: inout GraphicsContext, size: CGSize, phase: Double, energy: Double) {
        context.blendMode = .plusLighter
        let lift = 1 + energy
        for ribbon in ribbons {
            for strand in 0..<3 {
                var path = Path()
                let offset = Double(strand) * 5
                var x = 0.0
                while x <= size.width + 10 {
                    let u = x / max(size.width, 1)
                    let envelope = 0.55 + 0.45 * sin(u * .pi)
                    let y = size.height * (ribbon.y - (1 - bandHeight)) / bandHeight
                        + sin(u * .pi * ribbon.frequency * 2 + phase * ribbon.speed + Double(strand) * 0.5) * ribbon.amplitude * envelope * lift
                        + sin(u * 13 + phase * ribbon.speed * 2) * 5
                        + sin(u * 47 + phase * 9) * energy * 9 * envelope
                        + offset
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += 14
                }
                let opacity = min(0.5, (0.16 - Double(strand) * 0.045) * (1 + energy * 1.6))
                context.stroke(path, with: .color(ribbon.color.opacity(opacity)), lineWidth: ribbon.width)
            }
        }
        context.blendMode = .normal
    }

    private static func drawDust(_ context: inout GraphicsContext, size: CGSize, phase: Double) {
        context.blendMode = .plusLighter
        for i in 0..<32 {
            let seed = Double(i)
            let x = fract(sin(seed * 12.9898) * 43758.5453) * size.width
            let rise = 0.008 + fract(sin(seed * 78.233) * 9631.17) * 0.02
            let y = (1 - fract(fract(sin(seed * 3.71) * 1731.3) + phase * rise)) * size.height
            let radius = 0.5 + fract(sin(seed * 5.13) * 311.7) * 1.2
            let alpha = 0.22 + 0.22 * sin(phase * 2.4 + seed)
            let color: Color = i % 3 == 0 ? .kpGold : Color(red: 0.63, green: 0.94, blue: 0.97)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(color.opacity(alpha)))
        }
        context.blendMode = .normal
    }

    private static func drawStars(_ context: inout GraphicsContext, size: CGSize) {
        for i in 0..<28 {
            let seed = Double(i) + 100
            let x = fract(sin(seed * 12.9898) * 43758.5453) * size.width
            let y = fract(sin(seed * 4.1414) * 2371.77) * size.height * (1 - bandHeight)
            let radius = 0.4 + fract(sin(seed * 5.13) * 311.7) * 0.9
            let color: Color = i % 4 == 0 ? .kpGold : .white
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(color.opacity(0.18 + 0.2 * fract(seed * 0.37))))
        }
    }

    private static func drawGlow(_ context: inout GraphicsContext, size: CGSize, energy: Double) {
        guard energy > 0.02 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height * 0.6)
        let radius = size.width * (0.35 + energy * 0.25)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.6, width: radius * 2, height: radius * 1.2)),
            with: .radialGradient(
                Gradient(colors: [.kpCyan.opacity(0.14 * energy), .kpGold.opacity(0.05 * energy), .clear]),
                center: center, startRadius: 0, endRadius: radius
            )
        )
    }

    private static func fract(_ value: Double) -> Double { value - floor(value) }
}

/// Integrates speed into phase so surges speed up smoothly instead of jumping.
private final class AmbientMotion {
    private(set) var phase = 0.0
    private(set) var energy = 0.0
    private var lastDate: Date?

    func advance(to date: Date, target: Double) {
        let dt = min(0.1, lastDate.map { date.timeIntervalSince($0) } ?? 0)
        lastDate = date
        energy += (target - energy) * min(1, dt * (target > energy ? 9 : 3))
        phase += dt * (0.35 + energy * 1.8)
    }
}

private struct Mountains: Shape {
    func path(in rect: CGRect) -> Path {
        let peaks: [(Double, Double)] = [
            (0, 0.65), (0.06, 0.4), (0.12, 0.6), (0.2, 0.25), (0.27, 0.55), (0.34, 0.35), (0.42, 0.62),
            (0.5, 0.3), (0.57, 0.58), (0.65, 0.2), (0.73, 0.52), (0.81, 0.36), (0.88, 0.6), (0.94, 0.32), (1, 0.55),
        ]
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        for (x, y) in peaks { path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
