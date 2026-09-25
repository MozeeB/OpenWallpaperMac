# ADR 0003: Phased, clean-room scene compatibility with graceful fallback

**Status:** accepted

## Decision

Render Wallpaper Engine scenes with our own Metal pipeline instead of translating their shaders:

1. S1: image layers, transforms, blend modes, orthographic camera, parallax.
2. S2: natively re-implemented common effects, combined in one pass (`EffectRegistry`).
3. S3: CPU particle simulation, instanced quads.

`SceneSupportAnalyzer` classifies every imported scene as full / partial / preview-only; preview-only
scenes (and any runtime failure) show the project's `preview` image instead.

## Alternatives rejected

- Porting linux-wallpaperengine: GPL-3.0, incompatible with MIT.
- Translating WE GLSL via glslang + SPIRV-Cross: heavy dependencies and a new untrusted-code surface;
  may be revisited behind a separate ADR.
