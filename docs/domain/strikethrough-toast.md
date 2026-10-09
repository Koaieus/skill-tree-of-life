# Strikethrough toast

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

## The diagonal cut geometry

The cut's endpoints are the shader uniforms `split_y_start` (y at x=0) and
`split_y_end` (y at x=1), in UV space (y down, 0..1 across the label bbox). They
are derived once per layout from font metrics by the **pure** static function:

```gdscript
StrikethroughToast.strike_endpoints(ascent, total_height, label_size, deg, height_ratio) -> Vector2
```

- Centre rides the **x-height band**: `baseline - ascent * height_ratio`, where the
  baseline is `(H - total_height)/2 + ascent` because the text is vertically
  centred in the rect. That makes the slash cross the letter bodies and miss
  ascender dots for any font/size. `height_ratio` is the `strike_height_ratio`
  export (default 0.30, lowercase x-height; raise toward ~0.45 to ride through
  capitals).
- Slope comes from `angle_deg` (a scene `@export`, default **6.5 degrees**),
  **aspect-corrected** by `W/H` so the on-screen angle is constant regardless of
  label width. Calibrated against the stock label: "+10 STR" at 32px renders
  **119x45** (ascent 35 / total 45; the label's min height, honoured by the toaster
  VBox). Verify slope by eye in the sandbox. See
  `test/unit/vfx/test_strikethrough_geometry.gd`.

`strike_endpoints` takes plain floats (no `Font`/`Node`), so it's unit-testable
headless. Pixel output is not asserted (shaders are hard headless).

Geometry is (re)fed on `Label.resized` via `_refresh_geometry()`, which also pushes
the `label_size` uniform. The label only changes size when its text/font does, so there is no per-frame poll.

## Shader gotchas

- **Canvas-material UVs are per-glyph.** A `ShaderMaterial` on a `Label` gets `UV`
  per draw call (per glyph in the font atlas), not across the whole label. Use
  `text_uv = VERTEX / label_size` in `vertex()` (label_size passed as a uniform)
  to reconstruct a clean 0..1 across the bbox. Don't reach for `UV` expecting
  label-space coords.
- **No SubViewport.** Rendering the label into a `SubViewportContainer > SubViewport
  > Label` for a sampleable texture comes out blurry. Don't reintroduce it.
- **`TEXTURE` is the font atlas.** On a Label canvas material `TEXTURE` is the font
  atlas: glyph coverage is in `.a`, RGB is white. Glyph colour comes from the
  incoming vertex `COLOR` (`font_color` on the main pass, `outline_color` on the
  outline pass), and `COLOR.a` carries `modulate:a`, which drives the `_animate_out`
  fade. The "strike through transparent glyph gaps" branch reads
  `texture(TEXTURE, UV).a` to tell glyph from gap.

## Deferred

A scene-graph split (two `Label` copies alpha-clipped by the diagonal through a
discard-only shader, a drawn beam at the cut, halves tweened apart perpendicular to
the line) is the candidate redesign for the split/unzip animation. It is visual
R&D for the "Toasts" live tab (`addons/toast_sandbox/toast_sandbox_panel.tscn`) and
is deferred.
