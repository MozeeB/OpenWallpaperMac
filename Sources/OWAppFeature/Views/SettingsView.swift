import OWCore
import SwiftUI

/// Settings window: general, performance (pause rules and frame caps), audio and advanced.
public struct SettingsView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            performance.tabItem { Label("Performance", systemImage: "gauge.with.dots.needle.33percent") }
            audio.tabItem { Label("Audio", systemImage: "waveform") }
            advanced.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 420)
    }

    private var settings: AppSettings { model.settings }

    private func binding<T>(_ get: @escaping (AppSettings) -> T, _ set: @escaping (AppSettings, T) -> AppSettings) -> Binding<T> {
        Binding(get: { get(model.settings) }, set: { model.updateSettings(set(model.settings, $0)) })
    }

    private var general: some View {
        Form {
            Toggle("Launch at login", isOn: binding(\.launchAtLogin) { $0.with(launchAtLogin: $1) })
            Toggle("Match system wallpaper (Mission Control, lock screen, menu bar)",
                   isOn: binding(\.posterSync) { $0.with(posterSync: $1) })
            Text("Uses a still frame of the live wallpaper as the regular macOS wallpaper. The original is restored when you quit.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var performance: some View {
        Form {
            Section("Frame rate") {
                Picker("Maximum", selection: binding(\.frameRateCap) { $0.with(frameRateCap: $1) }) {
                    ForEach(FrameRateCap.allCases, id: \.self) { Text("\($0.rawValue) fps").tag($0) }
                }
                Picker("On battery", selection: binding(\.batteryFrameRateCap) { $0.with(batteryFrameRateCap: $1) }) {
                    ForEach(FrameRateCap.allCases, id: \.self) { Text("\($0.rawValue) fps").tag($0) }
                }
                LabeledContent("Render scale (shaders & scenes)") {
                    Slider(value: binding(\.renderScale) { $0.with(renderScale: $1) }, in: 0.25 ... 1, step: 0.25)
                    Text("\(Int(settings.renderScale * 100))%").monospacedDigit().frame(width: 44)
                }
            }
            Section("When…") {
                rule("Another app is fullscreen or maximised", \.fullscreenApp)
                rule("The wallpaper is covered", \.occluded)
                rule("On battery power", \.onBattery)
                rule("Low Power Mode is on", \.lowPowerMode)
                rule("The Mac is running hot", \.thermalSerious)
                rule("The screen is locked", \.screenLocked)
                rule("Displays are asleep", \.screensAsleep)
            }
            Text("Pause stops rendering (0% CPU). Suspend also frees memory and the video decoder.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func rule(_ title: String, _ keyPath: WritableKeyPath<PauseRules.Mutable, PauseAction>) -> some View {
        Picker(title, selection: Binding(
            get: { PauseRulesAccess.value(model.settings.pauseRules, keyPath) },
            set: { model.updateSettings(model.settings.with(pauseRules: model.settings.pauseRules.with(keyPath, $0))) }
        )) {
            Text("Keep playing").tag(PauseAction.ignore)
            Text("Pause").tag(PauseAction.pause)
            Text("Suspend").tag(PauseAction.suspend)
        }
    }

    private var audio: some View {
        Form {
            Toggle("Audio-reactive wallpapers", isOn: binding(\.audioEnabled) { $0.with(audioEnabled: $1) })
            Text("""
            Captures system audio output only while an audio-reactive wallpaper is playing. \
            macOS asks for permission the first time (System Audio Recording). Audio never leaves your Mac.
            """)
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var advanced: some View {
        Form {
            Stepper("Window level offset: \(settings.windowLevelOffset)",
                    value: binding(\.windowLevelOffset) { $0.with(windowLevelOffset: $1) },
                    in: AppSettings.windowLevelOffsetRange)
            Text("Only change this if a macOS update draws desktop icons behind the wallpaper.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

enum PauseRulesAccess {
    static func value(_ rules: PauseRules, _ keyPath: WritableKeyPath<PauseRules.Mutable, PauseAction>) -> PauseAction {
        rules.mutableCopy[keyPath: keyPath]
    }
}
