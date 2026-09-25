# Writing shader wallpapers

A shader wallpaper is a folder with `wallpaper.json` and a `.metal` file containing one function:

```metal
float4 mainImage(float2 fragCoord, constant OWUniforms& u) {
    float2 uv = fragCoord / u.iResolution.xy;          // (0,0) bottom-left
    float bass = owAudio(u, 2);                         // 0…1, band 0…63
    return float4(uv, 0.5 + 0.5 * sin(u.iTime + bass), 1.0);
}
```

| Available | Meaning |
|---|---|
| `u.iResolution` | drawable size in pixels (`xy`), `z` = 1 |
| `u.iTime`, `u.iTimeDelta`, `u.iFrame` | seconds while playing, last frame delta, frame index |
| `u.iDate` | year, month (0-based), day, seconds since midnight |
| `u.iMouse` | reserved (zero; wallpapers do not receive clicks) |
| `owAudio(u, band)` | smoothed spectrum, average of both channels; needs `"usesAudio": true` |
| `prop_<key>` | `float4` per user property: numbers/bools in `.x`, colours in `.rgb` |

```json
{
  "title": "My Shader",
  "type": "shader",
  "entry": "shader.metal",
  "usesAudio": true,
  "properties": {
    "speed": { "type": "slider", "text": "Speed", "value": 1, "min": 0, "max": 4, "step": 0.1 },
    "tint":  { "type": "color",  "text": "Tint",  "value": "0.2 0.4 1" }
  }
}
```

Porting from Shadertoy: `vec2/3/4` → `float2/3/4`, `mix`/`fract` work as-is, `mod(a,b)` → `fmod` (sign
differs for negatives), `texture` channels are not supported yet.

Compile errors are reported with the line number in *your* file. A shader that stalls the GPU is stopped
by a watchdog and replaced by its preview image.

Test locally without installing: `swift run owctl render <folder> --out preview.png`.
