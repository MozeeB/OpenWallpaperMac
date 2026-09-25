import CoreGraphics
import Foundation
import IOKit.ps

/// Source of on-screen windows (injectable for tests).
public protocol WindowListProviding: Sendable {
    func onScreenWindows() -> [WindowInfo]
}

public struct CGWindowListProvider: WindowListProviding {
    public init() {}

    public func onScreenWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap(WindowInfo.init(dictionary:))
    }
}

/// Power source state (injectable for tests).
public protocol PowerSourceProviding: Sendable {
    var isOnBattery: Bool { get }
    var isLowPowerMode: Bool { get }
    var thermal: ThermalLevel { get }
}

public struct SystemPowerSource: PowerSourceProviding {
    public init() {}

    public var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    public var isLowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    public var thermal: ThermalLevel { ThermalLevel(ProcessInfo.processInfo.thermalState) }
}
