import Foundation
import OWCore

/// Pure decisions about what a web wallpaper may load.
public enum WebSecurityPolicy {
    /// Allowed: files inside the wallpaper folder, `about:blank`, `data:`/`blob:` URLs,
    /// and http(s) only when the user granted network access to this wallpaper.
    public static func allows(_ url: URL, root: URL, networkAllowed: Bool) -> Bool {
        switch url.scheme?.lowercased() {
        case "file":
            let base = root.standardizedFileURL.resolvingSymlinksInPath().path
            let target = url.standardizedFileURL.resolvingSymlinksInPath().path
            return target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        case "about":
            return url.absoluteString == "about:blank"
        case "data", "blob":
            return true
        case "http", "https":
            return networkAllowed
        default:
            return false
        }
    }

    /// WebKit content rule list that blocks all network loads.
    public static let blockNetworkRules = #"[{"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}}]"#
}

/// Messages a page may post to `window.webkit.messageHandlers.openWallpaperMac`.
public enum WebMessage: Equatable, Sendable {
    case ready
    case audioListenerRegistered
    case log(String)

    public static let handlerName = "openWallpaperMac"

    /// Validates an untrusted message body.
    public static func parse(_ body: Any) -> WebMessage? {
        guard let dict = body as? [String: Any], dict.count <= 4, let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready": return .ready
        case "audioListener": return .audioListenerRegistered
        case "log":
            guard let text = dict["message"] as? String else { return nil }
            return .log(String(text.prefix(500)))
        default: return nil
        }
    }
}

/// JavaScript shim providing the Wallpaper Engine web API surface.
public enum WebBridgeScript {
    public static let source = """
    (function () {
      if (window.__ow) { return; }
      var post = function (msg) {
        try { window.webkit.messageHandlers.\(WebMessage.handlerName).postMessage(msg); } catch (e) {}
      };
      var listeners = [];
      window.wallpaperRegisterAudioListener = function (cb) {
        if (typeof cb === 'function') { listeners.push(cb); post({ type: 'audioListener' }); }
      };
      window.__ow = {
        applyProperties: function (props) {
          var l = window.wallpaperPropertyListener;
          if (l && typeof l.applyUserProperties === 'function') { l.applyUserProperties(props); }
        },
        setPaused: function (paused) {
          var l = window.wallpaperPropertyListener;
          if (l && typeof l.setPaused === 'function') { l.setPaused(paused); }
          document.dispatchEvent(new CustomEvent('owpause', { detail: paused }));
        },
        audio: function (values) {
          for (var i = 0; i < listeners.length; i++) { try { listeners[i](values); } catch (e) {} }
        }
      };
      document.addEventListener('DOMContentLoaded', function () { post({ type: 'ready' }); });
    })();
    """

    /// Wallpaper Engine-shaped property payload: `{ key: { value: ... } }`, colours as `"r g b"`.
    public static func propertiesJSON(_ values: PropertyValues) -> String {
        let payload = values.reduce(into: [String: Any]()) { result, item in
            result[item.key] = ["value": jsonValue(item.value)]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    static func jsonValue(_ value: PropertyValue) -> Any {
        switch value {
        case .bool(let flag): return flag
        case .number(let number): return number.isFinite ? number : 0
        case .string(let text): return text
        case .color(let color): return color.weString
        }
    }

    public static func applyPropertiesCall(_ values: PropertyValues) -> String {
        "window.__ow && window.__ow.applyProperties(\(propertiesJSON(values)));"
    }

    public static func pausedCall(_ paused: Bool) -> String {
        "window.__ow && window.__ow.setPaused(\(paused));"
    }

    /// 128 values (64 left + 64 right), rounded to keep the script small.
    public static func audioCall(_ spectrum: AudioSpectrum) -> String {
        let values = spectrum.weArray.map { String(format: "%.3f", $0) }.joined(separator: ",")
        return "window.__ow && window.__ow.audio([\(values)]);"
    }
}
