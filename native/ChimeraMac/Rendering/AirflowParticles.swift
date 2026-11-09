import Foundation
import simd

final class AirflowParticleSystem {
    private enum Branch {
        case oral
        case nasal
    }

    private struct Particle {
        var s: Double
        var u: Double
        var v: Double
        var life: Double
        var nasalProgress: Double
        var branch: Branch
        var previous: SIMD3<Float>?
    }

    private var particles: [Particle] = []
    private var seed: UInt64 = 0x6a09e667f3bcc909

    init(count: Int = 96) {
        particles = (0..<count).map { _ in
            Particle(
                s: random() * 0.8,
                u: random() * 2 - 1,
                v: random() * 2 - 1,
                life: 0.6 + random() * 0.8,
                nasalProgress: 0,
                branch: .oral,
                previous: nil
            )
        }
    }

    func reset() {
        for index in particles.indices {
            particles[index].previous = nil
            particles[index].s = random() * 0.8
            particles[index].life = 0.6 + random() * 0.8
            particles[index].nasalProgress = 0
        }
    }

    func lines(frame: HumanFrame, telemetry: VoiceTelemetry, bodyScale: Double, dt: Double) -> [LineStrip3D] {
        let areas = telemetry.phAreas + telemetry.orAreas
        let flow = telemetry.flow
        guard frame.grid.count > 1, areas.count == flow.count, !areas.isEmpty else { return [] }
        let lipS = max(0.1, frame.lipS)
        let velumPort = max(0, telemetry.velumPort > 0 ? telemetry.velumPort : frame.velumPort)
        var output: [LineStrip3D] = []

        for index in particles.indices {
            var particle = particles[index]
            let sampleIndex = nearestIndex(frame.grid, s: particle.s, count: areas.count)
            let volumeFlow = sampleIndex < flow.count ? flow[sampleIndex] : 0
            let oralArea = sampleIndex < areas.count ? areas[sampleIndex] : 0
            let oralVelocity = volumeFlow / max(0.05, oralArea)
            let nasalVelocity = velumPort > 0.02 ? volumeFlow / max(0.05, velumPort) : 0
            let velocity = particle.branch == .nasal && particle.s >= telemetry.phLen ? nasalVelocity : oralVelocity
            let speed = velocity == 0 ? 0 : (velocity < 0 ? -1 : 1) * 2.2 * log1p(abs(velocity) / 30)
            particle.life -= dt * 0.25

            if abs(velocity) >= 3 {
                particle.s += speed * dt
                if particle.branch == .nasal && particle.s >= telemetry.phLen {
                    particle.nasalProgress += abs(speed) * dt / max(2, 11.4 * bodyScale)
                }
            }

            if particle.s > lipS || particle.s < 0 || particle.life <= 0 || particle.nasalProgress > 1 {
                respawn(&particle, velumPort: velumPort)
                particles[index] = particle
                continue
            }
            guard abs(velocity) >= 3,
                  let position = particle.branch == .nasal && particle.s >= telemetry.phLen
                    ? nasalPoint(frame: frame, progress: particle.nasalProgress, lateral: particle.v, bodyScale: bodyScale)
                    : oralPoint(frame: frame, s: particle.s, u: particle.u, v: particle.v, bodyScale: bodyScale) else {
                particle.previous = nil
                particles[index] = particle
                continue
            }
            if let previous = particle.previous {
                let strength = min(1, abs(speed) / 6) * min(1, particle.life)
                output.append(LineStrip3D(
                    points: [previous, position],
                    color: SIMD4<Float>(1, 0.78 + Float(strength) * 0.16, 0.42 + Float(strength) * 0.25, 0.12 + Float(strength) * 0.5),
                    width: 0.75 + Float(strength) * 0.55
                ))
            }
            particle.previous = position
            particles[index] = particle
        }
        return output
    }

    private func respawn(_ particle: inout Particle, velumPort: Double) {
        particle.s = random() * 0.8
        particle.u = random() * 2 - 1
        particle.v = random() * 2 - 1
        particle.life = 0.6 + random() * 0.8
        particle.nasalProgress = 0
        let nasalShare = velumPort > 0.02 ? min(0.65, velumPort / (velumPort + 1.2)) : 0
        particle.branch = random() < nasalShare ? .nasal : .oral
        particle.previous = nil
    }

    private func nearestIndex(_ grid: [GridSample], s: Double, count: Int) -> Int {
        var best = 0
        var distance = Double.infinity
        for index in 0..<min(grid.count, count) {
            let candidate = abs(grid[index].s - s)
            if candidate < distance {
                best = index
                distance = candidate
            }
        }
        return best
    }

    private func oralPoint(frame: HumanFrame, s: Double, u: Double, v: Double, bodyScale: Double) -> SIMD3<Float>? {
        let grid = frame.grid
        if s <= grid[0].s {
            let t = max(0, s / max(0.01, grid[0].s))
            let x = frame.glottis.x + (grid[0].mid.x - frame.glottis.x) * t + u * 0.18 * bodyScale
            let y = frame.glottis.y + (grid[0].mid.y - frame.glottis.y) * t
            return SIMD3<Float>(Float(x), Float(y), Float(v * 0.4 * bodyScale))
        }
        guard s < grid[grid.count - 1].s else { return nil }
        var upper = 1
        while upper < grid.count - 1 && grid[upper].s < s { upper += 1 }
        let lower = upper - 1
        let t = (s - grid[lower].s) / max(0.000001, grid[upper].s - grid[lower].s)
        let center = Vec2(
            x: grid[lower].mid.x + (grid[upper].mid.x - grid[lower].mid.x) * t,
            y: grid[lower].mid.y + (grid[upper].mid.y - grid[lower].mid.y) * t
        )
        let inner = Vec2(
            x: grid[lower].inner.x + (grid[upper].inner.x - grid[lower].inner.x) * t,
            y: grid[lower].inner.y + (grid[upper].inner.y - grid[lower].inner.y) * t
        )
        let outer = Vec2(
            x: grid[lower].outer.x + (grid[upper].outer.x - grid[lower].outer.x) * t,
            y: grid[lower].outer.y + (grid[upper].outer.y - grid[lower].outer.y) * t
        )
        let dx = outer.x - inner.x
        let dy = outer.y - inner.y
        let gap = max(0.001, hypot(dx, dy))
        let area = grid[lower].area + (grid[upper].area - grid[lower].area) * t
        let halfWidth = min(4 * bodyScale, max(0.008, area / (.pi * gap)))
        return SIMD3<Float>(
            Float(center.x + dx / gap * gap * 0.5 * u * 0.82),
            Float(center.y + dy / gap * gap * 0.5 * u * 0.82),
            Float(halfWidth * v * 0.82)
        )
    }

    private func nasalPoint(frame: HumanFrame, progress: Double, lateral: Double, bodyScale: Double) -> SIMD3<Float>? {
        let path = frame.nasalCavity
        guard path.count > 1 else { return nil }
        var lengths = [0.0]
        for index in 1..<path.count {
            lengths.append(lengths[index - 1] + hypot(path[index].x - path[index - 1].x, path[index].y - path[index - 1].y))
        }
        let target = min(1, max(0, progress)) * (lengths.last ?? 0)
        var index = 1
        while index < path.count - 1 && lengths[index] < target { index += 1 }
        let t = (target - lengths[index - 1]) / max(0.000001, lengths[index] - lengths[index - 1])
        let x = path[index - 1].x + (path[index].x - path[index - 1].x) * t
        let y = path[index - 1].y + (path[index].y - path[index - 1].y) * t
        return SIMD3<Float>(Float(x), Float(y), Float(lateral * 0.75 * bodyScale))
    }

    private func random() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }
}
