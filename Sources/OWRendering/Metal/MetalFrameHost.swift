import MetalKit
import OWCore
import QuartzCore

/// Detects runaway GPU work: an error status, or several consecutive over-budget frames.
public struct GPUWatchdog: Sendable {
    public let frameBudget: Double
    public let strikesAllowed: Int
    public private(set) var strikes = 0

    public init(frameBudget: Double = 0.25, strikesAllowed: Int = 3) {
        self.frameBudget = frameBudget
        self.strikesAllowed = strikesAllowed
    }

    /// Returns `true` when the renderer should be disabled.
    public mutating func record(gpuTime: Double, failed: Bool) -> Bool {
        if failed { return true }
        strikes = gpuTime > frameBudget ? strikes + 1 : 0
        return strikes >= strikesAllowed
    }
}

/// Hosts a `FrameDrawing` in an `MTKView` with frame-rate capping, pausing and a GPU watchdog.
///
/// Performance: the view is opaque, uses at most two drawables, renders at `renderScale` of native
/// resolution, and its display link stops entirely while paused (0% CPU).
@MainActor
public final class MetalFrameHost: NSObject, MTKViewDelegate {
    public let view: MTKView
    public var drawer: (any FrameDrawing)?
    public var onFailure: ((RenderError) -> Void)?
    public private(set) var framesRendered = 0

    private let context: MetalContext
    private var watchdog = GPUWatchdog()
    private var lastTimestamp: CFTimeInterval?
    private var renderScale: CGFloat = 1
    private var failed = false

    public init(context: MetalContext) {
        self.context = context
        view = MTKView(frame: .zero, device: context.device)
        super.init()
        view.colorPixelFormat = MetalContext.pixelFormat
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = false
        view.layer?.isOpaque = true
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        view.delegate = self
    }

    public func configure(renderScale scale: CGFloat) {
        renderScale = min(max(scale, 0.25), 1)
        updateDrawableSize()
    }

    public func setPlayback(_ state: PlaybackState) {
        switch state {
        case .playing(let fps) where !failed:
            view.preferredFramesPerSecond = max(fps, 1)
            lastTimestamp = nil
            view.isPaused = false
        default:
            view.isPaused = true
        }
    }

    public var isRunning: Bool { !view.isPaused }

    /// Draws a single frame (e.g. after a property change while paused).
    public func redraw() {
        guard view.isPaused, !failed else { return }
        view.draw()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func updateDrawableSize() {
        let scale = (view.window?.backingScaleFactor ?? 2) * renderScale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        if size.width > 0, size.height > 0, view.drawableSize != size { view.drawableSize = size }
    }

    public func draw(in view: MTKView) {
        updateDrawableSize()
        guard let drawer, !failed,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = context.queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        pass.colorAttachments[0].clearColor = drawer.clearColor
        let now = CACurrentMediaTime()
        let delta = lastTimestamp.map { Float(now - $0) } ?? 1 / Float(max(view.preferredFramesPerSecond, 1))
        lastTimestamp = now
        drawer.encodeFrame(into: encoder, size: view.drawableSize, delta: delta)
        encoder.endEncoding()
        buffer.addCompletedHandler { [weak self] completed in
            let gpuTime = completed.gpuEndTime - completed.gpuStartTime
            let isError = completed.status == .error
            Task { @MainActor in self?.recordCompletion(gpuTime: gpuTime, failed: isError) }
        }
        buffer.present(drawable)
        buffer.commit()
        framesRendered += 1
    }

    func recordCompletion(gpuTime: Double, failed didFail: Bool) {
        guard !failed, watchdog.record(gpuTime: gpuTime, failed: didFail) else { return }
        failed = true
        view.isPaused = true
        onFailure?(.gpuHang)
    }

    public func snapshot(maxDimension: Int = 1920) throws(RenderError) -> CGImage {
        guard let drawer else { throw .notLoaded }
        let size = view.drawableSize == .zero ? CGSize(width: 1280, height: 720) : view.drawableSize
        let ratio = min(1, CGFloat(maxDimension) / max(size.width, size.height))
        let bitmap = try OffscreenRenderer.render(
            drawer, context: context, width: Int(size.width * ratio), height: Int(size.height * ratio), delta: 0
        )
        guard let image = bitmap.makeCGImage() else { throw .snapshotFailed }
        return image
    }

    public func teardown() {
        view.isPaused = true
        view.delegate = nil
        drawer = nil
        view.removeFromSuperview()
    }
}
