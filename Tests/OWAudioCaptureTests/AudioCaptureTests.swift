import CoreAudio
import Foundation
import Testing
@testable import OWAudioAnalysis
@testable import OWAudioCapture
@testable import OWCore

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var spectra: [AudioSpectrum] = []
    private(set) var silenceCount = 0

    func add(_ spectrum: AudioSpectrum) { lock.withLock { spectra.append(spectrum) } }
    func silence() { lock.withLock { silenceCount += 1 } }
    var last: AudioSpectrum? { lock.withLock { spectra.last } }
    var count: Int { lock.withLock { spectra.count } }
}

private func stereoSine(frequency: Double, frames: Int, sampleRate: Double = 48_000) -> [Float] {
    (0 ..< frames).flatMap { frame -> [Float] in
        let value = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate))
        return [value, value * 0.5]
    }
}

@Suite("Spectrum analysis loop")
struct AnalysisLoopTests {
    @Test("turns ring samples into spectra")
    func spectra() throws {
        let ring = SPSCRingBuffer(capacity: 48_000)
        let collector = Collector()
        let loop = try #require(SpectrumAnalysisLoop(
            ring: ring, sampleRate: 48_000, onSpectrum: collector.add, onSilence: collector.silence
        ))
        ring.write(stereoSine(frequency: 440, frames: 4096))
        loop.tick()
        loop.tick()
        let spectrum = try #require(collector.last)
        #expect(spectrum.left.max()! > 0.5)
        #expect(spectrum.left.max()! >= spectrum.right.max()!)
        #expect(collector.silenceCount == 0)
    }

    @Test("reports sustained silence once, re-arms on sound")
    func silence() throws {
        let ring = SPSCRingBuffer(capacity: 48_000)
        let collector = Collector()
        let loop = try #require(SpectrumAnalysisLoop(
            ring: ring, sampleRate: 48_000, rate: 10, silenceSeconds: 0.5,
            onSpectrum: collector.add, onSilence: collector.silence
        ))
        for _ in 0 ..< 12 {
            ring.write([Float](repeating: 0, count: 256))
            loop.tick()
        }
        #expect(collector.silenceCount == 1)
        ring.write(stereoSine(frequency: 1000, frames: 512))
        loop.tick()
        for _ in 0 ..< 6 { loop.tick() }
        #expect(collector.silenceCount == 2)
    }

    @Test("timer-driven start and stop")
    func timer() async throws {
        let ring = SPSCRingBuffer(capacity: 4096)
        let collector = Collector()
        let loop = try #require(SpectrumAnalysisLoop(
            ring: ring, sampleRate: 48_000, rate: 100, onSpectrum: collector.add, onSilence: collector.silence
        ))
        loop.start()
        loop.start()
        try await Task.sleep(for: .milliseconds(150))
        loop.stop()
        #expect(collector.count > 3)
        #expect(SpectrumAnalysisLoop(ring: ring, sampleRate: 0, onSpectrum: { _ in }, onSilence: {}) == nil)
    }
}

@Suite("Real-time copy")
struct RealtimeCopyTests {
    @Test("copies interleaved and planar buffers into the ring")
    func copy() {
        let ring = SPSCRingBuffer(capacity: 64)
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: 32)
        defer { scratch.deallocate() }

        var interleaved: [Float] = [1, 2, 3, 4]
        interleaved.withUnsafeMutableBytes { raw in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                mNumberChannels: 2, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress
            ))
            ProcessTapCapture.copy(&list, into: ring, scratch: scratch, capacity: 32)
        }
        #expect(ring.read(count: 10) == [1, 2, 3, 4])

        var left: [Float] = [1, 3]
        var right: [Float] = [2, 4]
        let planar = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(planar.unsafeMutablePointer) }
        left.withUnsafeMutableBytes { l in
            right.withUnsafeMutableBytes { r in
                planar[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(l.count), mData: l.baseAddress)
                planar[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(r.count), mData: r.baseAddress)
                ProcessTapCapture.copy(planar.unsafePointer, into: ring, scratch: scratch, capacity: 32)
            }
        }
        #expect(ring.read(count: 10) == [1, 2, 3, 4])

        var empty = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: 0, mData: nil))
        ProcessTapCapture.copy(&empty, into: ring, scratch: scratch, capacity: 32)
        #expect(ring.availableToRead == 0)
    }
}

@Suite("Core Audio support")
@MainActor
struct CoreAudioSupportTests {
    @Test("helpers")
    func helpers() throws {
        #expect(CoreAudioSupport.fourCC(kAudioHardwarePropertyDefaultOutputDevice) == "dOut")
        #expect(throws: AudioCaptureError.osStatus(operation: "x", code: -1)) { try CoreAudioSupport.check(-1, "x") }
        #expect(AudioCaptureService.isSupported)
        if let device = try? CoreAudioSupport.defaultOutputDevice() {
            #expect(!(try CoreAudioSupport.deviceUID(device)).isEmpty)
        }
        #expect(throws: AudioCaptureError.self) { try CoreAudioSupport.tapFormat(AudioObjectID(kAudioObjectUnknown)) }
    }

    @Test("service stop is idempotent without start")
    func idempotent() {
        let service = AudioCaptureService()
        service.stop()
        #expect(!service.isRunning)
    }

    @Test("live system-audio tap (opt-in: OW_LIVE_AUDIO=1)",
          .enabled(if: ProcessInfo.processInfo.environment["OW_LIVE_AUDIO"] == "1"))
    func live() async throws {
        let service = AudioCaptureService()
        var received = 0
        service.onSpectrum = { _ in received += 1 }
        try service.start()
        try await Task.sleep(for: .seconds(1))
        service.stop()
        #expect(received > 10)
    }
}
