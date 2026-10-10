# Abstract texture library

A shader-texture library cut from Screaming Brain Studios' *Seamless Abstract
Texture Pack* (100 seamless 512×512 RGB PNGs). Decided on #1534.

## Provenance and licence

- Source archive, committed as the provenance copy and never imported (Godot
  ignores `.rar`): `assets/sbs_-_abstract_texture_pack_-_512x512.rar`.
- Licence: CC0 1.0 Universal — the archive's `License.txt` reads *"All Screaming
  Brain Studios assets have been released under the CC0/Public Domain License"*.
  No credit is owed; `assets/CREDITS.md` carries a line anyway.

## The two rules

1. **A pack texture is a mask, tinted in-shader.** A shader reads the texture's
   luminance (or one channel) as a pattern and takes every colour from our
   palette — entity tint, a material tint uniform, or an `Emissive` tier
   (`docs/domain/hdr-color.md`). The files stay RGB and unmodified; their raw
   rainbow never reaches the screen. Why: one palette owner, and glow only
   through named tiers — a texture's colours would bypass both.
2. **Only a texture with a consumer is imported.** Extract a pick into
   `assets/textures/abstract/`, keeping its original file name, in the same
   change that wires it up. `test/unit/test_abstract_texture_library.gd` fails
   on any PNG there whose `res://` path no `.tres`/`.tscn`/`.gdshader`/`.gd`
   mentions.

## Import settings

Mipmaps **on** (sampled far below 512 px — without mips they shimmer), lossless
compression (the 2D default), filter linear. After the first import, set
`mipmaps/generate=true` in the `.png.import` and run `mise run refresh` again.
Tiling is the shader's `repeat_enable` sampler hint, not an import flag.

## Browsing and extracting

```bash
S=$(mktemp -d)            # a scratch dir — never commit the sheet
bsdtar -xf assets/sbs_-_abstract_texture_pack_-_512x512.rar -C "$S"
magick montage "$S"/512x512/*.png -colorspace Gray -set label '%t' -pointsize 9 \
  -tile 10x -geometry 96x96+2+2 "$S/sheet.png"     # luminance: what a mask sees
cp "$S/512x512/Abstract_512x512-NN.png" assets/textures/abstract/
```

Judge a pick by its luminance at node scale, not its colours. A shader tuned
around mid-grey thresholds wants mean ≈ 0.35–0.65 and a standard deviation
above ~0.15:
`magick <png> -colorspace Gray -resize 60x60 -format "%[fx:mean] %[fx:standard_deviation]\n" info:`

## Imported textures

| File | NN | Look (luminance) | Consumer |
|---|---|---|---|
| `Abstract_512x512-28.png` | 28 | cellular blobs, high contrast (mean 0.54, sd 0.18) | `skill_node/visuals/blocker_blob_material.tres` `layer_a` — Dormant Core goo body + damage cracks |
| `Abstract_512x512-11.png` | 11 | diagonal stripe bands (mean 0.48, sd 0.16) | `skill_node/visuals/blocker_blob_material.tres` `layer_b` — edge wobble + streak/tear highlights |

Changing a pick is a sampler slot in the consuming material; delete the old
PNG and its `.import` in the same change if nothing else uses it.
