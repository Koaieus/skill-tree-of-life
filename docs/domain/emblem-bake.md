# Emblem offline bake: icon art → CARVE LUT

Offline-bake pipeline that turns an icon's silhouette into the same
height+gradient LUT encoding InnerDisk's gem carve already uses (see
`.claude/rules/skill-node-visuals.md`'s "diamond crown" section for why a
LUT bake, not a per-pixel analytic formula, is the right tool once a shape
stops being a fixed regular polygon).

**Two bakers feed the same encoding.** The production pipeline
(`tools/bake_svg_sdf.py`, driven by `mise run icons:update`) computes the
LUT from the icon's **SVG source** via msdfgen's true signed distance field
— no pixel rasterization anywhere in the path. `TextureCarveShape.bake_lut()`
(`skill_node/visuals/emblem/texture_carve_shape.gd`) is the retained fallback
for authored raster icons outside the SVG pipeline (editor "Bake" button).

**#246 was offline-bake only** — the baked LUT asset + the shape resource that
carries it, touching no render code. The display half (the atlas packing, the
`lighting.gdshaderinc` decode, the instance-uniform slice index, and the
`icons:update` extension that emits it all) landed in **#247**; see
"Packing + decode" below.

## Derivation

Source icons (`assets/icons/spells/*.png`) are flat monochrome silhouettes
with the background alpha-stripped — **only alpha is meaningful**; luminance
carries no interior height.

### SVG pipeline (production, `tools/bake_svg_sdf.py`)

1. **Paths.** Parse the SVG, keep every `<path d="...">`, drop the game-icons
   background rect (`M0 0h512v512H0z`). Concatenate the rest into a *single*
   `<path>` — msdfgen loads only the **last** path in the file, and SVG
   subpaths are just more `M` commands, so one element carries them all.
2. **SDF.** `msdfgen sdf -apxrange -4 256 -autoframe -dimensions 256 256`
   produces the true Euclidean signed distance field from the vector paths.
   The asymmetric pixel range gives a 4px exterior budget (the smooth mask's
   AA margin) and a 256px interior range; autoframe fits the shape to the
   248px center — the same footprint the old raster bake had. Output via
   `.fl32` (16-byte header + raw float32 rows, y-up → flipped to the PNG's
   y-down).
3. **Drop field (the dent).** Same intaglio formula as the raster baker:
   `drop = DEPTH * (max(sdf, 0) / max_interior_sdf)`, 0 at the silhouette
   boundary ramping to `DEPTH` at the shape's medial axis.
4. **Gradient.** `np.gradient` of the drop field, scaled by
   `TEXELS_PER_UNIT_P` (drop-per-unit-p, matching the shader's `-p / z_dome`
   disk space — see #318).
5. **Mask.** The A channel is the **signed distance itself** (1px-linear,
   clamped): `a = clamp(sdf_px * 0.5 + 0.5, 0, 1)`. Antialiased — the #247
   decode treats alpha as a blend weight, so the outline smooths with no
   shader involvement.

Dependencies: `msdfgen` (dev tool built once via `mise run tools:bootstrap` —
no packaged Linux binary; needs tinyxml2/freetype/libpng dev libs) and a
Python venv (`numpy` + `Pillow`) created by `icons:update` in the XDG cache.
The venv's `numpy.gradient` border handling (one-sided) matches
`_gradient_at` exactly.

### Raster fallback (`TextureCarveShape.bake_lut`)

1. **Inside-mask.** Sample the source's alpha at each LUT texel (nearest,
   not bilinear — keeps the silhouette boundary a crisp threshold); texels
   above `ALPHA_THRESHOLD` are "inside".
2. **Distance transform.** A two-pass chamfer distance transform (forward +
   backward sweep over the 8-neighborhood, 1 / √2 weights) gives every inside
   texel its approximate Euclidean distance, in texels, to the nearest
   outside texel. Deterministic and O(N) — no per-boundary-pixel brute force.
3. **Drop field (the dent).** Normalized per-icon: `drop = DEPTH *
   (distance / max_distance)`, where `max_distance` is the largest distance
   found anywhere inside this particular icon's mask. 0 at the silhouette
   boundary, ramping to the full `DEPTH` at the texel(s) farthest from any
   edge (the shape's medial axis) — an **intaglio** dent (cut *into* the
   dome), consistent with the existing CARVE metaphor (the gem cut and the
   weld bowl are both dents too).
4. **Gradient.** Central-difference of the drop field (one-sided at the
   LUT's own border), in drop-per-texel units.

## Encoding contract

Mirrors `InnerDisk._build_gem_lut` / `sn_gem_bump` **exactly** — this is the
interface #247's shader decode consumes, so the two halves must stay in
lock-step:

- `FORMAT_RGBA8`, square, `LUT_SIZE = 256` (the SVG baker and
  `TextureCarveShape.LUT_SIZE` are in lock-step; the gem LUT on InnerDisk is
  its own size — the two samplers are independent),
  `generate_mipmaps()`.
- **R** = `drop / DEPTH` (0..1). Drop is positive — a dent, not a bump.
- **GB** = `grad.xy / GRAD_SCALE`, remapped `-1..1 → 0..1`.
- **A** = 1 inside the silhouette mask, else 0 (SVG pipeline: smooth 0..1
  ramp from the signed distance — see above).

`LUT_SIZE` / `DEPTH` / `GRAD_SCALE` / `ALPHA_THRESHOLD` are `const`s on
`TextureCarveShape`. **If #247's decode constants (the `sn_*_bump` family's
`SN_TEXTURE_DEPTH_SCALE` / `SN_TEXTURE_GRAD_SCALE` equivalents in
`lighting.gdshaderinc`) ever drift from these, the bake and the decode
disagree silently** — same failure mode `inner_disk.gd`'s class doc already
warns about for the gem LUT. Keep them numerically identical.

## Usage

```gdscript
var shape := TextureCarveShape.new()
shape.source_texture = preload("res://assets/icons/spells/lightning_bolt.png")
# Editor: click the "Bake" tool button. Headless / CLI: call directly —
shape.baked_lut = TextureCarveShape.bake_lut(shape.source_texture)
var spec := shape.carve(EmblemSpec.PRIORITY_SPELL, &"spell")  # carries baked_lut, not the raw icon
```

The bake writes a committed asset per source (deterministic — baking the
same source twice yields byte-identical images, see
`test/unit/test_texture_carve_bake.gd`), git-reviewable and zero runtime
cost. `assets/emblem_luts/lightning_bolt.png` (+ `.import`) is the first
committed proof, baked from `assets/icons/spells/lightning_bolt.png`.

**Why a tool button, not an `EditorPlugin`:** an `EditorPlugin` registration
edits `project.godot`, a file shared across every parallel unit of this
issue's swarm — avoided for file-disjointness. The bake logic itself lives in
the headless-callable `static func bake_lut()`; the tool button
(`@export_tool_button`) is a thin wrapper over it, which is also what lets
the acceptance test drive the bake without the editor.

## Packing + decode (#247)

The bake above produces one LUT per icon. The display side has to let *many*
distinct baked shapes coexist on screen without breaking InnerDisk's shared
`ShaderMaterial` — the thing that batches every node in the level into one draw
call. A sampler **cannot be an `instance uniform`**, so "one `sampler2D` per
shape" would force either a per-node duplicate material (batching gone) or one
plain uniform per shape (and #172's instance-uniform slot ceiling is exactly
what that spends). So:

- Every baked LUT is stacked into **one** `sampler2DArray` bound as a plain
  uniform on the shared material.
- The only per-node value is an **int slice index** — which an `instance
  uniform` carries fine. Adding the 50th baked shape adds a *slice*, not a
  *slot*; that's what makes this scale past #172.

Concretely:

| Artifact | What it is |
|---|---|
| `assets/emblem_luts/<name>.png` | the per-icon baked LUT — reviewable, and what a `TextureCarveShape.baked_lut` points at |
| `assets/emblem_luts/carve_atlas.png` (+ `.import`) | all LUTs stacked vertically, imported as a `CompressedTexture2DArray` |
| `assets/emblem_luts/carve_atlas.tres` | the [CarveAtlas] manifest: slice index → LUT `res://` path |
| `sn_texture_bump` (`lighting.gdshaderinc`) | the decode; `SN_TEXTURE_DEPTH_SCALE` / `SN_TEXTURE_GRAD_SCALE` are the other half of the encoding contract above |

`InnerDisk.set_carve()` resolves a `TextureCarveShape` to its slice by the
baked LUT's own `resource_path`, so **no shape carries a hand-authored index**
that could drift out of step with the packing. A LUT the atlas doesn't carry
warns and falls back to the empty dome rather than rendering the wrong glyph.

Regenerate with `mise run icons:update` — the bake/pack is the last stage of
that task rather than a separate one, because an atlas that can go stale
against the art it's baked from eventually will.

### Two gotchas worth not rediscovering

- **`ResourceSaver.save()` on a `Texture2DArray` is a trap.** It reports `OK`
  and writes a file that reloads with **zero layers** (verified on 4.7 — the
  images don't survive serialization). Hence the stacked-PNG + importer route.
- **The `2d_array_texture` importer is also the *safe* route**, not just the
  working one: unlike the plain `texture` importer it exposes no
  `process/fix_alpha_border`, which would rewrite the RGB of fully-transparent
  texels — and here **RGB is the payload**, alpha is only the mask. With
  `compress/mode=0` every imported layer is byte-identical to `bake_lut()`'s
  output (verified under `--rendering-driver opengl3`; `get_layer_data()`
  returns null under the dummy renderer, so this can't be asserted from GUT —
  `test/unit/test_carve_atlas.gd` checks the committed PNG instead).

## Parked for later

- **WIS "exudes wealth" motif:** new archetype art authoring, not this
  pipeline. This bake proves against an existing spell icon; bespoke art is a
  separate future content issue.
