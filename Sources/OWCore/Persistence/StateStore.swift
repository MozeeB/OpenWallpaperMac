import Foundation

/// Everything the app persists between launches.
public struct PersistedState: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let settings: AppSettings
    public let assignments: [DisplayAssignment]
    public let library: [Wallpaper]

    public init(
        schemaVersion: Int = PersistedState.currentSchemaVersion,
        settings: AppSettings = .default,
        assignments: [DisplayAssignment] = [],
        library: [Wallpaper] = []
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.assignments = assignments
        self.library = library
    }

    public static let empty = PersistedState()

    public func with(
        settings: AppSettings? = nil,
        assignments: [DisplayAssignment]? = nil,
        library: [Wallpaper]? = nil
    ) -> PersistedState {
        PersistedState(
            schemaVersion: schemaVersion,
            settings: settings ?? self.settings,
            assignments: assignments ?? self.assignments,
            library: library ?? self.library
        )
    }
}

public enum StateStoreError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case corrupt(String)
    case writeFailed(String)
}

/// Loads and atomically saves `PersistedState` as JSON.
public actor StateStore {
    public nonisolated let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location: `~/Library/Application Support/OpenWallpaperMac/state.json`.
    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("OpenWallpaperMac/state.json")
    }

    /// Returns `.empty` if no file exists yet.
    public func load() throws(StateStoreError) -> PersistedState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw .corrupt(error.localizedDescription)
        }
        return try StateStore.decode(data)
    }

    public func save(_ state: PersistedState) throws(StateStoreError) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    static func decode(_ data: Data) throws(StateStoreError) -> PersistedState {
        struct VersionProbe: Decodable { let schemaVersion: Int }
        let version: Int
        do {
            version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw .corrupt(error.localizedDescription)
        }
        guard version <= PersistedState.currentSchemaVersion else { throw .unsupportedSchema(version) }
        do {
            return try JSONDecoder().decode(PersistedState.self, from: data)
        } catch {
            throw .corrupt(error.localizedDescription)
        }
    }
}
