# ADR 0002: Unsandboxed Developer ID build; no lock-screen video

**Status:** accepted

## Context

Core Audio process taps are unreliable inside the App Sandbox. Lock-screen video on macOS requires
private frameworks (WallpaperExtensionKit) or replacing Apple's aerial files, both of which break across
OS updates and are disallowed on the Mac App Store.

## Decision

- Ship a hardened-runtime, notarized Developer ID build via GitHub Releases (`scripts/release`).
- Do not use private APIs or aerial-file swapping. Instead, sync a still frame to the regular desktop
  picture (`NSWorkspace.setDesktopImageURL`) so Mission Control, Space swipes, the menu bar tint and the
  lock screen match; restore the user's original wallpaper on quit (backed up to disk).

## Consequences

A future sandboxed App Store variant is possible without audio capture.
