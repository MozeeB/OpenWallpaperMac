# ADR 0004: Per-Space wallpapers through a read-only private API

**Status:** accepted

## Context

Users want a different wallpaper (or rotation) on each macOS Space. AppKit has no public way to
identify Spaces: `NSWorkspace.activeSpaceDidChangeNotification` says *that* the Space changed, not
*which* Space is active, and Spaces have no public identifiers.

## Decision

- Read Spaces with the window server's `CopyManagedDisplaySpaces` (SkyLight `SLS...`, falling back to
  CoreGraphics `CGS...`). It is read-only, needs no special permission or disabled SIP, and returns
  each display's Spaces with a persistent `uuid` and the active Space. The original first desktop has an
  empty `uuid`, so its `ManagedSpaceID` is used instead.
- Resolve the symbols at runtime with `dlsym`. If they are missing, `SpaceMonitor.isAvailable` is false
  and the UI hides every per-Space option; nothing else changes.
- Keep one wallpaper window per display on all Spaces. On a Space switch the coordinator re-evaluates
  the display's effective assignment (the Space's own, else the display default) and cross-fades.
- Rotations are tracked per slot (display + optional Space). Rotations of Spaces that are not showing
  hold their position.
- Assignments persist the Space key (`space` field, optional for backward compatibility).

## Consequences

- Private API: not allowed on the Mac App Store. That distribution channel was already ruled out
  (ADR 0002). The call has been stable for many macOS releases but could change; the fallback keeps
  the app working without per-Space support.
- During the Space swipe animation the old wallpaper is visible until the switch completes, then the
  new one fades in.
