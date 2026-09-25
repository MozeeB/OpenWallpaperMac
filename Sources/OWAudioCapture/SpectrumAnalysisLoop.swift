import Foundation
import OWAudioAnalysis
import OWCore

/// Drains the ring buffer at a fixed rate on a utility queue and emits spectra.
///
/// Also reports sustained digital silence (all-zero samples for `silenceSeconds`), which is how a
/// denied audio-capture permission manifests; Core Audio offers no preflight API for it.
final class SpectrumAnalysisLoop: @unchecked Sendable {
    let rate: Double
    let silenceSeconds: Double
    private let ring: SPSCRingBuffer
    private let pipeline: SpectrumPipeline
    private let onSpectrum: @Sendable (AudioSpectrum) -> Void
    private let onSilence: @Sendable () -> Void
    private let queue = DispatchQueue(label: "OpenWallpaperMac.audio.analysis", qos: .utility)
    private var timer: (any DispatchSourceTimer)?
    private var window: [Float]
    private var incoming: [Float]
    private var silentTicks = 0
    private var reportedSilence = false

    init?(
        ring: SPSCRingBuffer, sampleRate: Double, rate: Double = 30, silenceSeconds: Double = 5,
        onSpectrum: @escaping @Sendable (AudioSpectrum) -> Void, onSilence: @escaping @Sendable () -> Void
    ) {
        guard let pipeline = SpectrumPipeline(fftSize: 2048, sampleRate: sampleRate) else { return nil }
        self.ring = ring
        self.pipeline = pipeline
        self.rate = rate
        self.silenceSeconds = silenceSeconds
        self.onSpectrum = onSpectrum
        self.onSilence = onSilence
        window = [Float](repeating: 0, count: pipeline.fftSize * 2)
        incoming = [Float](repeating: 0, count: pipeline.fftSize * 4)
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = 1 / rate
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        ring.drain()
        pipeline.reset()
    }

    /// One analysis step; internal for tests.
    func tick() {
        let got = incoming.withUnsafeMutableBufferPointer { ring.read(into: $0) }
        if got > 0 {
            // Slide the window left and append the newest samples (stereo interleaved).
            let keep = max(window.count - got, 0)
            if keep > 0 { window.replaceSubrange(0 ..< keep, with: window[(window.count - keep)...]) }
            let start = max(got - window.count, 0)
            window.replaceSubrange(keep ..< window.count, with: incoming[start ..< got])
        }
        trackSilence(receivedSamples: got)
        let bands = pipeline.process(interleaved: window)
        onSpectrum(AudioSpectrum(left: bands.left, right: bands.right))
    }

    private func trackSilence(receivedSamples: Int) {
        let silent = receivedSamples == 0 || incoming.prefix(receivedSamples).allSatisfy { $0 == 0 }
        silentTicks = silent ? silentTicks + 1 : 0
        if silent, !reportedSilence, Double(silentTicks) >= silenceSeconds * rate {
            reportedSilence = true
            onSilence()
        }
        if !silent { reportedSilence = false }
    }
}
