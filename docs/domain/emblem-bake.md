# Emblem offline bake: icon art → CARVE LUT

Offline-bake pipeline that turns an icon's silhouette into the same
height+gradient LUT encoding InnerDisk's gem carve uses (the gem crown section
below explains why a LUT bake, not a per-pixel analytic formula, is the right
tool once a shape stops being a fixed regular polygon).

**Two bakers feed the same encoding.** The production pipeline
(`tools/bake_svg_sdf.py`, driven by `mise run icons:update`) computes the LUT from
the icon's **SVG source** via msdfgen's true signed distance field — no pixel
rasterization anywhere in the path. `TextureCarveShape.bake_lut()`
(`skill_node/visuals/emblem/texture_carve_shape.gd`) is the retained fallback for
authored raster icons outside the SVG pipeline (editor "Bake" button).

The per-icon bake produces the LUT asset and the shape resource that carries it;
the display half (atlas packing, the `lighting.gdshaderinc` decode, the
instance-uniform slice index) is "Packing + decode" below.

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
   disk space).
5. **Mask.** The A channel is the **signed distance itself** (1px-linear,
   clamped): `a = clamp(sdf_px * 0.5 + 0.5, 0, 1)`. Antialiased — the
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

Mirrors `InnerDisk._build_gem_lut` / `sn_gem_bump` **exactly**; the shader decode
consumes it, so the two halves stay in lock-step:

- `FORMAT_RGBA8`, square, `LUT_SIZE = 256` (the SVG baker and
  `TextureCarveShape.LUT_SIZE` are in lock-step; the gem LUT on InnerDisk is
  its own size — the two samplers are independent),
  `generate_mipmaps()`.
- **R** = `drop / DEPTH` (0..1). Drop is positive — a dent, not a bump.
- **GB** = `grad.xy / GRAD_SCALE`, remapped `-1..1 → 0..1`.
- **A** = 1 inside the silhouette mask, else 0 (SVG pipeline: smooth 0..1
  ramp from the signed distance — see above).

`LUT_SIZE` / `DEPTH` / `GRAD_SCALE` / `ALPHA_THRESHOLD` are `const`s on
`TextureCarveShape` (`DEPTH` 0.35, `GRAD_SCALE` 3.0). **The decode constants
`SN_TEXTURE_DEPTH_SCALE` (0.35) / `SN_TEXTURE_GRAD_SCALE` (3.0) in
`lighting.gdshaderinc`'s `sn_texture_bump` must stay numerically identical**, or
the bake and the decode disagree silently. They are separate from the `SN_GEM_*`
pair so the two glyph families tune independently.

## Usage

```gdscript
var shape := TextureCarveShape.new()
shape.source_texture = preload("res://assets/icons/spells/lightning_bolt.png")
# Editor: click the "Bake" tool button. Headless / CLI: call directly —
shape.baked_lut = TextureCarveShape.bake_lut(shape.source_texture)
var spec := shape.carve(EmblemSpec.Priority.SPELL, &"spell")  # carries baked_lut, not the raw icon
```

The bake writes a committed asset per source (deterministic — baking the same
source twice yields byte-identical images, see
`test/unit/test_texture_carve_bake.gd`), git-reviewable and zero runtime cost,
e.g. `assets/emblem_luts/lightning_bolt.png` (+ `.import`).

The bake is a `@export_tool_button` rather than an `EditorPlugin` (a plugin edits
`project.godot`, which every parallel unit shares); it is a thin wrapper over the
headless-callable `static func bake_lut()`, which is also what lets a test drive
the bake without the editor.

**The button refuses to clobber a committed LUT.** The spell defs point
`baked_lut` at the pipeline-baked assets in `assets/emblem_luts/`; if the
button blindly re-baked, a stray click would swap the pristine SVG SDF for
the degraded raster chamfer. When `baked_lut` already resolves to a committed
asset (non-empty `resource_path`), the button warns and does nothing — clear
`baked_lut` first to re-bake an authored icon from `source_texture`.

## Packing + decode

The bake above produces one LUT per icon. The display side has to let *many*
distinct baked shapes coexist on screen without breaking InnerDisk's shared
`ShaderMaterial` — the thing that batches every node in the level into one draw
call. A sampler **cannot be an `instance uniform`**, so "one `sampler2D` per
shape" would force either a per-node duplicate material (batching gone) or one
plain uniform per shape (which spends the instance-uniform slot ceiling). So:

- Every baked LUT is stacked into **one** `sampler2DArray` (`carve_atlas`) bound
  as a plain uniform on the shared material.
- The only per-node value is an **int slice index** (`carve_slice`, plus
  `carve_slice_b` for ties) — which an `instance uniform` carries fine. Adding the
  50th baked shape adds a *slice*, not a *slot*; that is what scales past the
  instance-uniform slot ceiling. The payoff is that ceiling, authorability and
  arbitrary art, not fps (node shaders already batch to ~1-2 draw calls).

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

Regenerate with `mise run icons:update`; the bake/pack is the last stage of that
task so the atlas cannot go stale against its art.

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

## Gem crown LUT

`InnerDisk`'s gem-cut glyph (the `SkillDustAddon` relic's, `carve_shape =
GemCarveShape.SHARED`) is the same height-field glyph family as the polygon carve
but baked, because the shape is identical on every relic: no per-instance
parameter varies it, so recomputing its `atan2`/`mod`/facet math per pixel buys
nothing. The polygon varies per node (`sides`/`radius`), so it stays an analytic
per-pixel formula (`sn_polygon_facet`/`sn_bowl_drop`).

- **Bake.** `InnerDisk._build_gem_lut()` (lazy `static var _gem_lut`) bakes a
  128 px side-view cut once (flat table, tapering crown shoulders to the girdle, a
  pavilion to the culet; proportions are the `GEM_*_RATIO` consts); `sn_gem_bump()`
  decodes it per pixel. Baked with mipmaps and sampled `filter_linear_mipmap`: the
  LUT is minified (~2x) against the on-screen disk, and mips box-filter the facet
  creases instead of aliasing them.
- **Batching survives.** The LUT is identical for every InnerDisk, so it is a plain
  `uniform sampler2D gem_lut` on the one shared `ShaderMaterial`, set once in
  `_ready()`. Only a per-instance-varying sampler forces the duplicate-material
  path.
- **One implementation, not a CPU twin.** The GDScript bake is the single source of
  the geometry; the shader only decodes the texel, so there is nothing to drift.
- **Encoding.** R = `drop / SN_GEM_DEPTH_SCALE`, GB = `grad / SN_GEM_GRAD_SCALE`
  remapped -1..1 -> 0..1, A = the silhouette's antialiased coverage (1 well inside,
  ramping to 0 over `GEM_EDGE_AA_TEXELS`). The shader uses A as a blend weight,
  never a `> 0.5` cutoff (a hard alpha plus a hard branch stair-steps the outline;
  `test_carve_shape.gd` `test_gem_edge_coverage_is_antialiased`). The bake's
  `GEM_*` consts and the decode's `SN_GEM_*` consts are two halves of one encoding.
- **Raster fallback alpha is hard.** `TextureCarveShape.bake_lut()` writes a hard
  `1.0`/`0.0` alpha (same R/GB encoding); the decode treats alpha as a blend
  weight, so a hand-baked raster outline stair-steps until its bake gets the same
  coverage ramp (a one-sided change, no shader edit). The SVG pipeline already
  emits the smooth ramp.
- **When to use a LUT.** Only when the shape is fixed across every instance that
  shows it; per-instance variation (archetype, sides, depth) has to stay analytic,
  or ride the atlas slice index.

## Parked

- **WIS "exudes wealth" motif:** new archetype art authoring, a separate content
  issue, not this pipeline.
