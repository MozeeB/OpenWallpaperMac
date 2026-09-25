import Foundation
import OWAudioCapture
import OWCore
import OWDesktop
import OWFormats
import OWLibrary
import OWPower
import OWScene

/// Builds the object graph. `uiTest` isolates state in a temp folder, seeds sample wallpapers and
/// never touches the real system wallpaper or login items.
@MainActor
public enum AppEnvironment {
    public enum Mode: Sendable {
        case live
        case uiTest
    }

    public static func mode(from arguments: [String] = ProcessInfo.processInfo.arguments) -> Mode {
        arguments.contains("-UITestMode") ? .uiTest : .live
    }

    public static func makeModel(mode: Mode) -> AppModel {
        let base = baseDirectory(mode: mode)
        let displays = DisplayManager()
        let posters: PosterSync? = mode == .live
            ? PosterSync(setter: WorkspaceDesktopImageSetter(), directory: base.appendingPathComponent("Posters"))
            : nil
        let audio: (any AudioSpectrumSource)? = AudioCaptureService.isSupported ? AudioCaptureService() : nil
        let coordinator = PlaybackCoordinator(
            displays: displays, power: PowerMonitor(), factory: DefaultRendererFactory(), posters: posters, audio: audio
        )
        let store = StateStore(fileURL: base.appendingPathComponent("state.json"))
        let importer = ImportService(libraryRoot: base.appendingPathComponent("Library"), knownEffects: EffectRegistry.known)
        if mode == .uiTest {
            seedSamples(store: store, importer: importer, base: base, assign: argument(after: "-UITestAssign"))
        }
        return AppModel(
            store: store, importer: importer,
            thumbnails: ThumbnailService(cacheDirectory: base.appendingPathComponent("Thumbnails")),
            coordinator: coordinator, steam: SteamLibraryLocator(),
            loginItem: mode == .live ? SystemLoginItem() : InMemoryLoginItem()
        )
    }

    static func baseDirectory(mode: Mode) -> URL {
        switch mode {
        case .live:
            return StateStore.defaultURL().deletingLastPathComponent()
        case .uiTest:
            let name = "OpenWallpaperMac-UITest-\(ProcessInfo.processInfo.processIdentifier)"
            return FileManager.default.temporaryDirectory.appendingPathComponent(name)
        }
    }

    /// Writes a synthetic scene and a shader into a fresh state so UI tests have content.
    static func argument(after flag: String, in arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `assign` optionally puts the named sample on every connected display (used for smoke tests).
    static func seedSamples(store: StateStore, importer: ImportService, base: URL, assign: String? = nil) {
        let samples = base.appendingPathComponent("Samples")
        let scene = samples.appendingPathComponent("Synthetic Scene")
        let shader = samples.appendingPathComponent("Plasma")
        do {
            try SyntheticScene.write(SyntheticScene.projectFiles(), to: scene)
            try SyntheticScene.write(SampleContent.plasmaShaderFiles(), to: shader)
            var library = try [scene, shader].map { try importer.importFolder($0) }
            // A path (file or folder) is imported too, so smoke tests can run real media.
            if let assign, FileManager.default.fileExists(atPath: assign) {
                let item = try importer.importItem(at: URL(fileURLWithPath: assign))
                library.append(item.with(title: assign))
            }
            let assignments = library.first { $0.title == assign }.map { sample in
                SystemScreenProvider().currentScreens().map { DisplayAssignment(display: $0.key, wallpaper: sample.id) }
            } ?? []
            let state = PersistedState.empty.with(settings: .default.with(posterSync: false), assignments: assignments, library: library)
            let data = try JSONEncoder().encode(state)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try data.write(to: store.fileURL)
        } catch {
            NSLog("OpenWallpaperMac: seeding UI-test samples failed: \(error)")
        }
    }
}

@MainActor
final class InMemoryLoginItem: LoginItemControlling {
    private(set) var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}
