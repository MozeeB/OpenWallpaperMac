import CoreAudio
import Foundation

public enum AudioCaptureError: Error, Equatable, Sendable {
    case unsupportedOS
    case osStatus(operation: String, code: OSStatus)
    case noOutputDevice
    case invalidFormat
    case alreadyRunning
}

/// Thin, typed wrappers over the Core Audio HAL property API.
enum CoreAudioSupport {
    static func check(_ status: OSStatus, _ operation: String) throws(AudioCaptureError) {
        guard status == noErr else { throw .osStatus(operation: operation, code: status) }
    }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T,
                        qualifier: (UnsafeRawPointer, UInt32)? = nil) throws(AudioCaptureError) -> T {
        var address = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, qualifier?.1 ?? 0, qualifier?.0, &size, pointer)
        }
        try check(status, "read '\(fourCC(selector))'")
        return value
    }

    static func defaultOutputDevice() throws(AudioCaptureError) -> AudioObjectID {
        let device = try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                              initial: AudioObjectID(kAudioObjectUnknown))
        guard device != kAudioObjectUnknown else { throw .noOutputDevice }
        return device
    }

    static func deviceUID(_ device: AudioObjectID) throws(AudioCaptureError) -> String {
        let uid = try read(device, kAudioDevicePropertyDeviceUID, initial: "" as CFString)
        return uid as String
    }

    /// The HAL process object for a PID (used to exclude our own output from the tap).
    static func processObject(pid: pid_t) throws(AudioCaptureError) -> AudioObjectID {
        var pidValue = pid
        return try withUnsafePointer(to: &pidValue) { pointer throws(AudioCaptureError) -> AudioObjectID in
            try read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTranslatePIDToProcessObject,
                     initial: AudioObjectID(kAudioObjectUnknown),
                     qualifier: (UnsafeRawPointer(pointer), UInt32(MemoryLayout<pid_t>.size)))
        }
    }

    static func tapFormat(_ tap: AudioObjectID) throws(AudioCaptureError) -> AudioStreamBasicDescription {
        let format = try read(tap, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        guard format.mSampleRate > 0, format.mFormatID == kAudioFormatLinearPCM else { throw .invalidFormat }
        return format
    }

    static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? String(value)
    }
}
