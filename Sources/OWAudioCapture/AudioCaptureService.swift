import CoreAudio
import Foundation
import OWAudioAnalysis
import OWCore

/// Anything that produces audio spectra (real capture or a test fake).
@MainActor
public protocol AudioSpectrumSource: AnyObject {
    var onSpectrum: ((AudioSpectrum) -> Void)? { get set }
    var onSilence: (() -> Void)? { get set }
    var isRunning: Bool { get }
    func start() throws(AudioCaptureError)
    func stop()
}

/// System-audio capture -> 30 Hz spectra, rebuilt when the default output device changes.
///
/// Only runs while at least one audio-reactive wallpaper is playing (the app layer decides).
@MainActor
public final class AudioCaptureService: AudioSpectrumSource {
    public var onSpectrum: ((AudioSpectrum) -> Void)?
    public var onSilence: (() -> Void)?
    public private(set) var isRunning = false

    private let ring = SPSCRingBuffer(capacity: 48_000 * 2)
    private var capture: ProcessTapCapture?
    private var loop: SpectrumAnalysisLoop?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    public init() {}

    public static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    public func start() throws(AudioCaptureError) {
        guard !isRunning else { return }
        let capture = ProcessTapCapture(ring: ring)
        try capture.start()
        guard let loop = SpectrumAnalysisLoop(
            ring: ring, sampleRate: capture.sampleRate,
            onSpectrum: { [weak self] spectrum in Task { @MainActor in self?.onSpectrum?(spectrum) } },
            onSilence: { [weak self] in Task { @MainActor in self?.onSilence?() } }
        ) else {
            capture.stop()
            throw .invalidFormat
        }
        loop.start()
        self.capture = capture
        self.loop = loop
        isRunning = true
        listenForDeviceChanges()
    }

    public func stop() {
        stopListening()
        loop?.stop()
        capture?.stop()
        loop = nil
        capture = nil
        isRunning = false
    }

    private func restart() {
        guard isRunning else { return }
        stop()
        try? start()
    }

    private func listenForDeviceChanges() {
        var address = CoreAudioSupport.address(kAudioHardwarePropertyDefaultOutputDevice)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.restart() }
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        deviceListener = block
    }

    private func stopListening() {
        guard let deviceListener else { return }
        var address = CoreAudioSupport.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        self.deviceListener = nil
    }
}
