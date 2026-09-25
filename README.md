# OpenWallpaperMac

Open-source live wallpapers for macOS: video, web pages, Metal shaders, audio-reactive visuals, and
**imported Wallpaper Engine projects**, built natively in Swift with battery-respecting auto-pause.

> Not affiliated with Wallpaper Engine or Valve. Wallpaper Engine is Windows-only; OpenWallpaperMac is an
> independent, clean-room MIT implementation that can read projects you already own.

## Features

| | |
|---|---|
| **Video** | MP4/MOV/HEVC, hardware-decoded, one shared decoder per file across displays |
| **Web** | Any local HTML folder; network blocked by default; Wallpaper Engine web API (`wallpaperPropertyListener`, `wallpaperRegisterAudioListener`) |
| **Shaders** | Shadertoy-style Metal fragment shaders with user properties and audio bands ([guide](docs/shaders.md)) |
| **Scenes** | Wallpaper Engine `scene.pkg` import: image layers, blend modes, camera parallax, native effects (scroll, shake, water ripple/waves, pulse, tint, opacity, blur), particles; unsupported features fall back to the project's preview |
| **Audio-reactive** | System audio via a Core Audio process tap (macOS 14.4+, audio-only permission) |
| **Frame rate** | 15 / 30 / 60 fps from the menu bar; 60 fps videos play natively; lower caps on battery and when the Mac is hot |
| **Auto-pause** | Fullscreen/maximised apps, occlusion, battery, Low Power Mode, thermal pressure, lock, sleep; each one configurable (keep playing / pause / suspend) |
| **Native feel** | Sits below desktop icons on every Space; a still frame is synced to the system wallpaper so Mission Control, the menu bar and the lock screen match; the original wallpaper is restored on quit |

## Requirements

- macOS 15 or later, Apple silicon recommended
- Xcode 26 (to build), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run

```bash
xcodegen generate
```

```bash
xcodebuild -project OpenWallpaperMac.xcodeproj -scheme OpenWallpaperMac -configuration Release -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Release/OpenWallpaperMac.app
```

The app opens its library window and appears in the Dock, with a quick-access menu in the menu bar. Click **+** to import files or folders, then **Set on All Displays**. Closing the window keeps wallpapers running; click the Dock icon to reopen it.

### Importing Wallpaper Engine projects

Point the importer at a project folder (the one containing `project.json`, usually
`steamapps/workshop/content/431960/<id>`) copied from a PC, or use **Scan Steam Library** if your Steam
library is on this Mac. Nothing is downloaded; projects are referenced in place. Each scene gets a support
badge: *full*, *partial* (some effects skipped) or *preview only*.

## Releases

Download the latest DMG from [Releases](https://github.com/MozeeB/OpenWallpaperMac/releases), open it and
drag **OpenWallpaperMac** into **Applications**.

Releases are fully automatic. Every push to `main` runs CI; when it passes, the
[release workflow](.github/workflows/release.yml) reads the commit messages since the last release and,
if a release is due, builds the DMG, writes the release notes, creates the tag and publishes the GitHub
Release:

| Commits since the last release | New version |
|---|---|
| `feat: ...` | minor (0.1.1 -> 0.2.0) |
| `fix: ...` or `perf: ...` | patch (0.1.1 -> 0.1.2) |
| `feat!: ...` or a `BREAKING CHANGE:` footer | major (next minor while below 1.0) |
| only `docs:`, `chore:`, `ci:`, `test:`, `style:`, `refactor:` | no release |

You can still release a specific version by pushing a tag yourself:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Build the same DMG locally (ad-hoc signed; add `DEVELOPER_ID` and notary settings for a notarized one;
see the header of the script):

```bash
scripts/release/make-dmg.sh
```

Without Developer ID secrets the published DMG is ad-hoc signed, so users must allow it once under
System Settings > Privacy & Security. Add the secrets listed at the top of `release.yml` to ship signed,
notarized builds.

## Developer tools

```bash
swift test
```

```bash
swift run owctl --help
```

`owctl` inspects/extracts `.pkg` and `.tex` files, validates folders, renders shaders/scenes offscreen to PNG,
and benchmarks per-frame cost (`owctl bench <folder-or-video>`).

## Project layout

```
App/                 thin SwiftUI app shell (menu bar, library, settings)
Sources/OWCore       immutable models, path sanitising, limits, persisted state
Sources/OWFormats    PKG / TEX / project.json / scene.json parsers (untrusted input)
Sources/OWDesktop    desktop-level windows per display, poster sync
Sources/OWRendering  image, video, web and shader renderers; Metal plumbing
Sources/OWScene      Wallpaper Engine scene renderer (layers, effects, particles)
Sources/OWPower      power signals and the pure playback policy
Sources/OWAudio*     FFT analysis and Core Audio process-tap capture
Sources/OWLibrary    import, Steam discovery, thumbnails
Sources/OWAppFeature coordinator, app model and SwiftUI views
Sources/owctl        CLI
docs/                ADRs, format notes, clean-room policy, performance report
```

## Documentation

- [Performance report](docs/performance.md): budgets and measured numbers
- [Shader authoring](docs/shaders.md)
- [Clean-room policy](docs/CLEANROOM.md): required reading for contributors
- Format notes: [PKG](docs/formats/pkg.md), [TEX](docs/formats/tex.md), [scenes](docs/formats/scene.md)
- [Architecture decisions](docs/adr/)

## License

MIT. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
