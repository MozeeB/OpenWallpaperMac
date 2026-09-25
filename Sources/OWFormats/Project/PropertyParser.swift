import Foundation
import OWCore

/// Maps Wallpaper Engine-style `general.properties` dictionaries to `PropertyDefinition`s.
///
/// The same shape is used by native `wallpaper.json` manifests so authors learn one format.
/// Unknown or unsupported property types (file pickers, label-only "text") are skipped.
public enum PropertyParser {
    public static func parse(_ raw: [String: Any]) -> [PropertyDefinition] {
        raw.prefix(Limits.maxProperties)
            .compactMap { key, value in (value as? [String: Any]).flatMap { definition(key: key, $0) } }
            .sorted { ($0.order, $0.key) < ($1.order, $1.key) }
    }

    static func definition(key: String, _ raw: [String: Any]) -> PropertyDefinition? {
        guard !key.isEmpty, key.count <= 128, let type = raw["type"] as? String else { return nil }
        let label = cleanLabel(raw["text"] as? String) ?? key
        let order = (raw["order"] as? NSNumber)?.intValue ?? 0
        guard let (kind, value) = kindAndValue(type: type.lowercased(), raw) else { return nil }
        return PropertyDefinition(key: key, label: label, order: order, kind: kind, defaultValue: value)
    }

    private static func kindAndValue(type: String, _ raw: [String: Any]) -> (PropertyKind, PropertyValue)? {
        switch type {
        case "bool":
            return (.bool, .bool(boolValue(raw["value"])))
        case "slider":
            return slider(raw)
        case "color":
            let color = (raw["value"] as? String).flatMap(RGBColor.init(weString:)) ?? .white
            return (.color, .color(color))
        case "combo":
            return combo(raw)
        case "textinput":
            return (.text, .string(String((raw["value"] as? String ?? "").prefix(4096))))
        default:
            return nil
        }
    }

    private static func slider(_ raw: [String: Any]) -> (PropertyKind, PropertyValue)? {
        let lower = number(raw["min"]) ?? 0
        let upper = number(raw["max"]) ?? 100
        guard lower.isFinite, upper.isFinite, lower <= upper else { return nil }
        let step: Double
        if let explicit = number(raw["step"]), explicit > 0 {
            step = explicit
        } else if let precision = number(raw["precision"]), precision >= 0, precision <= 6 {
            step = pow(10, -precision)
        } else {
            step = upper > lower ? (upper - lower) / 100 : 1
        }
        let value = min(max(number(raw["value"]) ?? lower, lower), upper)
        return (.slider(min: lower, max: upper, step: step), .number(value))
    }

    private static func combo(_ raw: [String: Any]) -> (PropertyKind, PropertyValue)? {
        let options = (raw["options"] as? [[String: Any]] ?? []).compactMap { option -> ComboOption? in
            guard let value = stringValue(option["value"]) else { return nil }
            return ComboOption(label: cleanLabel(option["label"] as? String) ?? value, value: value)
        }
        guard let first = options.first else { return nil }
        let current = stringValue(raw["value"]).flatMap { value in options.first { $0.value == value } } ?? first
        return (.combo(options), .string(current.value))
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: return number.boolValue
        case let text as String: return ["true", "1"].contains(text.lowercased())
        default: return false
        }
    }

    static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber:
            let double = number.doubleValue
            return double.rounded() == double ? String(Int(double)) : String(double)
        default: return nil
        }
    }

    /// Strips HTML tags and whitespace; returns nil when nothing is left.
    static func cleanLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : String(stripped.prefix(200))
    }
}
