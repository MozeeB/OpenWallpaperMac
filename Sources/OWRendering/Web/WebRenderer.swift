import AppKit
import OWCore
import OWFormats
import QuartzCore
import WebKit

/// HTML wallpaper in a sandboxed `WKWebView`.
///
/// Security: loads only files inside the wallpaper folder, blocks network by default, never opens
/// windows. Performance: pausing hides the view (WebKit throttles timers and rAF for hidden views)
/// and suspends media; suspending unloads the page.
@MainActor
public final class WebRenderer: NSObject, WallpaperRenderer, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    public var onFailure: ((RenderError) -> Void)?
    public let hostView: NSView
    public private(set) var webView: WKWebView?
    public private(set) var receivedMessages: [WebMessage] = []
    public var networkAllowed = false

    private var root: URL?
    private var entry: URL?
    private var values: PropertyValues = [:]
    private var definitions: [PropertyDefinition] = []
    private var wantsAudio = false
    private var lastAudioPush: CFTimeInterval = 0
    private var loadContinuation: CheckedContinuation<Void, Never>?
    public static let audioInterval: CFTimeInterval = 1.0 / 30

    override public init() {
        hostView = NSView()
        hostView.wantsLayer = true
        hostView.layer?.backgroundColor = NSColor.black.cgColor
        super.init()
    }

    public func load(_ wallpaper: ResolvedWallpaper, context: RenderContext) async throws(RenderError) {
        guard let entry = wallpaper.entryFileURL else { throw .assetMissing(wallpaper.wallpaper.entry.string) }
        root = wallpaper.wallpaper.root
        self.entry = entry
        definitions = wallpaper.wallpaper.properties
        values = definitions.resolve(wallpaper.values)
        await createWebView()
    }

    private func createWebView() async {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.suppressesIncrementalRendering = true
        let controller = configuration.userContentController
        controller.addUserScript(WKUserScript(source: WebBridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.add(WeakMessageHandler(self), name: WebMessage.handlerName)
        if !networkAllowed, let rules = await WebRenderer.networkBlockList() { controller.add(rules) }
        let webView = WKWebView(frame: hostView.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = .black
        hostView.addSubview(webView)
        self.webView = webView
        guard let entry, let root else { return }
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            webView.loadFileURL(entry, allowingReadAccessTo: root)
        }
        applyScripts()
    }

    private static func networkBlockList() async -> WKContentRuleList? {
        try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "ow-block-network", encodedContentRuleList: WebSecurityPolicy.blockNetworkRules
        )
    }

    private func finishLoading() {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    private func applyScripts() {
        webView?.evaluateJavaScript(WebBridgeScript.applyPropertiesCall(values), completionHandler: nil)
    }

    public func setPlayback(_ state: PlaybackState) {
        switch state {
        case .playing:
            if webView == nil { Task { await createWebView() } }
            webView?.isHidden = false
            webView?.setAllMediaPlaybackSuspended(false, completionHandler: nil)
            webView?.evaluateJavaScript(WebBridgeScript.pausedCall(false), completionHandler: nil)
        case .paused:
            webView?.evaluateJavaScript(WebBridgeScript.pausedCall(true), completionHandler: nil)
            webView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            webView?.isHidden = true
        case .suspended:
            destroyWebView()
        }
    }

    public func apply(_ newValues: PropertyValues) {
        values = definitions.resolve(newValues)
        applyScripts()
    }

    public func receive(_ spectrum: AudioSpectrum) {
        guard wantsAudio, let webView, !webView.isHidden else { return }
        let now = CACurrentMediaTime()
        guard now - lastAudioPush >= WebRenderer.audioInterval else { return }
        lastAudioPush = now
        webView.evaluateJavaScript(WebBridgeScript.audioCall(spectrum), completionHandler: nil)
    }

    public func snapshot() async throws(RenderError) -> CGImage {
        guard let webView else { throw .notLoaded }
        do {
            let image = try await webView.takeSnapshot(configuration: nil)
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw RenderError.snapshotFailed }
            return cgImage
        } catch {
            throw .snapshotFailed
        }
    }

    public func teardown() {
        destroyWebView()
        root = nil
        entry = nil
    }

    private func destroyWebView() {
        finishLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: WebMessage.handlerName)
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        wantsAudio = false
    }

    // MARK: WKNavigationDelegate / WKUIDelegate

    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url, let root else { return .cancel }
        return WebSecurityPolicy.allows(url, root: root, networkAllowed: networkAllowed) ? .allow : .cancel
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finishLoading()
        onFailure?(.web(error.localizedDescription))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        finishLoading()
        onFailure?(.web(error.localizedDescription))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onFailure?(.web("web content process terminated"))
    }

    public func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? { nil }

    // MARK: WKScriptMessageHandler

    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = WebMessage.parse(message.body) else { return }
        if receivedMessages.count < 100 { receivedMessages.append(parsed) }
        if parsed == .audioListenerRegistered { wantsAudio = true }
        if parsed == .ready { applyScripts() }
    }
}

/// Breaks the retain cycle between `WKUserContentController` and the renderer.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
