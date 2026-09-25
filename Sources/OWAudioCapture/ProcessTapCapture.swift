import CoreAudio
import Foundation
import OWAudioAnalysis

/// Captures the system output mix (minus our own process) via a Core Audio process tap.
///
/// Requires macOS 14.4+ and the "System Audio Recording Only" permission, prompted on first start
/// (Info.plist `NSAudioCaptureUsageDescription`). The IO block is real-time: it only copies into
/// the ring buffer and never locks or allocates.
final class ProcessTapCapture: @unchecked Sendable {
    let ring: SPSCRingBuffer
    private(set) var sampleRate: Double = 48_000
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "OpenWallpaperMac.audio.io", qos: .userInteractive)
    private let scratch: UnsafeMutablePointer<Float>
    private static let scratchCapacity = 16_384

    init(ring: SPSCRingBuffer) {
        self.ring = ring
        scratch = .allocate(capacity: ProcessTapCapture.scratchCapacity)
    }

    deinit {
        stop()
        scratch.deallocate()
    }

    var isRunning: Bool { procID != nil }

    func start() throws(AudioCaptureError) {
        guard #available(macOS 14.4, *) else { throw .unsupportedOS }
        guard !isRunning else { throw .alreadyRunning }
        do {
            try createTap()
            try createAggregate()
            try startIO()
        } catch {
            stop()
            throw error
        }
    }

    @available(macOS 14.4, *)
    private func createTap() throws(AudioCaptureError) {
        let own = (try? CoreAudioSupport.processObject(pid: getpid())) ?? AudioObjectID(kAudioObjectUnknown)
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: own == kAudioObjectUnknown ? [] : [own])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "OpenWallpaperMac audio tap"
        try CoreAudioSupport.check(AudioHardwareCreateProcessTap(description, &tapID), "create process tap")
        sampleRate = try CoreAudioSupport.tapFormat(tapID).mSampleRate
        tapUUID = description.uuid.uuidString
    }

    private var tapUUID = ""

    private func createAggregate() throws(AudioCaptureError) {
        let outputUID = try CoreAudioSupport.deviceUID(try CoreAudioSupport.defaultOutputDevice())
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "OpenWallpaperMac Tap",
            kAudioAggregateDeviceUIDKey: "OpenWallpaperMac-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUUID]],
        ]
        try CoreAudioSupport.check(
            AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID), "create aggregate device"
        )
    }

    private func startIO() throws(AudioCaptureError) {
        let ring = self.ring
        let scratch = self.scratch
        let capacity = ProcessTapCapture.scratchCapacity
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            ProcessTapCapture.copy(input, into: ring, scratch: scratch, capacity: capacity)
        }
        try CoreAudioSupport.check(status, "create IO proc")
        try CoreAudioSupport.check(AudioDeviceStart(aggregateID, procID), "start device")
    }

    /// Real-time safe: interleaves to stereo in preallocated scratch and pushes to the ring.
    static func copy(_ input: UnsafePointer<AudioBufferList>, into ring: SPSCRingBuffer,
                     scratch: UnsafeMutablePointer<Float>, capacity: Int) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }
        let firstSamples = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        if first.mNumberChannels == 2 || buffers.count == 1 {
            ring.write(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: firstSamples))
            return
        }
        guard let right = buffers[1].mData else { return }
        let frames = min(firstSamples, capacity / 2)
        let left = data.assumingMemoryBound(to: Float.self)
        let rightSamples = right.assumingMemoryBound(to: Float.self)
        for frame in 0 ..< frames {
            scratch[frame * 2] = left[frame]
            scratch[frame * 2 + 1] = rightSamples[frame]
        }
        ring.write(UnsafeBufferPointer(start: scratch, count: frames * 2))
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}
