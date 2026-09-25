import CoreGraphics
import Foundation
import Testing
import simd
@testable import OWCore
@testable import OWFormats
@testable import OWScene

@Suite("Scene camera & math")
struct SceneCameraTests {
    let general = SceneGeneral(width: 1920, height: 1080, cameraParallax: true, parallaxAmount: 0.5, parallaxDelay: 0.1, parallaxMouseInfluence: 0.5)

    @Test("fill crops, fit letterboxes, stretch keeps the scene")
    func visibleRects() {
        let fill = SceneCamera(general: general, fill: .fill)
        let (low, high) = fill.visibleRect(viewport: CGSize(width: 1000, height: 1000))
        #expect(low == SIMD2(420, 0))
        #expect(high == SIMD2(1500, 1080))
        let fit = SceneCamera(general: general, fill: .fit)
        let (fitLow, fitHigh) = fit.visibleRect(viewport: CGSize(width: 1000, height: 1000))
        #expect(fitLow == SIMD2(0, -420))
        #expect(fitHigh == SIMD2(1920, 1500))
        let stretch = SceneCamera(general: general, fill: .stretch)
        #expect(stretch.visibleRect(viewport: CGSize(width: 10, height: 1000)).1 == SIMD2(1920, 1080))
        #expect(fill.visibleRect(viewport: .zero).1 == SIMD2(1920, 1080))
    }

    @Test("projection maps scene corners to clip space")
    func projection() {
        let camera = SceneCamera(general: general, fill: .stretch)
        let matrix = camera.projection(viewport: CGSize(width: 1920, height: 1080))
        let corner = matrix * SIMD4<Float>(1920, 1080, 0, 1)
        #expect(abs(corner.x - 1) < 1e-5 && abs(corner.y - 1) < 1e-5)
        let origin = matrix * SIMD4<Float>(0, 0, 0, 1)
        #expect(abs(origin.x + 1) < 1e-5 && abs(origin.y + 1) < 1e-5)
    }

    @Test("parallax eases toward the cursor and scales with depth")
    func parallax() {
        var camera = SceneCamera(general: general, fill: .fill)
        #expect(camera.parallaxOffset(depth: Vec2(1, 1)) == .zero)
        camera.updateCursor(target: SIMD2(1, 1), delta: 0.1)
        #expect(camera.cursor.x > 0.5 && camera.cursor.x < 1)
        for _ in 0 ..< 100 { camera.updateCursor(target: SIMD2(5, 5), delta: 0.1) }
        #expect(abs(camera.cursor.x - 1) < 0.001)
        let deep = camera.parallaxOffset(depth: Vec2(2, 2))
        let shallow = camera.parallaxOffset(depth: Vec2(1, 1))
        #expect(abs(deep.x - shallow.x * 2) < 0.01)
        var off = SceneCamera(general: SceneGeneral(), fill: .fill)
        off.updateCursor(target: SIMD2(1, 1), delta: 1)
        #expect(off.cursor == SIMD2(0.5, 0.5))
        #expect(off.parallaxOffset(depth: Vec2(1, 1)) == .zero)
    }

    @Test("model matrix places a unit quad")
    func model() {
        let matrix = SceneMath.model(origin: SIMD2(10, 20), size: SIMD2(4, 2), scale: SIMD2(1, 1), angle: .pi / 2)
        let corner = matrix * SIMD4<Float>(0.5, 0, 0, 1)
        #expect(abs(corner.x - 10) < 1e-4 && abs(corner.y - 22) < 1e-4)
    }
}

@Suite("Effects & particles")
struct EffectParticleTests {
    @Test("maps effect constants with aliases, defaults and user bindings")
    func effects() {
        let effects = [
            SceneEffect(name: "scroll", file: "", constants: ["speed": SceneValue([0.2, 0.1])]),
            SceneEffect(name: "shake", file: "", constants: ["strength": SceneValue([0.5], userKey: "shake")]),
            SceneEffect(name: "waterripple", file: ""),
            SceneEffect(name: "waterwaves", file: ""),
            SceneEffect(name: "pulse", file: "", constants: ["amount": SceneValue([0.3])]),
            SceneEffect(name: "tint", file: "", constants: ["color": SceneValue([1, 0, 0])]),
            SceneEffect(name: "opacity", file: "", constants: ["alpha": SceneValue([0.5])]),
            SceneEffect(name: "blur", file: "", constants: ["scale": SceneValue([2])]),
            SceneEffect(name: "godrays", file: ""),
            SceneEffect(name: "opacity", file: "", visible: SceneValue([0]), constants: ["alpha": SceneValue([0])]),
        ]
        let params = EffectRegistry.parameters(for: effects, values: ["shake": .number(0.9)])
        #expect(params.scroll == SIMD2(0.2, 0.1))
        #expect(params.shakeStrength == 0.9)
        #expect(params.rippleStrength == 0.1)
        #expect(params.waveStrength == 0.1)
        #expect(params.pulseAmount == 0.3)
        #expect(params.tint == SIMD3(1, 0, 0) && params.tintAmount == 1)
        #expect(params.opacity == 0.5)
        #expect(params.blurRadius == 2)
        #expect(params.isAnimated)
        #expect(!EffectParameters().isAnimated)
        #expect(!EffectRegistry.known.contains("godrays"))
    }

    private func system(maxCount: Int = 50, startTime: Float = 0) -> ParticleSystemDocument {
        var initializer = ParticleInitializerSpec()
        initializer.lifetime = FloatRange(1, 1)
        initializer.velocityMin = Vec3(10, 0, 0)
        initializer.velocityMax = Vec3(10, 0, 0)
        var operators = ParticleOperatorSpec()
        operators.fadeInTime = 0.2
        operators.fadeOutTime = 0.5
        operators.sizeStart = 1
        operators.sizeEnd = 0
        operators.gravity = Vec3(0, -10, 0)
        let emitter = ParticleEmitterSpec(
            shape: .box, rate: 10, origin: .zero, distanceMin: .zero, distanceMax: Vec3(5, 5, 0),
            directions: Vec3(1, 1, 0), speed: FloatRange(0, 0)
        )
        let sphere = ParticleEmitterSpec(
            shape: .sphere, rate: 10, origin: .zero, distanceMin: Vec3(1, 1, 0), distanceMax: Vec3(2, 2, 0),
            directions: Vec3(1, 1, 0), speed: FloatRange(1, 2)
        )
        return ParticleSystemDocument(
            emitters: [emitter, sphere], initializer: initializer, operators: operators, material: nil,
            maxCount: maxCount, startTime: startTime, unsupported: []
        )
    }

    @Test("simulation is deterministic, respects caps and lifetimes")
    func simulation() {
        var first = ParticleSimulator(system: system(), origin: SIMD2(100, 100), seed: 7)
        var second = ParticleSimulator(system: system(), origin: SIMD2(100, 100), seed: 7)
        for _ in 0 ..< 15 {
            first.update(delta: 1 / 30)
            second.update(delta: 1 / 30)
        }
        #expect(first.particles == second.particles)
        #expect(first.particles.count == 10)
        #expect(first.instanceData().count == first.particles.count * 8)
        for _ in 0 ..< 90 { first.update(delta: 1 / 30) }
        #expect(first.particles.allSatisfy { $0.age < $0.lifetime })
        #expect(first.particles.count <= 21)
        var capped = ParticleSimulator(system: system(maxCount: 3), origin: .zero)
        capped.update(delta: 0.25)
        capped.update(delta: 0.25)
        #expect(capped.particles.count == 3)
        let warmed = ParticleSimulator(system: system(startTime: 1), origin: .zero)
        #expect(!warmed.particles.isEmpty)
    }

    @Test("fade and size curves")
    func curves() {
        let simulator = ParticleSimulator(system: system(), origin: .zero)
        #expect(simulator.fade(progress: 0) == 0)
        #expect(simulator.fade(progress: 0.1) == 0.5)
        #expect(simulator.fade(progress: 0.4) == 1)
        #expect(abs(simulator.fade(progress: 0.75) - 0.5) < 1e-5)
        #expect(simulator.sizeMultiplier(progress: 0.25) == 0.75)
    }

    @Test("layer uniforms pack to the shader layout")
    func packing() {
        var effect = EffectParameters()
        effect.blurRadius = 3
        let packed = LayerUniformPacker.pack(
            mvp: matrix_identity_float4x4, color: SIMD4(1, 2, 3, 4), uvRect: SIMD4(0, 0, 1, 1), effect: effect, time: 9
        )
        #expect(packed.count == LayerUniformPacker.floatCount)
        #expect(packed[0] == 1 && packed[5] == 1)
        #expect(Array(packed[16 ..< 20]) == [1, 2, 3, 4])
        #expect(packed[40] == 9 && packed[43] == 3)
    }
}
