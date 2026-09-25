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
        if mode == .uiTest { seedSamples(store: store, importer: importer, base: base) }
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
            return FileManager.default.temporaryDirectory.appendingPathComponent("OpenWallpaperMac-UITest-\(ProcessInfo.processInfo.processIdentifier)")
        }
    }

    /// Writes a synthetic scene and a shader into a fresh state so UI tests have content.
    static func seedSamples(store: StateStore, importer: ImportService, base: URL) {
        let samples = base.appendingPathComponent("Samples")
        let scene = samples.appendingPathComponent("Synthetic Scene")
        let shader = samples.appendingPathComponent("Plasma")
        do {
            try SyntheticScene.write(SyntheticScene.projectFiles(), to: scene)
            try SyntheticScene.write(SampleContent.plasmaShaderFiles(), to: shader)
            let library = try [scene, shader].map { try importer.importFolder($0) }
            let data = try JSONEncoder().encode(PersistedState.empty.with(settings: .default.with(posterSync: false), library: library))
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
