import AppKit
import OWCore
import OWDesktop
import OWLibrary
import OWRendering

/// Session lifecycle: create, load, promote (cross-fade), fail over to the preview image.
extension PlaybackCoordinator {
    /// Starts a renderer for `wallpaper`. In the background it loads off screen and replaces the
    /// visible session with a cross-fade once ready.
    func startSession(
        on screen: ScreenDescriptor, wallpaper: Wallpaper, values: PropertyValues, fill: FillMode, inBackground: Bool
    ) {
        guard wallpaper.support != .previewOnly else {
            startFallback(on: screen, for: wallpaper, fill: fill, inBackground: inBackground)
            return
        }
        switch factory.makeRenderer(for: wallpaper.type) {
        case .success(let renderer):
            let session = RenderSession(display: screen.key, wallpaper: wallpaper, renderer: renderer, values: values, isFallback: false)
            launch(session, on: screen, fill: fill, inBackground: inBackground)
        case .failure:
            startFallback(on: screen, for: wallpaper, fill: fill, inBackground: inBackground)
        }
    }

    private func launch(_ session: RenderSession, on screen: ScreenDescriptor, fill: FillMode, inBackground: Bool) {
        if inBackground {
            pending[screen.key] = session
        } else {
            sessions[screen.key] = session
            displays.windows[screen.key]?.host(session.renderer.hostView)
        }
        session.renderer.onFailure = { [weak self, weak session] error in
            guard let self, let session else { return }
            self.handleFailure(session, error: error, fill: fill)
        }
        let context = RenderContext(
            pixelSize: screen.pixelSize, scale: screen.scale, fill: fill, renderScale: CGFloat(settings.renderScale)
        )
        let resolved = resolve(session)
        session.loadTask = Task { [weak self, weak session] in
            guard let session else { return }
            do throws(RenderError) {
                guard let resolved else { throw RenderError.assetMissing(session.wallpaper.root.path) }
                try await session.renderer.load(resolved, context: context)
                guard !Task.isCancelled else { return }
                self?.didLoad(session)
            } catch {
                guard !Task.isCancelled else { return }
                self?.handleFailure(session, error: error, fill: fill)
            }
        }
    }

    private func resolve(_ session: RenderSession) -> ResolvedWallpaper? {
        guard let assets = try? WallpaperResolver.assets(for: session.wallpaper) else { return nil }
        return ResolvedWallpaper(wallpaper: session.wallpaper, assets: assets, values: session.values)
    }

    private func didLoad(_ session: RenderSession) {
        let key = session.display
        if pending[key] === session {
            promote(session)
        } else if sessions[key] === session {
            session.phase = .ready
            session.renderer.setPlayback(session.playback)
        } else {
            return
        }
        let id = session.wallpaper.id
        onEvent?(session.isFallback ? .fellBackToPreview(key, id) : .loaded(key, id))
        updateAudio()
        syncPoster(session)
    }

    /// Makes a background-loaded session visible with a cross-fade, then retires the old one.
    private func promote(_ session: RenderSession) {
        let key = session.display
        pending.removeValue(forKey: key)
        let previous = sessions[key]
        sessions[key] = session
        session.phase = .ready
        applyPlayback()
        session.renderer.setPlayback(session.playback)
        if let window = displays.windows[key] {
            window.crossfade(to: session.renderer.hostView) { previous?.teardown() }
        } else {
            previous?.teardown()
        }
    }

    private func handleFailure(_ session: RenderSession, error: RenderError, fill: FillMode) {
        let key = session.display
        let wasPending = pending[key] === session
        guard wasPending || sessions[key] === session else { return }
        session.phase = .failed(error)
        onEvent?(.failed(key, session.wallpaper.id, error))
        session.teardown()
        if wasPending {
            pending.removeValue(forKey: key)
        } else {
            sessions.removeValue(forKey: key)
        }
        guard !session.isFallback, let screen = displays.screens.first(where: { $0.key == key }) else { return }
        // A failed rotation item keeps the current wallpaper visible while its preview loads.
        startFallback(on: screen, for: session.wallpaper, fill: fill, inBackground: wasPending && sessions[key] != nil)
        applyPlayback()
    }

    /// Shows the wallpaper's preview image (e.g. `preview.gif`/`preview.jpg`) instead.
    private func startFallback(on screen: ScreenDescriptor, for wallpaper: Wallpaper, fill: FillMode, inBackground: Bool) {
        guard let preview = wallpaper.preview else {
            if !inBackground { displays.windows[screen.key]?.host(nil) }
            return
        }
        let still = Wallpaper(id: wallpaper.id, title: wallpaper.title, type: .image, origin: wallpaper.origin,
                              root: wallpaper.root, entry: preview, preview: preview)
        guard case .success(let renderer) = factory.makeRenderer(for: .image) else { return }
        let session = RenderSession(display: screen.key, wallpaper: still, renderer: renderer, values: [:], isFallback: true)
        launch(session, on: screen, fill: fill, inBackground: inBackground)
    }
}

extension RenderSession {
    /// Whether this session is showing `wallpaper` (a fallback matches the wallpaper it stands in for).
    func shows(_ wallpaper: Wallpaper) -> Bool {
        if isFallback { return self.wallpaper.id == wallpaper.id && self.wallpaper.root == wallpaper.root }
        return self.wallpaper == wallpaper
    }
}
