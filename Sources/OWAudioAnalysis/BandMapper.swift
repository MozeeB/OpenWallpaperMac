import Foundation

/// Groups FFT bins into logarithmically spaced bands and maps them to 0...1 via a dB window.
public struct BandMapper: Sendable {
    public let bandCount: Int
    public let minFrequency: Double
    public let maxFrequency: Double
    public let floorDecibels: Float
    public let ceilingDecibels: Float

    public init(
        bandCount: Int = 64, minFrequency: Double = 20, maxFrequency: Double = 16_000,
        floorDecibels: Float = -70, ceilingDecibels: Float = -10
    ) {
        self.bandCount = max(bandCount, 1)
        self.minFrequency = max(minFrequency, 1)
        self.maxFrequency = max(maxFrequency, minFrequency + 1)
        self.floorDecibels = floorDecibels
        self.ceilingDecibels = max(ceilingDecibels, floorDecibels + 1)
    }

    /// Bin ranges (half-open) for each band, given FFT bin count and sample rate.
    public func binRanges(binCount: Int, sampleRate: Double) -> [Range<Int>] {
        let binWidth = sampleRate / Double(binCount * 2)
        let ratio = maxFrequency / minFrequency
        return (0 ..< bandCount).map { band in
            let lowFreq = minFrequency * pow(ratio, Double(band) / Double(bandCount))
            let highFreq = minFrequency * pow(ratio, Double(band + 1) / Double(bandCount))
            let low = min(max(Int(lowFreq / binWidth), 1), binCount - 1)
            let high = min(max(Int(highFreq / binWidth), low + 1), binCount)
            return low ..< high
        }
    }

    /// Peak magnitude per band, normalised to 0...1.
    public func bands(magnitudes: [Float], sampleRate: Double) -> [Float] {
        guard magnitudes.count > 1 else { return [Float](repeating: 0, count: bandCount) }
        return binRanges(binCount: magnitudes.count, sampleRate: sampleRate).map { range in
            normalize(magnitudes[range].max() ?? 0)
        }
    }

    func normalize(_ magnitude: Float) -> Float {
        let decibels = 20 * log10(max(magnitude, 1e-9))
        let value = (decibels - floorDecibels) / (ceilingDecibels - floorDecibels)
        return min(max(value, 0), 1)
    }
}

/// Attack/decay smoothing so visuals rise quickly on beats and fall gracefully.
public struct SpectrumSmoother: Sendable {
    public let attack: Float
    public let decay: Float
    public private(set) var state: [Float]

    /// - Parameters:
    ///   - attack: fraction (0...1] of the gap closed per frame when rising.
    ///   - decay: fraction (0...1] of the gap closed per frame when falling.
    public init(bandCount: Int, attack: Float = 0.6, decay: Float = 0.15) {
        self.attack = min(max(attack, 0.01), 1)
        self.decay = min(max(decay, 0.01), 1)
        state = [Float](repeating: 0, count: bandCount)
    }

    public mutating func smooth(_ input: [Float]) -> [Float] {
        let count = min(input.count, state.count)
        for index in 0 ..< count {
            let previous = state[index]
            let target = input[index]
            let factor = target > previous ? attack : decay
            state[index] = previous + (target - previous) * factor
        }
        return state
    }

    public mutating func reset() {
        state = [Float](repeating: 0, count: state.count)
    }
}
