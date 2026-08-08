# HDR colour authoring: the `I` slider, the `Color` class, and bloom

How >1.0 colours get authored, stored, and read by the bloom pass. Settled by
probing in Godot 4.7 against #371; the `I`/stop datapoints below are empirical,
not reasoned.

## `Color` has no intensity field

The `Color` class is four unbounded floats — `r, g, b, a`. There is no `I` /
intensity member, no metadata, no flag bit. A `Color(1.353, 1.353, 1.353)` is
*just* three channels at 1.353; nothing remembers that it came from a picker at
I=+1. This is why the `Color` doc page says nothing about intensity — `I` lives
on `ColorPicker.edit_intensity`, not on `Color`.

**Why it matters:** programmatic glow needs no engine API and no recovery of a
"hidden state." Write the value you want directly:

```gdscript
const GLOW_VALUE := Color(1.353256, 1.353256, 1.353256)  # white +1 stop
```

## What the `I` slider does

`ColorPicker` doc on `edit_intensity`:

> The intensity is applied as follows: convert the color to linear encoding,
> multiply it by `2 ** intensity`, and then convert it back to nonlinear sRGB
> encoding.

So `stored = sRGB_encode( sRGB_decode(base) × 2^I )`. `I` is in **EV stops**
(+1 = ×2 linear), not a multiplier on the stored value. The stored `Color`'s
rgb is the *sRGB-encoded* form; the *linear* value the bloom pass thresholds is
`2^I` for white.

## Verified: exact piecewise sRGB above 1.0

Godot uses the piecewise sRGB function extended above 1.0, not a `^2.2`
approximation. Confirmed by setting white at I=+1..+4 in the picker and reading
the stored `Color` back:

| I (stops) | linear (2^I) | encoded (observed) | `1.055×L^(1/2.4) − 0.055` |
|---|---|---|---|
| +1 | 2.0  | 1.353256 | 1.3531 ✓ |
| +2 | 4.0  | 1.825    | 1.8248 ✓ |
| +3 | 8.0  | 2.454    | 2.4544 ✓ |
| +4 | 16.0 | 3.294    | 3.2944 ✓ |

Closes the open caveat in #371's verdict: the >1.0 path is exact piecewise all
the way up. Encoded growth is ~×1.35/stop asymptotically; linear doubles per
stop.

## Bloom threshold is in linear space

`Environment.glow_hdr_threshold` is a *linear* luminance value. The renderer
linearizes the authored (encoded) `Color` back via the same inverse piecewise
before the glow pass — so a tier authored at `+1` stop really is linear 2.0 at
threshold time. `glow_hdr_threshold = 1.0` therefore means *"any I > 0 stops
blooms"* for white; for non-white bases hinge it on `sRGB_decode(channel) × 2^I`.

This is the clean mental model #371's `inert / label / value / alert` tiers
map onto: tiers are named by **stops**, not hand-picked floats.

| tier     | I      | linear (white) | encoded       |
|----------|--------|----------------|---------------|
| inert    | 0      | 1.0            | `1.0`         |
| label    | ~+0.5  | ~1.4           | ~`1.15`        |
| value    | +1     | 2.0            | `1.353256`    |
| alert    | +2     | 4.0            | `1.825`       |
| peak     | +3     | 8.0            | `2.454`       |

`peak` (`Emissive.PEAK`) is deliberately the only tier above `alert` — a
momentary ignition-flash overshoot that relaxes back down, never a resting
state. Reach for a hand-picked float above `alert` and you're re-deriving this
tier; name it instead.

### `glow_intensity` defaults to 0.3 — budget for it before tiering harder

Confirmed 2026-08-08 (#391 third follow-up): `Environment.glow_intensity`'s
class default is `0.3`, and `ui/theme/default_game_env.tres` didn't override it
until this fix. At that intensity, a tier that is genuinely above threshold
still reads as *faint-to-invisible* — which is easy to misdiagnose as "this
element still isn't blooming" and "fix" by cranking the element's own EV stops
past `alert`, one surface at a time, forever.

The concrete trap: `Emissive.at(base, ALERT)` on a **non-white, mid-saturation
base** (an archetype tint, not `Color.WHITE`) is nowhere near as bright as the
stop table above implies — sRGB decode is steep at midtones. A channel encoded
at `0.78` (a typical mid-tint archetype green) decodes to linear `~0.57`; at
`alert` (×4) that's linear `~2.26` — genuinely over the `1.0` threshold, but at
`glow_intensity = 0.3` the excess (`~1.26 × 0.3 ≈ 0.38`) barely registers.
Bumping to `+3`/`+4` stops (linear `~4.5`/`~9.1`) pushes the *same* weak
intensity into visible range — which is exactly the "nothing at ALERT, medium
at +3, great at +4" ladder that first surfaces this bug. **The fix is
`glow_intensity`, not another stop.** `default_game_env.tres` now sets it to
`1.2`.

### A thin/small element needs real pixel coverage, not just a hot colour

Bloom's wider mips (`glow_levels/4..7`) are built by repeatedly *downsampling*
the frame — a feature smaller than a handful of pixels is gone before it
reaches them, no matter how far over threshold its colour is. A `FanTrace` pad
sprite at an 8px texture × `0.4` scale (a ~3px dot) or a 2px `Line2D` hairline
both under-supply coverage for a "big" glow read; #391's fix widened the line
to 3px and grew the pad's resting scale to `0.65` (~5px) once `glow_intensity`
was no longer the confound. Judge sprite/stroke size against the *rendered*
pixel footprint at the scale it's actually shown, not the source texture size.

### Coverage is on-screen pixels — a world-space element's zoom level counts

The pixel-coverage floor above is about screen pixels, not world/texture
units, so anything drawn in world space (`Graph`'s `Edge`, not a screen-space
`Control`) changes its own coverage as the camera zooms. Confirmed empirically
(2026-08-08, `graph/edge.gd`'s `lit_glow_stops`) on a 2.5px-wide lit `Line2D`:
at `ALERT` (`2.0` stops) it only blooms near max camera zoom (~×2.0) — zoomed
out to 1× or less, the same line covers too few screen pixels and reads
inert. At `PEAK` (`3.0`) it blooms across most zoom levels but blows out at
max zoom, and `PEAK` is a named momentary-overshoot tier (see above), not
meant as a resting value. `2.5` stops — not a named tier, chosen by trial and
error with the sandbox as the feedback loop — is the empirical middle ground
for *this* line width; it isn't derived from anything reasoned and doesn't
generalize to a different width without retesting.

This raises two open questions this doc doesn't answer yet, because probing
beats reasoning here same as everywhere else in this file:

- Should a world-space element's glow (stops, or width) scale with camera
  zoom to hold screen-pixel coverage constant, rather than picking one
  compromise value that's under-lit at some zooms and over-lit at others?
- Is fading out at extreme zoom-out actually *fine* — a graph zoomed out far
  enough that lit edges are a handful of pixels each is arguably a case where
  losing the glow (but not the SDR colour) is the correct read, not a bug.

A screen-space `Control` (HUD panels, tooltip fan) doesn't have this problem —
its size is display pixels regardless of camera state — so this only applies
to `Graph`/`Edge`/`SkillNode` world-space visuals **at actual runtime.**

### The editor's 2D canvas zoom reintroduces the same problem for a `Control`

Confirmed 2026-08-08, tuning `ModSlabRow`/`SlabPanel`'s border glow: at 100%
editor zoom a value read as barely-lit; at 500% the same scene went solid
white. The claim above ("a screen-space Control's coverage is zoom-invariant")
is only true of the *game window* — the Godot 2D editor's zoom tool scales how
many actual framebuffer pixels a node's geometry rasterizes to within the
editor viewport's fixed resolution, exactly like a world-space camera zoom.
Authoring against that view reproduces the coverage-floor problem this section
describes for `Edge`, on a widget that will never see it at runtime.

**Judge glow on a screen-space `Control` at 100% editor zoom, or better, an
actual F6 run** — never a zoomed-in canvas view. A value that only reads right
zoomed in is over-tuned by roughly the amount the zoom inflated its coverage.

### Bloom-previewing a leaf `.tscn` opened standalone

A content scene like `ModSlabRow` or `SlabPanel` ships with no
`WorldEnvironment` of its own (only `scenes/game_root.tscn` and
`bloom_viewport.tscn` mount one, per "Where the pass is mounted" below) — so F6
("run current scene") on the bare file renders with no bloom, tempting a
stowaway `WorldEnvironment` node into the leaf scene itself. Don't: a scene
instanced N times (a fan panel holds one `ModSlabRow` per modifier) would
register N `WorldEnvironment`s in the real game's root viewport, last-writer-
wins, silently moving the shared dial.

The project sets `rendering/environment/defaults/default_environment` to
`ui/theme/default_game_env.tres` (`project.godot`) instead — the engine's
built-in fallback for any viewport whose `World2D` has no bound `Environment`.
Every real level already has an explicit `WorldEnvironment` (from
`game_root.tscn` or `bloom_viewport.tscn`), so this default only ever engages
for a scene that currently renders with none — F6 on a leaf UI scene, chiefly.
It costs nothing elsewhere and needs no per-scene node. It does **not** fix a
`SandboxHost` dock tab (gotcha #5 below disables environments at the viewport-
mode level, which a default-environment fallback can't override) — that still
needs a `bloom_viewport.tscn`-wrapped `%World`, which some panels (e.g.
`fan_live_panel.tscn`) already carry for their own content.

## Round-trips unclamped through `.tscn`

The property, the scene format, and the picker all carry >1.0 without clamp
(#371 W1). `theme_override_colors/font_color = Color(1.353256, …, 1)` saves,
reloads, and reads back identical. Also verified for `modulate` above 1.0.

The *ergonomic* way to author in-scene is the `I` slider; the *typed* way is
the `Color` constructor. They produce the same bytes.

## Generating tiers from a base + stops

When you'd rather name a tier by stops than commit the encoded float, use the
engine's own `Color.srgb_to_linear()` / `linear_to_srgb()` — same code path the
picker uses, so the output matches what would be hand-authored for the same
base + I:

```gdscript
func emissive(base: Color, stops: float) -> Color:
    var lin := base.srgb_to_linear() * pow(2.0, stops)
    return lin.linear_to_srgb()
```

Note these methods leave `a` untouched (alpha is always stored linear, never
encoded — see the `Color` doc on `a`), so a translucent emissive keeps its
alpha through the conversion.

## Equal stops, unequal glow: `Emissive.tint()` vs `Emissive.at()`

`Emissive.at(base, stops)` lifts whatever channel values `base` already has —
it does **not** equalize how bright different hues read at the same stop
count. Bloom thresholds per channel, and Rec.709 luma weights blue ten times
lower than green (`0.0722` vs `0.7152`), so a blue-dominant tint can sit at
its own max channel value and still contribute far less to the glow pass than
an evenly-spread or green/red-dominant tint at the same `stops`. Confirmed
empirically 2026-08-08 tuning `SlabPanel`'s stroke against real `StatDef`
archetype tints (not a placeholder grey — see the pixel-coverage section
above for that separate confound): STR's red (`Color(0.9451, 0.2689,
0.2453)`, linear luminance ≈0.23) and INT's blue (`Color(0.291, 0.5892,
1.0)`, linear luminance ≈0.31) needed visibly different raw `glow_energy` to
"properly bloom" even at the same nominal tier.

`Emissive.tint(base, stops)` fixes this for a **single-tint** element: it
rescales `base` to Rec.709 luminance 1.0 (keeping hue/chroma, discarding how
bright the source colour happens to be) before applying the stop lift. Two
properties fall out for free: `tint(WHITE, s) == at(WHITE, s)` exactly
(white's luminance is already 1.0), and at `stops = 0` any hue lands at
luminance 1.0 — the `INERT` tier definition, generalised from "white sits at
threshold" to "any colour's luminance sits at threshold." `SlabPanel`'s
`hot_tint` term uses the shader-side copy of this formula (`slab_panel.gdshader`)
for exactly this reason — one stat tint per instance, so `glow_energy` now
means the same thing regardless of which stat it's tinted by.

**`Edge`'s lit-line glow cannot take this fix.** A lit edge can connect two
*different*-archetype endpoints (the gradient's whole point), but
`Emissive.tint()`'s normalization factor is per-hue — it would need to live
per-vertex in the `Gradient` stops, and #391 already established that HDR
`Gradient` stops don't reach the bloom pass correctly on a `Line2D` (that's
*why* the lift lives in `self_modulate` — one value for the whole node —
instead of the gradient in the first place). `self_modulate` can't carry two
different per-endpoint normalization factors at once. `lit_glow_stops`
therefore stays what it already was: an empirically-tuned raw value for one
line width, not equalized across the hues it might carry — the same
"probe, don't derive" caveat the pixel-coverage section above already gives
it.

## Where the pass is mounted (landed 2026-08-07)

**Bloom is one full-screen pass per *viewport*.** The `Environment` lives in
`ui/theme/default_game_env.tres` — one file, one dial, shared by every surface.

- **Root viewport:** the `WorldEnvironment` in `scenes/game_root.tscn`. All three
  level scenes inherit it from the composition root.
- **SubViewports:** instance **`ui/theme/bloom_viewport.tscn`** in place of a plain
  `SubViewport`. It is a `SubViewport` root carrying `own_world_3d`, `use_hdr_2d`
  and the `WorldEnvironment` — all three of which are required, and all three of
  which fail *silently* when missed. Because the root of an instanced scene accepts
  new children without Editable Children, panel content goes straight under it and
  the `WorldEnvironment` stays invisible inside the instance. Per-panel `size` /
  `render_target_update_mode` / `unique_name_in_owner` override normally.
  (`gimbal_3d_showcase.tscn` predates this and rolls its own — leave it.)

  **Gotcha:** the packaged `WorldEnvironment` is internal, so `%WorldEnvironment`
  does **not** resolve from the instancing scene. The scene hands it out itself —
  `bloom_viewport.gd` exposes `get_environment_resource()`, and a tuning panel binds
  to *that*. Do **not** substitute `load("res://ui/theme/default_game_env.tres")` and
  trust the resource cache to have handed you the same object. That assumption held
  in a game run, was never checked in the editor, and is the shape of bug that leaves
  a panel's sliders driving an object nothing is rendering. Bind to the node;
  identity is then true by construction rather than by cache behaviour.
- **Tuning surface:** the **Bloom** tab in the sandbox host
  (`addons/bloom_sandbox/`). Its sliders edit the shared resource *in place*, its
  Save button writes it back, and **Reset** re-reads the file — so tuning there is
  tuning the real dial. Its sidebar prints a diagnostic block (every item in the
  list below, plus both Environment instance ids) precisely because all of these
  fail with nothing on screen to say which one fired.

  **Reset cannot use a plain `load()`** — that returns the already-mutated cached
  instance and the reset silently no-ops. `ResourceLoader.load(path, "",
  ResourceLoader.CACHE_MODE_IGNORE)` is what actually re-reads the file. Copy its
  `PROPERTY_USAGE_STORAGE` properties *onto* the live object; reassigning your own
  reference just orphans you from the one the viewport holds.

### Five ways glow silently does nothing

All five fail with no error and no warning. In diagnosis order:

1. **`background_canvas_max_layer` defaults to `0`,** which excludes every
   `CanvasLayer` — i.e. the entire HUD. Set to `100`: verified to include the base
   canvas and layer 50, and to exclude layer 101 (`SceneTransition`'s black fade,
   which must never bloom).
2. **`use_hdr_2d` is per-viewport.** The `rendering/viewport/hdr_2d=true` project
   setting covers the **root viewport only**. A `SubViewport` defaults to `false`
   and renders inert no matter how correct its Environment is. Verified: own-world
   + HDR blooms, shared-world + HDR blooms, own-world *without* HDR does not.
3. **Without `own_world_3d`, a SubViewport's `WorldEnvironment` registers on the
   *shared* world.** In the editor that is the editor's own world — it collides
   with the editor's environment and leaks between panels. Glow still works; the
   damage is elsewhere.
4. **A stray `glow_hdr_threshold` above your content — which the editor will
   persist without being asked.** The dial is one shared file. The Bloom tab's
   sliders mutate that *resource*, so the editor marks it dirty and writes it on
   its own save cycle — **pressing the tab's Save button is not required**, and a
   session spent scrubbing sliders can leave `glow_hdr_threshold = 1.53` on disk
   with nothing on screen saying so. At that threshold the `VALUE` tier (linear
   ≈1.42) is *below* the floor, so every surface in the project up to `ALERT`
   goes inert — and with almost nothing lit, dragging Intensity or Strength then
   appears to do nothing either, because there is nothing to amplify. Observed
   2026-08-07; it is what the Bloom tab's "the sliders are inert" report turned
   out to be. **Check `git diff ui/theme/default_game_env.tres` first**, before
   believing a scene or a viewport is at fault.

   Related, and the reason the failure is easy to walk into: the file omits
   `glow_intensity`, so it runs at Godot's default `0.3` — low. Intensity is the
   knob for *bloom present but weak*; threshold is the knob that makes it
   **absent**. Reaching for the wrong one is how a threshold ends up at 1.53.
5. **A SubViewport in an editor dock inherits the editor's "environments
   disabled".** A viewport's environment mode defaults to `INHERIT` — it takes
   the setting from its *parent* viewport rather than deciding for itself. In a
   game the parent chain ends at the root with environments on. In the editor the
   parent is the editor's own window viewport, which has them **off** so the
   editor UI is never post-processed, and every nested `SubViewport` silently
   inherits that. The pass never runs.

   **Fix, and it is the whole fix:** `bloom_viewport.gd` forces it in `_ready`.

   ```gdscript
   RenderingServer.viewport_set_environment_mode(
       get_viewport_rid(), RenderingServer.VIEWPORT_ENVIRONMENT_ENABLED
   )
   ```

   **History, because this line was removed once and cost a second session.**
   6014649 added it while the Bloom panel was still `add_child`ed from an
   `@export` — non-scenic composition in place — and the tab bloomed. 9dcc89c
   then baked the panel into its tab scene, observed bloom (with the forcing
   still live), concluded baking was the cause, and reverted the forcing as "a
   guess carrying a wrong rationale". The tab went inert again; restoring the
   forcing fixed it, verified 2026-08-08. **Scenic baking is not what makes the
   glow pass run.** Keep baking anyway — `.claude/rules/sandbox-host.md` wants it
   for its own reasons (`%PanelHost` adoption, reload-as-cold-open) — but never
   credit it with this.

   It is the most expensive of the five to diagnose because **every reading you
   can take is green**: `use_hdr_2d`, `own_world_3d`, `render_target_update_mode`,
   `glow_enabled`, `forward_plus/vulkan`, the Environment registered on the
   viewport's `World3D`, an HDR (`RGBH`) render target, and matching Environment
   instance ids. Toggling `glow_enabled` does nothing, because the pass is not
   running at all.

   **The discriminator:** open the panel `.tscn` and look at it on the editor's
   **2D screen**. Same scene, same process, same `Environment` — if it blooms
   there and not in the dock, this is your bug, and nothing about the Environment
   is at fault. The 2D screen parents the scene under `EditorNode`'s scene-root
   SubViewport, which has environments **enabled**; the dock hangs off the
   editor's main window viewport, which does not — that difference *is* the
   mechanism, not merely a symptom of it.

   **Ruled out empirically, so nobody re-derives them:** parent-viewport
   `use_hdr_2d`, root-viewport `use_hdr_2d`, nine simultaneous bloom viewports
   sharing one `Environment` resource, and the editor's redraw schedule
   (**Update Continuously** changes nothing). All four bloom identically in a
   game run — and a game run cannot reproduce this at all, which is the trap:
   the original #371 verification passed for exactly that reason.

   This is the concrete cost of non-scenic sandbox composition, and the reason
   `.claude/rules/sandbox-host.md` insists a tab be an inherited scene that
   *instances* its panel. See `docs/domain/sandbox-framework.md`.

Debug in that order, and **debug the Environment through the root viewport, never
through a SubViewport** — a SubViewport has two extra ways to render inert, so a
failure there tells you nothing about which of the three is wrong.

### `.tres` comments do not survive

The engine re-serializes an `Environment` `.tres` it touches and **strips every
`;` comment**. Rationale for a knob belongs here or in a rule file, never in the
resource. (General `.tres` hazards: `.claude/rules/godot-tres-authoring.md`.)

### Glow levels are the shape knob, not intensity

`glow_levels/1..7` are mip weights: level 1 is the tightest radius, 7 the widest.
With only 1–4 enabled (the obvious-looking default) glow pools **inside letter
counters and at stroke intersections** — it only accumulates where lit pixels are
already dense, which reads as grime rather than as light. Weighting outward
(`0.5 / 0.9 / 1.0 / 1.0 / 0.7 / 0.3`) gives a rim instead.

Judge that against **thin strokes**, not solid swatches. A 100×40 filled rect at
+3 blows out into a blob under settings that look right on text and rim arcs.

### Alpha is the fade channel; colour value is the dimmer

Canvas blending is non-premultiplied, so what reaches the pass is `rgb × a`. To
make something quieter, **drop a tier — don't drop alpha**. Alpha stays reserved
for animated reveals, where the bloom ramping in with the fade is a feature.

## See also

- `ui/theme/emissive.gd` — `Emissive.at(base, stops)` and the named tiers, the
  only sanctioned way to author an emissive colour in code.
- `theme.tres` — `TierInert` / `TierLabel` / `TierValue` / `TierAlert`
  `theme_type_variation`s, the way to author an emissive **Label**.
- #371 — the verdict this doc supports (bloom, not per-element SDF glow; the
  Layer 0/1/2 architecture; the Theme-resource palette home).
- `.claude/rules/rendering-performance.md` — bloom is a fullscreen pass; cost
  is fixed by resolution, independent of element count.
- `.claude/rules/godot-shaders.md` — headless import doesn't compile GLSL;
  verify under a real renderer.
- `.claude/rules/ui-palette.md` — the SDR palette this HDR layer rides atop.