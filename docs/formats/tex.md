# TEX textures (`materials/*.tex`)

Little-endian. Strings marked `\0` are NUL-terminated ASCII.

```
"TEXV####\0"  "TEXI####\0"
Int32 format        0 RGBA8888 · 4 DXT5 · 6 DXT3 · 7 DXT1 · 8 RG88 · 9 R8
Int32 flags         1 no-interpolation · 2 clamp UVs · 4 animated (GIF) · 32 video
Int32 textureWidth  Int32 textureHeight   (power-of-two storage)
Int32 imageWidth    Int32 imageHeight     (visible area, top-left of storage)
UInt32 unused
"TEXB####\0"        container version 1…4
Int32 imageCount
[v3+] Int32 imageFormat   -1 = raw pixels, otherwise an encoded image file (PNG, JPEG…)
[v4]  Int32 isMP4
per image: Int32 mipmapCount, then per mipmap:
  [v4] Int32, Int32, "condition\0", Int32
  Int32 width, Int32 height
  [v2+] Int32 isLZ4, Int32 decompressedSize
  Int32 byteCount, bytes
[animated] "TEXS####\0" Int32 frameCount [v3: Int32 w, Int32 h]
  per frame: Int32 image, Float frameTime, x, y, width, (unused), (unused), height
             (floats in v2+, Int32 in v1)
```

LZ4 payloads are raw LZ4 blocks, decoded with Apple's Compression framework (`COMPRESSION_LZ4_RAW`).

## Handling

- BCn (DXT) data is uploaded to Metal still compressed (`bc1/bc2/bc3_rgba`); `BCnDecoder` exists for PNG
  export and tests.
- R8/RG88 use texture swizzles to appear as grey (+alpha).
- Limits: dimensions ≤ 16 384, ≤ 4 096 images, ≤ 16 mipmaps, ≤ 512 MB decompressed; LZ4 output must
  match the declared size exactly.
- MP4 textures are recognised but not rendered (scene reports partial support).
