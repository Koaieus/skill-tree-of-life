# Emblem offline bake (#246): icon art → CARVE LUT

Offline-bake pipeline that turns an authored icon's alpha silhouette into the
same height+gradient LUT encoding InnerDisk's gem carve already uses (see
`.claude/rules/skill-node-visuals.md`'s "diamond crown" section for why a
LUT bake, not a per-pixel analytic formula, is the right tool once a shape
stops being a fixed regular polygon). Lives entirely in
`skill_node/visuals/emblem/texture_carve_shape.gd` (`TextureCarveShape`).

**Scope: offline-bake only.** This produces the baked LUT asset + the shape
resource that carries it. It does **not** touch the live render path —
`InnerDisk`'s `TEXTURE` carve branch still falls back to an empty dome (see
`skill_node/visuals/inner_disk.gd`'s `set_carve()`). Wiring a per-node-varying
LUT into InnerDisk's shared-material batching (an instance-uniform sampler
slice index, `lighting.gdshaderinc` decode, the atlas story) is #247's job,
which is blocked on this landing.

## Derivation

Source icons (`assets/icons/spells/*.png`) are flat monochrome silhouettes
with the background alpha-stripped — **only alpha is meaningful**; luminance
carries no interior height.

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

- `FORMAT_RGBA8`, square, `LUT_SIZE = 128` (matches `InnerDisk.GEM_LUT_SIZE`),
  `generate_mipmaps()`.
- **R** = `drop / DEPTH` (0..1). Drop is positive — a dent, not a bump.
- **GB** = `grad.xy / GRAD_SCALE`, remapped `-1..1 → 0..1`.
- **A** = 1 inside the silhouette mask, else 0.

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

## Parked for later

- **WIS "exudes wealth" motif:** new archetype art authoring, not this
  pipeline. This bake proves against an existing spell icon; bespoke art is a
  separate future content issue.
- **Render / empty-dome fallback / atlas / `icons:update` extension:** #247.
