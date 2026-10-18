import SwiftUI

// MARK: - Confetti Burst
/// Lightweight particle burst drawn with Canvas + TimelineView.
/// Fires each time `trigger` changes. Renders nothing under Reduce Motion.
///
///     @State private var confetti = 0
///     .overlay { ConfettiBurst(trigger: confetti) }
///     confetti += 1

struct ConfettiBurst: View {
    let trigger: Int
    let colors: [Color]
    /// Where the burst originates, in unit coordinates of the view.
    let origin: UnitPoint
    let particleCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [ConfettiParticle] = []
    @State private var startDate: Date?
    @State private var cleanupTask: Task<Void, Never>?

    private let lifetime: Double = 2.4

    init(
        trigger: Int,
        colors: [Color] = ConfettiBurst.defaultColors,
        origin: UnitPoint = UnitPoint(x: 0.5, y: 0.32),
        particleCount: Int = 90
    ) {
        self.trigger = trigger
        self.colors = colors
        self.origin = origin
        self.particleCount = particleCount
    }

    static let defaultColors: [Color] = [
        Palette.brand,
        Palette.brandSecondary,
        CategoryGroup.foodDrink.color,
        CategoryGroup.information.color,
        CategoryGroup.lifestyleWellness.color,
        CategoryGroup.communication.color,
        CategoryGroup.socialMedia.color
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: startDate == nil)) { timeline in
            Canvas { context, size in
                guard let start = startDate else { return }
                let elapsed: Double = timeline.date.timeIntervalSince(start)
                guard elapsed >= 0, elapsed <= lifetime else { return }
                draw(in: &context, size: size, elapsed: elapsed)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            fire()
        }
        .onDisappear {
            cleanupTask?.cancel()
        }
    }

    // MARK: Firing

    private func fire() {
        guard !reduceMotion else { return }
        particles = ConfettiParticle.make(count: particleCount, colorCount: max(colors.count, 1))
        startDate = Date()
        cleanupTask?.cancel()
        let duration: Double = lifetime
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            startDate = nil
            particles = []
        }
    }

    // MARK: Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let originPoint = CGPoint(x: origin.x * size.width, y: origin.y * size.height)
        let gravity: Double = 900
        let fadeStart: Double = lifetime * 0.6

        for particle in particles {
            let t: Double = max(0, elapsed - particle.delay)
            guard t > 0 else { continue }

            // Simple ballistic motion with drag on the horizontal axis.
            let drag: Double = 1.0 / (1.0 + t * 1.6)
            let x: Double = Double(originPoint.x) + particle.velocity.dx * t * drag
            let y: Double = Double(originPoint.y) + particle.velocity.dy * t + 0.5 * gravity * t * t * particle.weight
            let wobble: Double = sin(t * particle.wobbleSpeed) * 8.0

            var opacity: Double = 1.0
            if elapsed > fadeStart {
                opacity = max(0, 1.0 - (elapsed - fadeStart) / (lifetime - fadeStart))
            }

            var piece = context
            piece.opacity = opacity
            piece.translateBy(x: x + wobble, y: y)
            piece.rotate(by: .degrees(particle.spin * t))
            // Fake 3D flip by squashing one axis.
            let flip: Double = abs(cos(t * particle.flipSpeed))
            piece.scaleBy(x: 1.0, y: max(0.15, flip))

            let color: Color = colors[particle.colorIndex % max(colors.count, 1)]
            let rect = CGRect(
                x: -particle.size.width / 2,
                y: -particle.size.height / 2,
                width: particle.size.width,
                height: particle.size.height
            )
            let path: Path = particle.isRound
                ? Path(ellipseIn: rect)
                : Path(roundedRect: rect, cornerRadius: 1.5)
            piece.fill(path, with: .color(color))
        }
    }
}

// MARK: - Particle

struct ConfettiParticle {
    let velocity: CGVector
    let size: CGSize
    let spin: Double
    let flipSpeed: Double
    let wobbleSpeed: Double
    let weight: Double
    let delay: Double
    let colorIndex: Int
    let isRound: Bool

    static func make(count: Int, colorCount: Int) -> [ConfettiParticle] {
        var result: [ConfettiParticle] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            // Mostly upward fan, slightly wider than a semicircle.
            let angle: Double = Double.random(in: (-Double.pi * 0.95)...(-Double.pi * 0.05))
            let speed: Double = Double.random(in: 380...880)
            let velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
            let width: Double = Double.random(in: 6...11)
            let isRound: Bool = index % 5 == 0
            let height: Double = isRound ? width : width * Double.random(in: 1.4...2.2)
            let particle = ConfettiParticle(
                velocity: velocity,
                size: CGSize(width: width, height: height),
                spin: Double.random(in: -540...540),
                flipSpeed: Double.random(in: 4...12),
                wobbleSpeed: Double.random(in: 3...9),
                weight: Double.random(in: 0.7...1.2),
                delay: Double.random(in: 0...0.12),
                colorIndex: index % max(colorCount, 1),
                isRound: isRound
            )
            result.append(particle)
        }
        return result
    }
}
