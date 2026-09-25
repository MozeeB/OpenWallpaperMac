# Clean-room policy

OpenWallpaperMac is MIT-licensed. To keep it that way, Wallpaper Engine compatibility is implemented
from **observable behaviour and public format descriptions only**.

## Rules for contributors

1. **Do not read, copy, translate or paraphrase source code from `linux-wallpaperengine`** (GPL-3.0) or
   any other GPL/LGPL/proprietary Wallpaper Engine implementation. If you have studied that code, do not
   contribute to `Sources/OWFormats/Scene`, `Sources/OWScene` or the effect registry.
2. Do not include Wallpaper Engine's built-in shaders, effect files or assets, even in modified form.
   Effects are re-implemented natively in our own MSL (`Sources/OWScene/ScenePipelines.swift`).
3. Do not commit Workshop content (or anything derived from it) as fixtures. Tests use
   `SyntheticScene` (original, generated content). Local compatibility checks against your own library
   are opt-in and never uploaded.
4. Format knowledge lives in `docs/formats/*.md`, written in our own words, citing public sources.
   Porting code from permissively licensed references (e.g. RePKG, MIT) requires attribution in
   `THIRD_PARTY_NOTICES.md`.
5. Pull requests touching scene/format code must include this attestation in the description:

   > I have not referred to GPL-licensed Wallpaper Engine implementations while writing this change.

## Naming

The product never uses "Wallpaper Engine" in its name or icon. Describing compatibility
("imports Wallpaper Engine projects") is fine.
