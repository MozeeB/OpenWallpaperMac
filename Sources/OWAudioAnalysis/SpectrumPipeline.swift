import Foundation

/// Stereo samples → smoothed 64-band spectra per channel.
///
/// Owns FFT state; call from a single (utility) queue.
public final class SpectrumPipeline {
    public let fftSize: Int
    public let sampleRate: Double
    private let fft: FFTAnalyzer
    private let mapper: BandMapper
    private var leftSmoother: SpectrumSmoother
    private var rightSmoother: SpectrumSmoother

    public init?(fftSize: Int = 2048, sampleRate: Double = 48_000, mapper: BandMapper = BandMapper()) {
        guard sampleRate > 0, let fft = FFTAnalyzer(size: fftSize) else { return nil }
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.fft = fft
        self.mapper = mapper
        leftSmoother = SpectrumSmoother(bandCount: mapper.bandCount)
        rightSmoother = SpectrumSmoother(bandCount: mapper.bandCount)
    }

    /// Processes one window of interleaved stereo samples (L R L R …).
    public func process(interleaved samples: [Float]) -> (left: [Float], right: [Float]) {
        let (left, right) = SpectrumPipeline.deinterleave(samples)
        return process(left: left, right: right)
    }

    public func process(left: [Float], right: [Float]) -> (left: [Float], right: [Float]) {
        let leftBands = mapper.bands(magnitudes: fft.magnitudes(left), sampleRate: sampleRate)
        let rightBands = mapper.bands(magnitudes: fft.magnitudes(right), sampleRate: sampleRate)
        return (leftSmoother.smooth(leftBands), rightSmoother.smooth(rightBands))
    }

    public func reset() {
        leftSmoother.reset()
        rightSmoother.reset()
    }

    static func deinterleave(_ samples: [Float]) -> ([Float], [Float]) {
        let frames = samples.count / 2
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)
        for frame in 0 ..< frames {
            left[frame] = samples[frame * 2]
            right[frame] = samples[frame * 2 + 1]
        }
        return (left, right)
    }
}
