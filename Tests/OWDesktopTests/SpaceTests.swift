import AppKit
import Foundation
import Testing
@testable import OWCore
@testable import OWDesktop

private let builtIn = DisplayKey("37D8832A-2D66-02CA-B9F7-8F30A301B230")
private let external = DisplayKey("1CDAB793-36EC-4760-A480-8CB2D869D89D")

/// Shape of what the window server returns (captured from macOS 26.6).
nonisolated(unsafe) private let windowServerFixture: [[String: Any]] = [
    [
        "Display Identifier": builtIn.rawValue,
        "Current Space": ["ManagedSpaceID": 3, "uuid": "452B8850-0000", "type": 0],
        "Spaces": [
            ["ManagedSpaceID": 1, "uuid": "", "type": 0],
            ["ManagedSpaceID": 3, "uuid": "452B8850-0000", "type": 0],
            ["ManagedSpaceID": 12, "uuid": "FULL-1", "type": 4],
            ["ManagedSpaceID": 4, "uuid": "E233B925-0000", "type": 0],
        ],
    ],
    [
        "Display Identifier": external.rawValue,
        "Current Space": ["ManagedSpaceID": 7, "uuid": "AF758A28-0000", "type": 0],
        "Spaces": [["ManagedSpaceID": 7, "uuid": "AF758A28-0000", "type": 0]],
    ],
]

@Suite("Space parsing")
struct SpaceParserTests {
    @Test("numbers desktops, skips fullscreen numbering, falls back for the empty uuid")
    func parse() throws {
        let result = SpaceParser.parse(windowServerFixture, displays: [builtIn, external])
        let spaces = try #require(result[builtIn])
        #expect(spaces.spaces.map(\.name) == ["Desktop 1", "Desktop 2", "Fullscreen app", "Desktop 3"])
        #expect(spaces.spaces[0].key == SpaceKey("managed-1"))
        #expect(spaces.current == SpaceKey("452B8850-0000"))
        #expect(spaces.currentSpace?.number == 2)
        #expect(result[external]?.spaces.count == 1)
    }

    @Test("shared Spaces (reported as Main) apply to every display")
    func shared() {
        let raw: [[String: Any]] = [[
            "Display Identifier": "Main",
            "Current Space": ["ManagedSpaceID": 5, "uuid": "S5"],
            "Spaces": [["ManagedSpaceID": 5, "uuid": "S5"], ["ManagedSpaceID": 6, "uuid": "S6"]],
        ]]
        let result = SpaceParser.parse(raw, displays: [builtIn, external])
        #expect(result[builtIn] == result[external])
        #expect(result[external]?.current == SpaceKey("S5"))
    }

    @Test("ignores malformed entries")
    func malformed() {
        let raw: [[String: Any]] = [["Spaces": []], ["Display Identifier": "X", "Spaces": [["type": 0]]]]
        let result = SpaceParser.parse(raw, displays: [])
        #expect(result[DisplayKey("X")]?.spaces.isEmpty == true)
        #expect(result[DisplayKey("X")]?.current == nil)
        #expect(SpaceInfo(key: SpaceKey("k"), number: 0, isFullscreen: true).name == "Fullscreen app")
    }
}

@MainActor
private final class FakeSpaceProvider: SpaceProviding {
    var isAvailable = true
    var value: [DisplayKey: DisplaySpaces] = [:]
    func snapshot(displays: [DisplayKey]) -> [DisplayKey: DisplaySpaces] { value }
}

@Suite("SpaceMonitor")
@MainActor
struct SpaceMonitorTests {
    @Test("reports the active Space and notifies only on change")
    func monitor() {
        let provider = FakeSpaceProvider()
        let one = SpaceInfo(key: SpaceKey("one"), number: 1)
        let two = SpaceInfo(key: SpaceKey("two"), number: 2)
        provider.value = [builtIn: DisplaySpaces(spaces: [one, two], current: one.key)]
        let monitor = SpaceMonitor(provider: provider)
        var changes = 0
        monitor.onChange = { changes += 1 }
        monitor.start()
        monitor.start()
        #expect(monitor.currentSpace(on: builtIn) == one.key)
        #expect(changes == 1)
        monitor.refresh()
        #expect(changes == 1, "no change, no notification")
        provider.value = [builtIn: DisplaySpaces(spaces: [one, two], current: two.key)]
        monitor.updateDisplays([builtIn])
        #expect(monitor.currentSpace(on: builtIn) == two.key)
        #expect(changes == 2)
        monitor.stop()
    }

    @Test("unavailable provider disables the feature")
    func unavailable() {
        let provider = FakeSpaceProvider()
        provider.isAvailable = false
        let monitor = SpaceMonitor(provider: provider)
        monitor.start()
        #expect(!monitor.isAvailable)
        #expect(monitor.currentSpace(on: builtIn) == nil)
    }

    @Test("the real window-server provider works on this Mac")
    func live() {
        let provider = WindowServerSpaceProvider()
        let displays = SystemScreenProvider().currentScreens().map(\.key)
        if provider.isAvailable, let first = displays.first {
            #expect(provider.snapshot(displays: displays)[first]?.spaces.isEmpty == false)
        }
    }
}
