# Strikethrough toast (#82 / #84)

The "removed modifier" floater: a stat toast that greys out and gets slashed
through, then unzips along the cut. `ui/floating_number_layer/strikethrough_toast/`
(`strikethrough_toast.gd` + `strikethrough.gdshader` + `.tscn`). Swapped in by
`FloaterStyles.modifier_removed()` via `FloaterStyle.scene_override`.

## Scene shape (load-bearing)

It is a **plain `Label` with a canvas `ShaderMaterial`** — *not* a SubViewport.
The label uses `anchors_preset=15` (fills its Control) with **centered** text, and
the Control sits in the toaster's full-width `VBoxContainer`. So the text does NOT
hug the glyph run: it's centered in a rect whose width tracks the widest toast in
the stack. Any geometry math must therefore place the cut by **font metrics**, not
by assuming the label rect == the text bounds.

## The diagonal cut geometry (#84)

The cut's endpoints are the shader uniforms `split_y_start` (y at x=0) and
`split_y_end` (y at x=1), in UV space (y down, 0..1 across the label bbox). They
are derived once per layout from font metrics by the **pure** static function:

```gdscript
StrikethroughToast.strike_endpoints(ascent, total_height, label_size, angle_deg) -> Vector2
```

- Centre rides the **x-height band**: `baseline − ascent * X_HEIGHT_RATIO` (0.30),
  where the baseline is `(H − total_height)/2 + ascent` because the text is
  vertically centred in the rect. This is what makes the slash cross the letter
  bodies and miss ascender dots, for *any* font/size — the old hardcoded
  `split_y(x) = mix(0.7, 0.4, x)` only looked right for one label shape.
- Slope comes from `angle_deg` (a scene `@export`, default **6.5°**),
  **aspect-corrected** by `W/H` so the on-screen angle is constant regardless of
  label width. Calibrated against the REAL stock label — "+10 STR" at 32px renders
  **119×45** (ascent 35 / total 45; the label's min height, honoured by the toaster
  VBox), so 6.5° reproduces the old good-looking 0.7/0.4. (An earlier pass mis-tuned
  to 3.5° against an assumed H=32 and came out half as steep — verify slope by eye
  in the sandbox.) `strike_height_ratio` (default 0.30, lowercase x-height; raise
  toward ~0.45 to ride through capitals) is the other `@export` knob. See
  `test/unit/vfx/test_strikethrough_geometry.gd`.

`strike_endpoints` takes plain floats (no `Font`/`Node`), so it's unit-testable
headless — the "test the geometry inputs to the shader" ask in #84. Pixel output
is not asserted (shaders are hard headless).

Geometry is (re)fed on `Label.resized` via `_refresh_geometry()`, which also pushes
the `label_size` uniform. This replaced a per-frame `_process` poll (the old stale
TODO): the label only changes size when its text/font does.

## Shader gotchas carried forward (the thrash in #84's 8 commits)

- **Canvas-material UVs are per-glyph.** A `ShaderMaterial` on a `Label` gets `UV`
  per draw-call (per glyph in the font atlas), not across the whole label. The fix
  is `text_uv = VERTEX / label_size` in `vertex()` (label_size passed as a uniform)
  to reconstruct a clean 0..1 across the bbox. Don't reach for `UV` expecting
  label-space coords.
- **The SubViewport route is rejected.** An earlier attempt rendered the label into
  a `SubViewportContainer > SubViewport > Label` to get a sampleable texture — it
  came out blurry/ugly. Do NOT reintroduce it.
- **`TEXTURE` on a Label canvas material is unreliable** (observed returning white).
  The current shader's "draw the strike through transparent glyph gaps" branch
  depends on `texture(TEXTURE, ...).a` telling glyph from gap, which is fragile.

## Known follow-up — Tier 2 (deferred, R&D in the sandbox)

The **split/unzip animation** (`split_open` UV displacement in the shader +
`_animate_out`) still needs to cleanly move the two halves apart, and the reliance
on `TEXTURE` glyph coverage is brittle. The robust redesign to iterate on — **in
the toast sandbox** (`scenes/dev/toast_showcase.tscn`, the "Toasts" tab, which
exists precisely to debug this) — is to render the split as scene-graph rather than
glyph sampling: two `Label` copies alpha-clipped by the diagonal via a discard-only
shader (no `TEXTURE` sample → no white bug), a drawn beam at the cut for the hot-tip
sweep, and tween the halves apart perpendicular to the line. This is visual R&D, so
it wants eyeballs, not a headless assert.
