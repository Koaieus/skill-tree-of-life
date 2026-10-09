---
description: Godot project workflow and engine gotchas — .tscn/.tres authoring order, class-cache refresh, uid sidecars, shaders, headless-vs-rendered verification, worktrees
---

# Godot workflow

> A `*` at the end of a heading marks a silent-failure gotcha: apply the fix, no need to tell the user.

## `.tscn` root node: `script = ExtResource(...)` MUST come before any `@export` override*

Godot 4 deserializes node properties in file order. If `script = ExtResource(...)`
is listed **after** an `@export var` override on the root node, the script
attachment silently reinitialises the exported var to its GDScript default,
discarding the scene override. Confirmed empirically: `mode_color = red` →
instantiate → property reads gold (class default) because `script` was last.

```gdshader
# WRONG — mode_color will always read gold
[node name="Foo" type="MarginContainer"]
mode_color = Color(0.945, 0.269, 0.245, 1)   # ↓ this override is LOST
script = ExtResource("1_script")

# CORRECT
[node name="Foo" type="MarginContainer"]
script = ExtResource("1_script")             # script goes FIRST
mode_color = Color(0.945, 0.269, 0.245, 1)   # then export overrides
```

Children inside the same scene are unaffected — this only bites the root node
of the `.tscn` itself. A test that instantiates the scene and asserts the
property catches regressions immediately.

## `@tool` scripts must guard editor-time writes in `_ready()` with `Engine.is_editor_hint()`*

`@tool` scripts that modify `modulate`, child-instanced `@export` vars, or
shader parameters during `_ready()` dirty the scene on every editor load; Godot
serialises those writes back into the `.tscn` as property overrides. Guard the
**writes**:

```gdscript
func _ready() -> void:
    if not Engine.is_editor_hint():
        _apply_active(false)   # don't modify the scene during editor load
```

A bare `if Engine.is_editor_hint(): return` at the top is safe only for a script
that does nothing but visual setup. A script a live sandbox tab instantiates runs
`_ready` with the hint TRUE, so an early return strands every subscription below
it (GUT has hint false and never sees it). Gate the OS-facing lines individually
— `PlayerInputController._ready` is the worked case, and
`docs/domain/sandbox-framework.md` the rule.

## A non-`@tool` script behind a `.tres`/`.tscn` an editor panel loads is a placeholder instance*

Only its `@export`s read back; every method or signal touch throws *"Invalid
access to property or key"* (naming the **node**, the wrong file) or *"placeholder
instance"* (naming the resource). `Foo.new()` from a `@tool` caller is exempt.
So everything reachable from a `.tres` an editor panel loads must be `@tool`;
`check` catches only the node case, GUT neither. The gate is
`test/unit/test_tres_scripts_are_tool.gd`. Guard in the **method**, not just
`_ready()`: `@export` setters fire during deserialization, first.

## In a `@tool` script, never write a DERIVED value back into an `@export`*

If `@export var x` is both the authored knob and where computed growth lands,
the editor serializes the *computed* value into the `.tscn` — and the next load
computes again from there. It compounds on every save, silently.

**How to apply:** split the property. Export the authored input, expose the
derived value as a plain `var` with only a getter:

```gdscript
@export var base_radius: float = 32.0        # authored, serialized
var radius: float:                            # derived, never serialized
    get: return base_radius + _stake_growth()
```

Callers keep reading `radius`; only writers move to `base_radius`. This also
kills the usual companion bugs — the "capture the authored value on `_ready`"
dance, and its pre-tree-write blind spot. Note `.tscn` files must be migrated
by hand: Godot drops unknown properties **silently**, so a stale `radius = 38`
line reverts that node to the class default with no error.

## A Sprite2D fed a PlaceholderTexture2D collapses its UVs — kills any UV shader*

`PlaceholderTexture2D` reports a `size` but carries **no image data**. A
`Sprite2D` drawing one still returns the right `get_rect()`, but the quad it
submits has **degenerate (constant) UVs** — every fragment sees the same `UV`.
Any `canvas_item` shader on that sprite that reads `UV` (procedural tiling,
starfields, noise clouds) therefore gets no gradient and renders a flat/garbage
result. No error, no warning; it just looks wrong.

Verified empirically for #157: the space-background starfield drew as sub-pixel
moiré dust because each tile was a `Sprite2D` + `PlaceholderTexture2D`. Sampling
the rendered `UV` gave a constant `~0.125` across the whole sprite interior;
swapping to a real `GradientTexture2D` (same size, content irrelevant — the
shader ignores the texels) made `UV` interpolate `0..1` and the field rendered
correctly. Parallax2D + `repeat_size` tiling was *not* the culprit and works fine
with a real texture.

**How to apply:** never use `PlaceholderTexture2D` as the host texture for a
Sprite2D whose material reads `UV`. Use a real texture of the desired tile size
(a `GradientTexture2D` needs only a `Gradient` sub-resource and a width/height —
no asset file). This only bites custom UV shaders; a plain textured sprite that
just wants the placeholder's magenta is unaffected.

Related: a full-screen shader hosted on a **CanvasLayer**'s Parallax2D is
zoom-*stable* (the layer doesn't inherit the world camera's zoom) while parallax
scroll still tracks the camera — so star size/count stay put across the whole
zoom range. Under a plain Node2D the same Parallax2D *does* scale with zoom.

## Sub-resources in a scene are SHARED across every instantiate() unless local-to-scene*

A `SubResource` (e.g. a `Gradient` on a `Line2D`, a `ShaderMaterial`) declared
inline in a `.tscn` is loaded once and reused by every `PackedScene.instantiate()`
call — it is not duplicated per instance. If a script mutates that resource
per-instance (e.g. `Edge.gd` writing per-edge colors into `line_2d.gradient`),
every instance ends up sharing one object: whichever instance wrote last wins,
and all instances render identically. Symptom is exactly "the per-instance
tweak has no visible effect" — no error, no crash, just silently wrong output.

Fix: set `resource_local_to_scene = true` on the sub-resource in the `.tscn`
(inspector: resource → Local To Scene). This makes Godot duplicate it fresh on
every `instantiate()`. Applies to any resource a scene's own script intends to
own uniquely per instance — gradients, materials, curves, etc. — not just Edge.

## `@export` cannot be applied to a `static var`*

```
Parse Error: Annotation "@export" cannot be applied to a static variable.
```

Verified on 4.7. So there's no "exported class-level constant" — and you wouldn't
want one: `@export` serializes **per resource/node**, so an exported "where do X
live" path would put an editable copy of the same answer on every instance.

**How to apply:** a class-level fact is a `const` (`CoreClass.DIR`). Reach for
`@export` only when each instance legitimately carries its own value.

## Sweep for orphaned `.uid` files after ANY move or delete*

Godot writes a sidecar `<file>.uid` for scripts (and other importables). Moving
or deleting the file does not remove the sidecar — you get a tracked `.uid`
pointing at nothing. Harmless-looking, permanent, and it accumulates.

```bash
find . -name '*.uid' -not -path './.godot/*' -not -path './.claude/worktrees/*' \
  | while read u; do [ -e "${u%.uid}" ] || echo "ORPHAN: $u"; done
```

Run it as part of the same change, not later. Note `.tscn`/`.tres` carry their
uid **inline** in the `[gd_scene uid="…"]` header, so deleting a scene leaves no
sidecar — this bites `.gd` (and imported assets), not scenes.

The inverse bite, on **create**: a new `.gd` mints its `.uid` sidecar on first
load — a headless test run counts — and the repo tracks them. A branch that adds scripts must commit their sidecars too,
or the worktree is left with untracked strays that the next checkout regenerates
as churn (#716's two test scripts landed sidecar-less and needed a pinning chore
commit). Sweep for `?? *.uid` in `git status` at branch-finish time.

Known pre-existing orphan: `addons/gut/menu_manager.gd.uid`, shipped by vendored
GUT 9.6.0 (`24da57f`) with no companion script. Left alone deliberately — don't
diverge from a vendored addon over it.

## Refreshing a stale class cache — rename, rebase, or fresh worktree*

`.godot/global_script_class_cache.cfg` goes stale whenever the set of
`class_name`s moves under it: you added or renamed one, you rebased / pulled /
ff-merged a branch whose commit did (nothing in your own tree changed — the
surprising one), or you are in a **fresh worktree** (own gitignored `.godot/`,
so no cache at all). Symptoms: *"Could not find type X"* on correct source, or
**a green GUT run with a lower `Scripts`/`Tests` total**, because a script that
cannot resolve a type is skipped silently (`.claude/rules/testing.md`). Refresh
first; don't audit the test file.

**`mise run test` / `test:one` / `test:dir` refresh for you** (#919): before GUT
starts, `.mise/tasks/test` diffs the tree's `class_name` set against the cache
(~50 ms) and, only on drift, prints `class cache stale (N new / M gone):
refreshing…` and runs `refresh` (~12 s once per fresh worktree). Hand-run
`mise run refresh` (or `godot --headless --editor --quit`) only for a non-test
launch — a sandbox scene, `godot --script` — and never before `check`, which is
itself an editor pass. Pure script edits and new files WITHOUT a `class_name`
need no refresh. A `.gd` with a parse error and a `class_name` never enters the
cache, so every `test` refreshes and prints the `SCRIPT ERROR` — the noise is
the diagnosis.

Two things `refresh` does not say:

- **"Nothing changed" describes file churn** (which scenes/resources the editor
  re-serialized), not the cache — a rebuild moves no tracked file. It never means
  "the cache was fine"; re-run the failing thing before concluding anything.
- **A landed branch that ADDS an importable asset** leaves the MAIN checkout
  unable to load it: `land` tests in the branch's own warmed worktree, the main
  checkout never imported the `.png`/`.svg`, and tests reaching it fail with
  `Parse Error: [ext_resource] referenced non-existent resource`
  (`assets/icons/aspects/hex.png`, 2026-10-08). Run `mise run refresh` in the
  main checkout after landing or pulling such a branch; an older worktree needs
  its own warm.

## The look-alike that is NOT a stale cache: `mise run check` can miss a parse error*

**Symptom:** at runtime, *"Invalid call. Nonexistent function 'x' in base
'GDScript'"* on a brand-new script — while `mise run check` says **"✓ all
scripts compiled clean"** and `mise run refresh` says "nothing changed".

It reads exactly like the stale-cache section above, and it isn't. A script with
a parse error loads as an **empty** GDScript: the `class_name` still resolves (it
is in the cache), so the call site compiles, and every method on it is missing at
runtime. Chasing the cache gets you nowhere, twice.

Get the real error out of the file itself:

```bash
mise run check-script -- command/world_fingerprint.gd
```

That prints the parse error with a line number. Ignore any *"Identifier not
found: StatRegistry/Events"* it also emits — `--script` skips autoloads, and that
noise is unrelated (see the crumb).

Live example: `PackedInt64Array` has no `hash()`. One bad line, whole script
empty, check green.

**How to apply:** a runtime "nonexistent function" on a file you just wrote is a
parse error until proven otherwise. `--check-only --script <file>` first, refresh
never.

## Always git status after a refresh*

**The expected outcome is nothing, or cosmetic noise.** Every effect is a text
diff in a git-tracked file you can see and revert in one command. Refresh when
you need to — also while the user has the editor open (worst case it writes
`.uid`/import metadata the editor would have produced anyway; pause only if they
are mid-save on the very files you touch). Don't stall, work around it, `md5sum`
anything, or ask permission; glance at the diff and go on.

The editor pass re-serializes any scene or `.tres` it touches. Every effect on
record is benign:

- **Default-elision** — properties equal to their script's *current* default
  are dropped (`operation = 0`, `unit_value = 1.0`, …) and `uid=` is added to
  ext_resources; non-default values are kept. **A shifted default does this
  with no editor pass at all** (`e521ac2` dropped `max_hops = 3` from
  `spark.tres` once the script declared that default); the mirror case adds a line.
- **Regenerated sub_resource ids** (`Resource_umwfs` → `Resource_qrijo`, consumer
  updated in lockstep) and **node positions** nudged by a few pixels.

**No committed instance of the editor destroying a non-default value has ever
been found** (the two once-cited cases were audited out, 2026-08-29). If one
seems to have vanished, check its `@export` default **at that sha**
(`git show <sha>:script.gd`): equal → elision, safe; different → the first
evidenced case, record the sha. Don't commit these in an unrelated change —
revert them or commit them alone as normalization.

`mise run refresh` runs the pass, excludes pre-existing dirt, and prints either
`✓ refresh done — nothing changed` or a grouped report separating benign
sidecar/`.import` churn from authored files, listing only the non-trivial lines
removed. That list is the whole judgement call.

## Verifying `.gdshader` changes — headless import does NOT compile GLSL*

`godot --headless --editor --quit` (and GUT) run under the **dummy renderer**,
which never compiles shader GLSL. A `.gdshader` edit that produces invalid
generated GLSL (e.g. an `#include`d function whose parameter name collides with
a `uniform` — Godot's codegen rewrites the uniform *token* even inside the
function body, silently miscompiling to something like `mix(vec3, vec4, float)`)
**passes a clean headless import and a green test suite**, then fails at driver
compile only under a real renderer:

```
ERROR: ... Fragment shader compilation failed / no matching function ...
  compile_stages() servers/rendering/renderer_rd/shader_rd.cpp
```

The node just renders its untextured fallback (a white quad). To compile
shaders for real, run the scene under the xvfb + opengl3 recipe in "Capturing a
real rendered frame" below and `grep -iE 'compilation failed|no matching'` the
output (empty = clean). The bug is in Godot's shader codegen, so it reproduces
on opengl3/llvmpipe even though production uses RD/Vulkan.

`mise run check-shaders` (#682) walks every `.gdshader`/`.gdshaderinc` and gates
GDSL parse/type errors (undefined function, name collision) on the dummy
renderer. It says nothing about the silent codegen miscompile above, which
needs the rendered recipe.

## Hand-authoring `.tres` — UID mismatch silently nulls the field*

`[ext_resource type="Script" uid="uid://..." path="res://foo/bar.gd" id="x"]`
— if `uid` doesn't match the actual `.uid` file for `path`, Godot does NOT
error. The ext_resource entry silently fails to resolve; any `SubResource`
declaring `script = ExtResource("x")` instantiates as a bare `Resource`
without the script attached; any field referencing that SubResource ends up
as `null`. Tests that don't probe the field never notice — the broken
preset just generates empty content downstream.

How to apply: when authoring a multi-script `.tres` by hand, **never trust
copy-pasted uids**. Either omit the `uid=` attribute (Godot resolves by
`path=`), or verify each uid against `cat <script>.gd.uid`. Lint by loading
the preset in a GUT test and asserting every field is non-null.

## Editing a font `.import` REGENERATES its uid — re-pin it by hand*

Changing any `[params]` line in a `.ttf.import` and reimporting rewrites the
file's `uid=` to a fresh one. `theme.tres` references the font by the OLD uid, so
the next load warns `ext_resource, invalid UID: uid://... — using text path
instead` and every consumer silently falls back to the path. It still works, but
you have just orphaned a uid the repo hard-codes.

How to apply: after `godot --headless --import`, `git diff` the `.import` and put
the original `uid=` back (`sed -i 's|^uid="uid://[a-z0-9]*"|uid://<original>|'`).
Reimport again to confirm the warning is gone. The same happens for any imported
asset, not just fonts.

## Text drawn at a canvas scale needs supersampling, not a font flag*

A `Label` rasters its glyphs at `font_size` and the canvas then STRETCHES that
bitmap: a `Camera2D` zoom, a `Node2D` scale and window stretch all resample it.
Magnified it reads mushy; minified it breaks into fragments. Godot's automatic
oversampling covers the *viewport* scale only — not a camera zoom, and not a
parent's scale.

Three knobs, and only one of them is scoped:

- **`oversampling` in the `.import`** rasters every use of that font N times
  larger. Global: it measurably THINS screen-space labels at zoom 1, which want a
  native raster. Measured on `CinzelHeader` in the HUD, 2026-08-26.
- **`multichannel_signed_distance_field`** is scale-free and was the obvious
  answer, but Cinzel's space glyph renders a visible stray dash under MSDF at
  every `msdf_size` / `msdf_pixel_range` combination tried (48–64 / 2–8).
- **Per-Label supersampling** is the scoped version of the first (the answer):
  set `font_size * N`, `scale = 1/N`, and lay the box out in raster units — a
  `Control` scales about its own `position`, so centring must still use the DRAWN
  width.

**`generate_mipmaps` is inert on its own.** Godot's default canvas filter has no
mipmap stage, so the mipmaps are never sampled until a CanvasItem sets
`texture_filter = 4` (`LINEAR_WITH_MIPMAPS`). That pair is what fixes the
*minified* case; supersampling only fixes the magnified one.

Judge all of this by screenshot ("Capturing a real rendered frame") — the headless suite cannot see it.

## Hand-authoring `.tres` — two parser gotchas

- **Array literals must be single-line.** `Array[T]([a, b, c])` works; the
  same with newlines after `[` gives a "Parse Error: Expected string."
  Same for `PackedStringArray` contents. Author wide, don't pretty-print.
- **`PackedStringArray` uses positional args, NOT a bracketed list.**
  `PackedStringArray("a", "b")` — correct. `PackedStringArray(["a", "b"])`
  — parses as a single nested-array element and breaks reads. `Array[T]`
  *does* take `[...]`. Don't conflate them.

## Scene-node systems with injected deps: wire in `initialize()`, not `_ready()`

A system that lives in the scene tree (e.g. `%HighlightController`, sibling of
the other Systems nodes) has its `_ready()` fire DURING scene instantiation —
**before** GameRoot's `_ready` can inject its dependency fields. So any signal
hookup or resolve that reads injected deps must NOT live in the node's own
`_ready`; it'll run with null deps and silently no-op. Put it in a public
`initialize()` that GameRoot calls right after assigning the deps. (Group
membership in `_enter_tree` is fine — it needs nothing injected.) Systems wired
purely off autoloads (`BattleSystem` → `Events.skill_node_depleted`) can keep
their hookup in `_ready`; a system reading sibling-system references can't.

## Deferred call with a freed Object argument is silently dropped

`some_method.call_deferred(obj)` — if `obj` (an Object/Node passed as an
argument) is freed before the MessageQueue flushes, Godot drops the call with no
error. Bit us in entity-death cleanup: a deferred `deallocate_all_owned(entity)`
raced `queue_free(entity)` and never ran, orphaning nodes. If you must defer work
keyed on an object that might be freed the same frame, either do the work
synchronously or guarantee the free is ordered after it. See
[entity-death.md](../../.claude/rules/entity-death.md).

## Typed variable + freed dict entry = crash before is_instance_valid*

`var t: FloaterToaster = dict.get(key)` — if the dict holds a freed instance,
the typed assignment crashes before `is_instance_valid` gets a chance to run.
Read into an untyped var first:

```gdscript
var stored = dict.get(key)
var t: MyType = stored if is_instance_valid(stored) else null
```

## Worktrees

`mise run worktree:new -- <issue|name>` / `worktree:ls` / `worktree:rm -- <fuzzy>`
give an isolated checkout under `.worktrees/<slug>/`; the `warp` and `swarm`
skills drive the cycle on top (swarm drones make their own worktree as their
first action). Each worktree has its own gitignored `.godot/` (own import and
class cache; its cold import never touches the main checkout's), and
`worktree:new` pays it up front — `refresh` then `check` inside the new
worktree, one verdict line; `--no-warm` / `NO_WARM=1` skips both. Closing
keywords and `gh --body-file`: `docs/domain/issue-workflow.md`.

## `godot --script` does not boot autoloads — use a GUT test to inspect scene state

A throwaway `godot --headless --script foo.gd` (`extends SceneTree`) is the
obvious way to ask "what does this scene actually contain at runtime?" It runs,
but **the autoload singletons are never registered**, so every script that
touches `StatRegistry`, `Events`, `SceneTransition`, … fails to compile:

```
SCRIPT ERROR: Compile Error: Identifier not found: StatRegistry
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
```

The trap is the failure *shape*: those errors go to stderr while your own
`print()` never fires, so a grep for your expected output comes back empty and
reads as "the scene has 0 edges" rather than "half the project didn't compile."
Cost two debugging loops in one session chasing a scene that was fine.

**Use a GUT test instead** — `mise run test:one` boots the project normally, so
autoloads exist (`.claude/rules/testing.md` states this). If the thing is worth
inspecting once it is usually worth pinning, so the test is rarely wasted work.

`--script` remains fine for anything that touches no game code: probing an engine
API, sampling a `Curve`, checking `Image` formats.

## A hairline in `_draw` must snap to the VIEWPORT's screen grid*

Godot's 2D canvas does not antialias filled geometry — a pixel is covered iff its
**centre** is inside the span — so a 1px line landing between two centres draws
nothing. Snapping to whole pixels only helps on the *screen* grid, and under
`canvas_items` stretch (1440x960 base) a differently-sized window rescales the
canvas on the way out. Only `get_viewport().get_screen_transform()` carries that
rescale; `get_global_transform_with_canvas()` and the [CanvasLayer]'s own
`get_screen_transform()` both report identity (probed 2026-08-24).

**How to apply:** compose by hand — `get_viewport().get_screen_transform() *
get_global_transform_with_canvas()` — `round()` the rect in that space, draw
filled spans, transform back (`MinimapViewportRectLayer`). **Symptom:** a 1px
edge vanishing at certain coordinates on one axis only, that a window resize or
refocus makes come and go.

## `Rect2.has_point` is half-open; a zero-size `Rect2` contains nothing*

It excludes the bottom/right edges, so `position + size` is *outside* — and a
zero-size rect contains not even its own origin. Fails as a wrong answer, never
an error (found via two test failures in `VisionCircles`' bounds early-out).

For an inclusive region, keep `lo`/`hi` vectors and compare explicitly. `Rect2`
is for layout/culling, not "is this inside?" predicates.

## Interdependent `@export`s restore in declaration order*

**Declare the bound ABOVE the value that clamps against it.** A setter that
clamps one exported property against another (`fill_current` clamped to
`fill_max`) reads that property's *default* if it is declared later — so every
scene-authored value is clamped against the default at load, and nothing errors.

Two live cases sit in `skill_node/visuals/rim_ring.gd`; both were found by
seeing wrong values in a scene, not by reading the code.

## `MultiMesh` per-instance data does not round-trip headless — the obvious test asserts nothing*

Godot's `RendererDummy` no-ops the whole per-instance `MultiMesh` read/write
path. So this, which looks like a real test, is not one:

```gdscript
mm.set_instance_transform_2d(0, expected)
assert_eq(mm.get_instance_transform_2d(0), expected)   # passes on garbage
```

`get_instance_transform_2d()` comes back **identity** regardless of what was
pushed. The assert therefore passes when the code under test wrote an all-zero
transform, wrote nothing at all, or wrote the right thing — it cannot tell the
three apart, in either direction.

This blind spot let **#413 ship invisible edges** past every headless probe.

**Instead, expose the computation as a pure function and assert that.**
`ui/frontmatter/menu_edge_view.gd` is the pattern — `segment_transform(from, to)`
and `segment_instance_transform(index)` are static/pure, fully testable, and the
`set_instance_transform_2d` call site shrinks to a one-liner with nothing left
to get wrong:

```gdscript
for i in curve_segments:
    multimesh.set_instance_transform_2d(i, segment_instance_transform(i))
```

Instance **colours and custom data do** round-trip today. Do not lean on it —
the same driver owns them, and nothing guarantees the asymmetry survives an
engine bump.

Anything that must be verified as *actually drawn* needs a real frame — see
"Capturing a real rendered frame".

## `add_child` fails SILENTLY on a busy parent — and a directly-run scene has `root` busy*

`Node.add_child()` does not raise when the parent is "busy setting up children".
It prints an error and **does nothing** — the child stays unparented, and the
next line runs as if it worked.

`root` is exactly that while the `SceneTree` is adding a scene that was run
DIRECTLY: F6 in the editor, or `run/main_scene`. So any `_ready()` in that scene
which reaches for `get_tree().root.add_child(...)` is doing it inside the one
window where it cannot succeed.

Real crash (#589/C1): `MenuFanHarness.measure()` parented itself to `root` (a
detached Control measures every rect as `0x0`); on a direct run it never
parented, and the errors that followed named an unrelated thing.

**How to apply.** If you need a temporary in-tree host during `_ready`:

- Do NOT use `root`. Every **autoload** is a fully-ready child of `root` before
  any scene is added, so none of them is ever mid-add — one of those is a host
  that works in both cases.
- **Verify, do not assume.** Check `is_visible_in_tree()` after parenting and
  move on if false: some autoloads are invisible by nature (a fade overlay), and
  a hidden host puts the rects straight back to `0x0`.
- Check `get_parent() != null` after any `add_child` you cannot supervise, and
  assert on THAT rather than letting it surface downstream.

Deferring the work (`build.call_deferred()`) also fixes the direct run, and was
rejected here: it breaks every test that rightly expects the scene to be usable
once `_ready()` returns.

## Capturing a real rendered frame — xvfb + opengl3 + x11*

`--headless` uses the dummy renderer, which never compiles GLSL and no-ops
MultiMesh writes — glow, z-order, fog and shader output are invisible to GUT.
For real pixels (or real shader compilation) without a window on the user's
desktop:

```
timeout 60 xvfb-run -a -s "-screen 0 1440x960x24" godot --path . <scene.tscn> \
    --rendering-driver opengl3 --display-driver x11 --quit-after 180
```

Both flags are load-bearing. **Vulkan does not work under Xvfb** (*"None of the
devices supports both graphics and present queues"*) and without
`--display-driver x11` Godot tries Wayland and dies (*"Can't connect to a
Wayland display"*). `--quit-after N` counts *frames*, not seconds; for a
long-settling scene start `Xvfb :99` by hand, `sleep`, `import -window root
shot.png` and `kill`.

To screenshot from code, run a throwaway scene that instantiates the target,
`await RenderingServer.frame_post_draw`, then
`get_viewport().get_texture().get_image().save_png(...)`; delete it afterwards.

- **`add_child` the target deferred** (`add_child.call_deferred`) — inline
  reproduces the busy-parent failure above.
- **`Input.action_press()` does not drive `_input`/`_unhandled_input`**; use
  `Input.parse_input_event()` with a real `InputEventKey`, pressed then released.

For a before/after, compare numerically over a small crop:

```bash
magick shot.png -crop 60x35+765+760 +repage -format "mean=%[fx:mean] max=%[fx:maxima]" info:
```

A `max` below 1.0 is proof nothing can bloom, whatever the CPU-side colour
function returns. A green suite proves the mechanism, not the picture (#589).

## A `:=`-inferred var fed by `Dictionary.keys()`/`.values()` compiles under `check` but fails under GUT*

A typed `Dictionary[SpellDef, int]` erases its key/value types through `.keys()`
and `.values()` — both hand back an untyped `Array`, so every element is a
`Variant` as far as the analyser is concerned. `mise run check` lets the
`:=` inference slide; GUT's load path does not, and you get a compile error on
a file that just passed the cheap gate.

**How to apply:** annotate the loop var explicitly instead of inferring it —
`for spell: SpellDef in dict.keys():`, never `for spell in dict.keys():` with a
downstream `:=`.

## `run/main_scene` stays on the frontmatter menu

`run/main_scene` is `scenes/meta/meta_root.tscn` and it is a config setting on
purpose: an autoload cannot redirect *before* the main scene is built, so
pointing the setting at a sandbox made every exported build construct that
level and cut away from it a moment later. Launch a sandbox by path
(`godot --path . scenes/<sandbox>.tscn`), never by repointing the main scene.
