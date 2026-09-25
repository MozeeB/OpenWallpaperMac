# Performance

## Design

- **Render only what is visible.** Per-display pause/suspend from `PowerPolicy` (fullscreen apps,
  occlusion, battery, Low Power Mode, thermal, lock, sleep). Paused = display link stopped;
  suspended = renderer torn down (decoder/GPU memory freed).
- **Frame pacing.** Default 60 fps (30 or 15 selectable), 15 fps on battery, thermal caps (fair -> 30, serious -> 15,
  critical -> suspend). Static scenes render one frame and stop.
- **Decode once.** One `AVQueuePlayer` per video file shared across displays.
- **Cheap compositing.** Opaque, shadowless windows; <= 2 drawables; optional render scale for GPU
  renderers (Settings > Performance).
- **No hot-path allocation.** Particle update in place; instance buffers triple-buffered and reused;
  audio IO thread only copies into a lock-free ring.

## Measured (M-series MacBook, macOS 26.6, 2 displays: 3024x1964 built-in + 1920x1080 external)

Live app, Release build, 30 fps, `ps`/`top` samples over ~10 s:

| Wallpaper | App CPU (both displays) | WindowServer increase | App RSS |
|---|---|---|---|
| Idle (library window open, no wallpaper) | 0.0% | n/a | 94 MB |
| 4K HEVC video (shared decoder) | ~3.1% (+~2.3% VTDecoderXPC) | ~+13% | 77 MB |
| Plasma shader (native resolution) | ~5.2% | ~+20% | 71 MB |
| Synthetic scene (layer + shake + particles) | ~5.1% | n/a | 72 MB |

Offscreen `owctl bench` at 3840x2160 (rendering cost only, no presentation):

| Wallpaper | CPU ms / frame | Projected CPU @ 30 fps |
|---|---|---|
| Plasma shader | 0.39 | 1.2% |
| Synthetic scene | 0.36 | 1.1% |
| 4K HEVC decode via AVAssetReader | 1.28 | 3.8% (copies frames; AVPlayer path is cheaper) |

### Real-world clip: 4K H.264, 60 fps, 24.7 Mbit/s, AAC audio (15 s loop)

Controlled A/B on the main display (app CPU + WindowServer increase):

| Strategy | App | WindowServer increase | Total |
|---|---|---|---|
| Play file as-is | 4.6% | ~+23% | ~28% |
| Video-only composition (audio never processed) | 3.4% | ~+9% | ~12% |
| Video-only + 30 fps output cap (**shipped**) | 5.2% | ~+3% | **~8%** |

The frame-rate cap applies to video too (60 fps default, 15 on battery; choose 15/30/60 from the menu
bar or Settings). Clips at or below the cap play natively with no composition overhead. In the app on two
displays this clip uses ~7.6% app CPU capped to 30 fps and **~6.1% at native 60 fps** (frame dropping has
its own cost); WindowServer load was similar in both runs.

## Against the budgets

| Budget (per display) | Target | Result |
|---|---|---|
| Video app CPU | <= 3% | Met: ~1.6% per display (4K30 HEVC); Over: ~3.5% per display for a 4K60 24.7 Mbit/s H.264 clip |
| Shader app CPU | <= 2% | Over: ~2.6% per display, dominated by per-frame drawable/present overhead, not shader work (1.2%) |
| Scene app CPU | <= 5% | Met: ~2.6% per display |
| Paused | 0% | Met: (display link stopped; unit-tested; idle measured 0.0%) |
| WindowServer increase | <= 15% hard, <= 10% stretch | Met: hard limit met (~6.5% video, ~10% shader per display); stretch met for video only |

Levers when over budget: lower the frame cap (15 fps halves presentation cost), reduce render scale, or
enable "Pause when on battery".

## How to measure

```bash
swift run -c release owctl bench path/to/wallpaper --width 3840 --height 2160
```

```bash
top -l 5 -s 2 -stats pid,cpu,rsize,command | grep -E "OpenWallpaperMac|WindowServer"
```

For energy: Activity Monitor > Energy, or `sudo powermetrics --samplers cpu_power,gpu_power -i 2000 -n 30`
with and without a wallpaper running.
