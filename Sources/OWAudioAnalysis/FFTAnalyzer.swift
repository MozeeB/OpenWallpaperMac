import Accelerate
import Foundation

/// Windowed real FFT → linear magnitudes, using vDSP.
///
/// Not thread-safe; own one per analysis queue. All buffers are preallocated so `magnitudes`
/// performs no allocation after init besides the returned array.
public final class FFTAnalyzer {
    public let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]

    /// - Parameter size: power of two between 64 and 16384.
    public init?(size: Int) {
        guard size >= 64, size <= 16_384, size & (size - 1) == 0 else { return nil }
        self.size = size
        log2n = vDSP_Length(log2(Double(size)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Magnitudes for bins 0..<size/2. Input shorter than `size` is zero-padded.
    public func magnitudes(_ samples: [Float]) -> [Float] {
        let count = min(samples.count, size)
        for index in 0 ..< size { windowed[index] = index < count ? samples[index] : 0 }
        vDSP.multiply(windowed, window, result: &windowed)
        var output = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Bin 0 packs DC (real) and Nyquist (imag); keep DC only.
                let dc = abs(split.realp[0])
                split.imagp[0] = 0
                output.withUnsafeMutableBufferPointer { out in
                    vDSP_zvabs(&split, 1, out.baseAddress!, 1, vDSP_Length(size / 2))
                }
                output[0] = dc
            }
        }
        // zrip doubles the output and the Hann window halves it, so /(size/2) maps a unit sine to ~1.
        let scale = 1 / Float(size / 2)
        return vDSP.multiply(scale, output)
    }
}
