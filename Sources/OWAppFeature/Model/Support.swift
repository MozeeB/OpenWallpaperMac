import Foundation
import OWCore
import OWFormats
import OWLibrary
import OWRendering
import ServiceManagement

/// Launch-at-login control (injectable for tests).
@MainActor
public protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// `SMAppService` main-app login item. Works only for a signed app in /Applications.
@MainActor
public struct SystemLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// User-facing descriptions of errors (no internal paths or codes beyond what helps).
public enum ImportErrorText {
    public static func describe(_ error: ImportError) -> String {
        switch error {
        case .notFound: return "file not found"
        case .unsupportedFile(let name): return "\(name) is not a supported wallpaper file"
        case .tooLarge(let name): return "\(name) is too large"
        case .project(let project): return describe(project)
        case .copyFailed(let reason): return "copy failed (\(reason))"
        case .package: return "the scene package is damaged"
        }
    }

    static func describe(_ error: ProjectError) -> String {
        switch error {
        case .noManifest: return "no project.json or wallpaper.json in the folder"
        case .unreadable: return "the manifest could not be read"
        case .invalidJSON: return "the manifest is not valid JSON"
        case .missingField(let field): return "the manifest is missing \"\(field)\""
        case .unsupportedType(let type): return "\"\(type)\" wallpapers are not supported"
        case .invalidPath(let path): return "unsafe path \"\(path)\""
        case .entryNotFound(let path): return "\(path) is missing"
        }
    }
}

public enum RenderErrorText {
    public static func describe(_ error: RenderError) -> String {
        switch error {
        case .unsupported(let type): return "\(type.rawValue) features not supported yet"
        case .assetMissing(let path): return "missing \(path)"
        case .invalidAsset(let reason): return reason
        case .metalUnavailable: return "Metal is unavailable"
        case let .compile(line, message): return "shader error\(line.map { " on line \($0)" } ?? ""): \(message)"
        case .gpuHang: return "the GPU took too long and the wallpaper was stopped"
        case .snapshotFailed: return "snapshot failed"
        case .notLoaded: return "not loaded"
        case .web(let reason): return reason
        }
    }
}
