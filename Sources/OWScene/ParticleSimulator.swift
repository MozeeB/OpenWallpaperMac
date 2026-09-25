import Foundation
import OWFormats

public struct Particle: Equatable, Sendable {
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    public var age: Float
    public let lifetime: Float
    public let size: Float
    public let color: SIMD3<Float>
    public let alpha: Float
    public var rotation: Float
    public let angularVelocity: Float

    public var progress: Float { lifetime > 0 ? min(age / lifetime, 1) : 1 }
}

/// Deterministic CPU particle simulation (seeded), rendered as instanced quads.
public struct ParticleSimulator: Sendable {
    public let system: ParticleSystemDocument
    public let origin: SIMD2<Float>
    public private(set) var particles: [Particle] = []
    private var rng: SplitMix64
    private var emitAccumulators: [Float]

    public init(system: ParticleSystemDocument, origin: SIMD2<Float>, seed: UInt64 = 1) {
        self.system = system
        self.origin = origin
        rng = SplitMix64(seed: seed)
        emitAccumulators = Array(repeating: 0, count: system.emitters.count)
        particles.reserveCapacity(system.maxCount)
        if system.startTime > 0 { prewarm(seconds: min(system.startTime, 10)) }
    }

    private mutating func prewarm(seconds: Float) {
        let step: Float = 1 / 30
        for _ in 0 ..< Int(seconds / step) { update(delta: step) }
    }

    public mutating func update(delta: Float) {
        let dt = min(max(delta, 0), 0.25)
        age(dt)
        emit(dt)
    }

    private mutating func age(_ dt: Float) {
        let ops = system.operators
        let gravity = SIMD2(ops.gravity.x, ops.gravity.y)
        let damping = max(0, 1 - ops.drag * dt)
        // In place: no per-frame allocation.
        for index in particles.indices {
            particles[index].age += dt
            particles[index].velocity = (particles[index].velocity + gravity * dt) * damping
            particles[index].position += particles[index].velocity * dt
            particles[index].rotation += particles[index].angularVelocity * dt
        }
        particles.removeAll { $0.age >= $0.lifetime }
    }

    private mutating func emit(_ dt: Float) {
        for (index, emitter) in system.emitters.enumerated() {
            emitAccumulators[index] += emitter.rate * dt
            while emitAccumulators[index] >= 1 {
                emitAccumulators[index] -= 1
                guard particles.count < system.maxCount else { continue }
                particles.append(spawn(emitter))
            }
        }
    }

    private mutating func spawn(_ emitter: ParticleEmitterSpec) -> Particle {
        let spec = system.initializer
        let offset = spawnOffset(emitter)
        let speed = random(emitter.speed)
        let direction = randomUnit() * SIMD2(emitter.directions.x, emitter.directions.y)
        let velocity = SIMD2(
            random(FloatRange(spec.velocityMin.x, spec.velocityMax.x)),
            random(FloatRange(spec.velocityMin.y, spec.velocityMax.y))
        ) + direction * speed
        return Particle(
            position: origin + SIMD2(emitter.origin.x, emitter.origin.y) + offset,
            velocity: velocity, age: 0, lifetime: max(random(spec.lifetime), 0.01),
            size: max(random(spec.size), 0),
            color: SIMD3(
                random(FloatRange(spec.colorMin.x, spec.colorMax.x)),
                random(FloatRange(spec.colorMin.y, spec.colorMax.y)),
                random(FloatRange(spec.colorMin.z, spec.colorMax.z))
            ),
            alpha: random(spec.alpha), rotation: random(spec.rotation), angularVelocity: random(spec.angularVelocity)
        )
    }

    private mutating func spawnOffset(_ emitter: ParticleEmitterSpec) -> SIMD2<Float> {
        switch emitter.shape {
        case .box:
            return SIMD2(
                random(FloatRange(-emitter.distanceMax.x, emitter.distanceMax.x)),
                random(FloatRange(-emitter.distanceMax.y, emitter.distanceMax.y))
            )
        case .sphere:
            let radius = random(FloatRange(emitter.distanceMin.x, emitter.distanceMax.x))
            return randomUnit() * radius
        }
    }

    private mutating func random(_ range: FloatRange) -> Float {
        range.lower + (range.upper - range.lower) * rng.nextUnit()
    }

    private mutating func randomUnit() -> SIMD2<Float> {
        let angle = rng.nextUnit() * 2 * .pi
        return SIMD2(cos(angle), sin(angle))
    }

    /// Alpha multiplier from the alpha-fade operator at a given lifetime progress.
    public func fade(progress: Float) -> Float {
        let ops = system.operators
        var value: Float = 1
        if ops.fadeInTime > 0, progress < ops.fadeInTime { value = progress / ops.fadeInTime }
        let fadeOutStart = 1 - ops.fadeOutTime
        if ops.fadeOutTime > 0, progress > fadeOutStart { value = min(value, (1 - progress) / ops.fadeOutTime) }
        return max(min(value, 1), 0)
    }

    public func sizeMultiplier(progress: Float) -> Float {
        let ops = system.operators
        return ops.sizeStart + (ops.sizeEnd - ops.sizeStart) * progress
    }

    /// Per-instance data: x, y, size, rotation, r, g, b, a.
    public func instanceData() -> [Float] {
        var output: [Float] = []
        writeInstanceData(into: &output)
        return output
    }

    /// Reuses `buffer`'s storage across frames.
    public func writeInstanceData(into buffer: inout [Float]) {
        buffer.removeAll(keepingCapacity: true)
        buffer.reserveCapacity(particles.count * 8)
        for particle in particles {
            let progress = particle.progress
            buffer.append(particle.position.x)
            buffer.append(particle.position.y)
            buffer.append(particle.size * sizeMultiplier(progress: progress))
            buffer.append(particle.rotation)
            buffer.append(particle.color.x)
            buffer.append(particle.color.y)
            buffer.append(particle.color.z)
            buffer.append(particle.alpha * fade(progress: progress))
        }
    }
}

/// Small deterministic generator so particle layouts are reproducible in tests and goldens.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}
