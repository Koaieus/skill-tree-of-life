---
description: .gdshader — headless import does NOT compile GLSL; PlaceholderTexture2D collapses UVs
paths:
  - "**/*.gdshader"
---

# Shaders

## A headless import does not compile GLSL — green suite, broken shader

`godot --headless --editor --quit` and GUT run under the **dummy renderer**,
which never compiles shader GLSL. An edit producing invalid generated GLSL passes
a clean import *and* a green test suite, then fails at driver compile under a real
renderer — the node just draws its untextured white fallback.

Drive a real backend under a virtual display to actually check:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 --quit-after 30 \
  res://path/to/scene_using_the_shader.tscn 2>&1 | grep -iE 'compilation failed|no matching'
```

Empty grep = clean. opengl3 (llvmpipe) needs no GPU, and reproduces codegen bugs
that production's Vulkan backend hits too.

## `min(dx, dy)` for a border falloff creases at the corners

Taking the nearer edge is a **Chebyshev** distance: its iso-contours are nested
rectangles, so the two ramps meet at a derivative discontinuity along each
45° diagonal. It renders as a hard seam into every corner, and mach banding
latches onto exactly that kind of slope break. Found authoring #412's
armed-mode border glow.

**Fix:** ramp each axis independently, then take the smooth (screen) union —
`a + b - a*b`. C1-continuous everywhere, identical to the old ramp at an edge
midpoint where the other axis contributes ~0, and smoothly brighter into the
corners rather than creased.

**And dither a shallow ramp.** A gradient that runs slowly over many pixels
quantises into steps once composited to 8-bit. One LSB of *static* screen-space
hash (`fract(sin(dot(FRAGCOORD.xy, …)) * …)`, keyed on FRAGCOORD and **never**
TIME, or it shimmers) removes it. Above ~2 LSB it reads as grain.

## A Sprite2D fed a `PlaceholderTexture2D` collapses its UVs

`PlaceholderTexture2D` reports a `size` but carries no image data, so the quad
submits **degenerate (constant) UVs** — every fragment sees the same `UV`. Any
shader reading `UV` (procedural tiling, starfields, noise) gets no gradient and
renders flat/garbage. No error, no warning.

**Fix:** use a real texture of the desired size — a `GradientTexture2D` needs only
a `Gradient` sub-resource plus width/height, no asset file. The texels are
irrelevant if the shader ignores them; what matters is that `UV` interpolates.

More: **`docs/domain/godot-workflow.md`**.
