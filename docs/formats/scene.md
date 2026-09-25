# Scene projects

A Wallpaper Engine project folder contains `project.json` and either loose files or `scene.pkg`.
`LayeredAssetSource` reads the package first, then the folder.

## project.json (subset used)

`title`, `type` (`scene` | `video` | `web`; `application` is rejected), `file` (entry), `preview`,
`general.properties` (user properties), `general.supportsaudioprocessing`.

Property types mapped by `PropertyParser`: `bool`, `slider` (`min`/`max`/`step` or `precision`),
`color` (`"r g b"`), `combo` (`options: [{label, value}]`), `textinput`. Label-only `text` and file
pickers are skipped. Native `wallpaper.json` manifests use the same property shape.

## scene.json

- `general`: `clearcolor`, `orthogonalprojection {width,height}`, `cameraparallax`,
  `cameraparallaxamount`, `cameraparallaxdelay`, `cameraparallaxmouseinfluence`
- `objects[]`, drawn in order (first = back):
  - image layer: `image` (model path), `origin`, `scale`, `angles` (radians, Z used), `size`,
    `visible`, `alpha`, `color`, `parallaxDepth`, `effects[]`
  - particle layer: `particle` (system path), transform, `visible`
  - anything else (sound, light, text, 3D model) is skipped and reported
- Values are numbers, `"x y z"` strings, or user bindings `{"user": key, "value": fallback}`.

Coordinates: origin bottom-left, y up, units of the orthographic projection. Layer origin is its centre.

## models / materials

`models/*.json`: `material`, optional `width`/`height`, `fullscreen`, `puppet` (unsupported → partial).
`materials/*.json` first pass: `blending` (`translucent` | `additive` | `normal` | `disabled`),
`textures[0]` → `materials/<name>.tex`; `_rt_*` render targets are unsupported.

## Effects

Identified by folder name in `effects/<name>/effect.json` and reimplemented natively
(`EffectRegistry`): `scroll`, `shake`, `foliagesway`, `waterripple`, `waterwaves`, `pulse`, `tint`,
`opacity`, `blur`. Parameters come from `passes[0].constantshadervalues` with aliases and defaults.

## Particles

Emitters `boxrandom`, `sphererandom`; initialisers `lifetimerandom`, `sizerandom`, `velocityrandom`,
`colorrandom`, `alpharandom`, `rotationrandom`, `angularvelocityrandom`; operators `movement`
(gravity, drag), `alphafade`, `sizechange`. Others are listed as unsupported.
