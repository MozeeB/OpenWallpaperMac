import Foundation
import Testing
@testable import OWAudioAnalysis

private func sine(frequency: Double, sampleRate: Double = 48_000, count: Int = 2048, amplitude: Float = 1) -> [Float] {
    (0 ..< count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
}

@Suite("FFT & bands")
struct FFTTests {
    @Test("rejects invalid sizes")
    func sizes() {
        #expect(FFTAnalyzer(size: 100) == nil)
        #expect(FFTAnalyzer(size: 32) == nil)
        #expect(FFTAnalyzer(size: 1024) != nil)
    }

    @Test("unit sine peaks near 1 at the right bin")
    func sinePeak() throws {
        let fft = try #require(FFTAnalyzer(size: 2048))
        let binWidth = 48_000.0 / 2048
        let frequency = binWidth * 40  // exactly on bin 40
        let magnitudes = fft.magnitudes(sine(frequency: frequency))
        let peak = try #require(magnitudes.indices.max { magnitudes[$0] < magnitudes[$1] })
        #expect(peak == 40)
        #expect(abs(magnitudes[40] - 1) < 0.05)
        #expect(fft.magnitudes([]).allSatisfy { $0 == 0 })
    }

    @Test("band ranges are ordered, non-empty and in bounds")
    func ranges() {
        let ranges = BandMapper().binRanges(binCount: 1024, sampleRate: 48_000)
        #expect(ranges.count == 64)
        #expect(ranges.allSatisfy { !$0.isEmpty && $0.lowerBound >= 1 && $0.upperBound <= 1024 })
        #expect(zip(ranges, ranges.dropFirst()).allSatisfy { $0.lowerBound <= $1.lowerBound })
    }

    @Test("a tone lights up the band containing it")
    func toneBand() throws {
        let mapper = BandMapper()
        let fft = try #require(FFTAnalyzer(size: 2048))
        let bands = mapper.bands(magnitudes: fft.magnitudes(sine(frequency: 1000)), sampleRate: 48_000)
        let loudest = try #require(bands.indices.max { bands[$0] < bands[$1] })
        let ranges = mapper.binRanges(binCount: 1024, sampleRate: 48_000)
        let binWidth = 48_000.0 / 2048
        let expectedBin = Int(1000 / binWidth)
        #expect(ranges[loudest].contains(expectedBin) || abs(ranges[loudest].lowerBound - expectedBin) <= 1)
        #expect(bands[loudest] > 0.9)
        #expect(bands[0] < 0.3)
        #expect(mapper.bands(magnitudes: [], sampleRate: 48_000) == [Float](repeating: 0, count: 64))
    }

    @Test("dB normalisation clamps")
    func normalize() {
        let mapper = BandMapper(floorDecibels: -60, ceilingDecibels: 0)
        #expect(mapper.normalize(0) == 0)
        #expect(mapper.normalize(1) == 1)
        #expect(abs(mapper.normalize(0.031_622_8) - 0.5) < 0.001)
        #expect(mapper.normalize(10) == 1)
    }
}

@Suite("Smoothing & pipeline")
struct PipelineTests {
    @Test("attack is faster than decay")
    func smoothing() {
        var smoother = SpectrumSmoother(bandCount: 1, attack: 0.5, decay: 0.1)
        #expect(smoother.smooth([1]) == [0.5])
        #expect(smoother.smooth([1]) == [0.75])
        let afterDrop = smoother.smooth([0])[0]
        #expect(abs(afterDrop - 0.675) < 0.0001)
        smoother.reset()
        #expect(smoother.state == [0])
        #expect(SpectrumSmoother(bandCount: 1, attack: 5, decay: -1).attack == 1)
    }

    @Test("pipeline separates channels")
    func pipeline() throws {
        let pipeline = try #require(SpectrumPipeline(fftSize: 2048))
        let left = sine(frequency: 200)
        let right = [Float](repeating: 0, count: 2048)
        let interleaved = zip(left, right).flatMap { [$0, $1] }
        let result = pipeline.process(interleaved: interleaved)
        #expect(result.left.max()! > 0.3)
        #expect(result.right.max()! == 0)
        pipeline.reset()
        #expect(SpectrumPipeline(sampleRate: 0) == nil)
    }
}

@Suite("SPSC ring buffer")
struct RingBufferTests {
    @Test("wraps around and respects capacity")
    func wraps() {
        let ring = SPSCRingBuffer(capacity: 5)
        #expect(ring.write([1, 2, 3]) == 3)
        #expect(ring.read(count: 2) == [1, 2])
        #expect(ring.write([4, 5, 6, 7]) == 3)  // usable capacity is 4
        #expect(ring.availableToRead == 4)
        #expect(ring.write([8]) == 0)
        #expect(ring.read(count: 10) == [3, 4, 5, 6])
        ring.write([9, 10])
        ring.drain()
        #expect(ring.availableToRead == 0)
        #expect(ring.read(count: 3).isEmpty)
    }

    @Test("concurrent producer/consumer preserves order without loss")
    func concurrent() async {
        let ring = SPSCRingBuffer(capacity: 1024)
        let total = 200_000
        async let produced: Void = Task.detached {
            var next: Float = 0
            while next < Float(total) {
                let chunk = (0 ..< 64).map { next + Float($0) }.filter { $0 < Float(total) }
                var offset = 0
                while offset < chunk.count {
                    offset += chunk[offset...].withContiguousStorageIfAvailable { ring.write($0) } ?? 0
                }
                next += Float(chunk.count)
            }
        }.value
        let consumed: Bool = await Task.detached {
            var expected: Float = 0
            while expected < Float(total) {
                for value in ring.read(count: 128) {
                    if value != expected { return false }
                    expected += 1
                }
            }
            return true
        }.value
        await produced
        #expect(consumed)
    }
}
