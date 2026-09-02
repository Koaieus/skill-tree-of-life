---
description: Godot project workflow — class cache refresh, scene round-trip safety
---

# Godot workflow

> "*" at end of header: No need to inform user on any of this.

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

## `@tool` scripts must guard `_ready()` with `Engine.is_editor_hint()` when they write to node properties*

`@tool` scripts that modify `modulate`, child-instanced `@export` vars, or
shader parameters during `_ready()` dirty the scene on every editor load.
Godot serialises those writes back into the `.tscn` as property overrides,
which can accumulate cruft and lose intentional values over save/reload cycles.
Guard anything that isn't pure visual setup:

```gdscript
func _ready() -> void:
    if Engine.is_editor_hint():
        return   # don't modify the scene during editor load
    _apply_active(false)
```

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
load — a headless test run counts — and the repo tracks them (392 under
`test/unit/` alone). A branch that adds scripts must commit their sidecars too,
or the worktree is left with untracked strays that the next checkout regenerates
as churn (#716's two test scripts landed sidecar-less and needed a pinning chore
commit). Sweep for `?? *.uid` in `git status` at branch-finish time.

Known pre-existing orphan: `addons/gut/menu_manager.gd.uid`, shipped by vendored
GUT 9.6.0 (`24da57f`) with no companion script. Left alone deliberately — don't
diverge from a vendored addon over it.

## Refreshing a stale class cache — rename, rebase, or fresh worktree*

The project's `.godot/global_script_class_cache.cfg` goes stale whenever the set
of `class_name`s moves under it. Three triggers, one fix:

- You renamed or added a `class_name`.
- You **rebased, pulled, or ff-merged a branch** and *someone else's* commit did.
  Nothing in your own working tree changed, which is what makes this one
  surprising. The swarm case: ff-merging a reviewed drone branch that added a
  `class_name`, then running the authoritative suite in the main checkout — it
  comes back red with hundreds of failures and it is the cache, every time.
- You're in a **fresh worktree** — it has its own gitignored `.godot/` (see the
  worktrees section below), so it starts with *no* cache at all.

Two symptoms, and only the first is loud. Runtime parse fails with *"Could not
find type X"* even though the source is correct — or **GUT reports a green run
with a lower `Scripts`/`Tests` total**, because a script that can't resolve a
type fails to parse and GUT skips the whole file silently
(`.claude/rules/testing.md`). Don't go auditing the test file; refresh first.

The cache only rebuilds when the editor enumerates the project:

```bash
mise run refresh      # or: godot --headless --editor --quit
```

**`refresh` reporting "nothing changed" does NOT mean the cache was already
current.** That verdict describes *file churn* — which scenes and resources the
editor pass re-serialized — and a cache rebuild moves no tracked file, so a run
that just fixed your build reports exactly the same "nothing changed" as a
no-op. Read it as "nothing for you to review or restore", never as "the cache
was fine, so this failure must be real". **Re-run the failing thing before
concluding anything**; the ordering that misleads is refresh-says-nothing →
assume-cache-was-fine → go hunting a phantom regression in someone's commit.

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
godot --headless --path . --check-only --script network/world_fingerprint.gd
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

**Calibrate before you read the list: the expected outcome is nothing, or
cosmetic noise.** Every possible effect below is a text diff in a git-tracked
file — you can *see* all of it, revert it in one command, and the worst case on
record is a handful of lines restored in under a minute. The entire protocol is
`git diff` after the pass.

So: refresh when you need to. Do not stall waiting for a safe moment, do not
build a workaround, do not `md5sum` anything, do not ask the user for
permission, and do not spend turns investigating a diff you can simply read.
Attention spent here is attention taken from the implementation you're actually
doing. Glance at the diff, check any *non-default* value that vanished against its
script default, and get back to work.

The editor pass re-serializes any scene or `.tres` it briefly touches. Every
git-visible effect on record has been cosmetic or benign:

- **Default-elision** — a pass over `procgen/pools/*.tres` dropped
  `operation = 0`, `archetype_stat = &""`, `unit_value = 1.0`, `min_tier = 1`
  and added `uid=` to ext_resources: 95 deletions across 8 files, alarming at a
  glance. Every dropped line equalled its class default, and non-default values
  (`max_tier = 2`) were **kept**. Godot omits defaults on re-serialize —
  semantically identical.
- **A shifted default does this on its own, with no editor pass involved** —
  `e521ac2` dropped `max_hops = 3` from `spark.tres` because
  `hop_range_finder.gd` declares `@export var max_hops: int = 3`. The stored
  value met the default, so the line stopped being written; runtime unchanged.
  The mirror case *adds* a line when a default moves away from a stored value.
- **Regenerated sub_resource ids** — `Resource_umwfs` → `Resource_qrijo`, with
  the consumer reference updated in lockstep (cosmetic, but noise).
- **Position normalisation** — node positions tweaked by a few pixels if the
  editor briefly re-laid out something.

**No committed instance of the editor destroying a non-default value has ever
been found.** This section asserted two; both were audited out 2026-08-29 —
`ed73af65` ("…stripped by editor") is a no-op against its parent `00a3f442`,
and `UIRoot` is present unchanged in `1d3ca92`. Neither loss reached git.

So if a non-default value vanished, check its `@export` default **at that sha**
(`git show <sha>:script.gd`) before concluding anything: equal → elision, safe;
different → you have the first evidenced case, record the sha. Nobody ran that
command for two and a half months, and "restore it" is what produced
`ed73af65` — a no-op written up as a witnessed incident.

These re-appear on every editor pass, so don't fold them into an unrelated
commit: either revert them, or commit them alone as normalization.

The whole protocol:

```bash
mise run refresh
```

It runs the pass, excludes pre-existing dirt, and hands back a verdict —
`✓ refresh done — nothing changed`, or a grouped report separating benign
sidecar/`.import` churn from authored files, listing **only the non-trivial
lines removed**. That list is the entire judgement call; everything else it
already classified for you. Don't hand-diff unless it points you somewhere.

## Refreshing while the user has the editor open — just do it

Don't stall work waiting for the user to close the editor. A refresh pass
alongside an open editor is normal: worst case it regenerates `.uid` files
and import metadata, which are git-tracked and need committing anyway, and
which the open editor would have produced itself on its next start.

The round-trip diff the section above documents is the same whether or not an
editor is open, and `git diff` covers both. So: run it, then diff.

Only pause for confirmation if the user is mid-save on the very files you're
about to touch.

### When the refresh is safe to skip

Pure script changes (function body edits, new methods, new files
WITHOUT a new `class_name`) don't need a refresh — the runtime parses
those fresh. Only `class_name` introduction / rename / removal requires
the cache to be rebuilt.

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

The node just renders its untextured fallback (a white quad). To actually
compile shaders headlessly, drive a real backend under a virtual display:

```bash
xvfb-run -a godot --path . --rendering-driver opengl3 --quit-after 30 \
  res://path/to/scene_using_the_shader.tscn 2>&1 | grep -iE 'compilation failed|no matching'
```

opengl3 (mesa/llvmpipe) needs no GPU and surfaces the codegen error even though
production uses the RD/Vulkan backend — the bug is in Godot's shader codegen, so
it reproduces on either backend. Empty grep = compiles clean.

`mise run check-shaders` (#682) walks every `.gdshader`/`.gdshaderinc` in the
repo and is a real gate — worth running before reaching for the manual
`xvfb-run` recipe above. But it stays on the plain `--headless` dummy
renderer for speed, so it only proves the tier this file's own examples
distinguish: GDSL parse/type errors (an undefined function call, a name
collision) surface there too, confirmed by injection. The **silent codegen
miscompile** this section opened with — valid-looking GDSL whose generated
GLSL is broken only at the backend compile step — is a different tier, and a
green `check-shaders` says nothing about it. That bug class still needs this
section's `xvfb-run … --rendering-driver opengl3` recipe.

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
- **Per-Label supersampling** is the scoped version of the first: set
  `font_size * N`, `scale = 1/N`, and lay the box out in raster units — a
  `Control` scales about its own `position`, so centring must still use the DRAWN
  width. `MenuNodeView._supersample_caption` is the worked example.

**`generate_mipmaps` is inert on its own.** Godot's default canvas filter has no
mipmap stage, so the mipmaps are never sampled until a CanvasItem sets
`texture_filter = 4` (`LINEAR_WITH_MIPMAPS`). That pair is what fixes the
*minified* case; supersampling only fixes the magnified one.

Judge all of this by screenshot (below) — the headless suite cannot see it.

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

### Typed variable + freed dict entry = crash before is_instance_valid*

`var t: FloaterToaster = dict.get(key)` — if the dict holds a freed instance,
the typed assignment crashes before `is_instance_valid` gets a chance to run.
Read into an untyped var first:

```gdscript
var stored = dict.get(key)
var t: MyType = stored if is_instance_valid(stored) else null
```

### Git
## `gh --body "..."` with backticks corrupts the comment — always use `--body-file`
A double-quoted shell string runs command substitution on backticks. Posting a
comment containing `` `NodeStatBoard extends StatBoard` `` silently deleted that
span (zsh ran it as a command, it failed, the empty result was substituted) and
published the mangled text. No error from `gh` — the corruption is only visible
by reading the posted comment back. Since issue bodies and comments here are full
of `` `code` `` spans, write a heredoc to the scratchpad and pass `--body-file`.
Recoverable with `gh issue comment <n> --edit-last --body-file`.

## Closing an issue?
Mention "Closes #{id}" in the commit message. Only fires on push — users already know this.
## Worktrees (#86)
Use `mise run worktree:new -- <issue|name>` / `worktree:ls` / `worktree:rm -- <fuzzy>`
(see `mise.toml`) to get an isolated checkout under `.worktrees/<slug>/`
instead of editing the main checkout directly. The `warp` skill
(`.claude/skills/warp/SKILL.md`) drives the full issue → worktree →
implement → approval → merge → close → teardown cycle on top of these tasks.

For a pre-planned issue that splits into file-disjoint units, the `swarm` skill
(`.claude/skills/swarm/SKILL.md`) fans that cycle out across parallel subagents —
Opus orchestrates, Sonnet/Haiku execute, each following `drone`
(`.claude/skills/drone/SKILL.md`). Those workers get their worktrees from the
harness (`isolation: "worktree"` → `.claude/worktrees/agent-<id>/` on branch
`worktree-agent-<id>`), not from `mise run worktree:new`.

Each worktree has its own gitignored `.godot/` — confirmed empirically (#86
spike) that a fresh worktree's cold `godot --headless --editor` import
neither touches nor corrupts the main checkout's `.godot/`, and is fully
independent (own import cache, own class cache).

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

## Screenshotting the running game (for anything the headless suite can't judge)

Glow, z-order, fog, and shader output are invisible to GUT — the dummy renderer
no-ops MultiMesh instance writes and never compiles GLSL. To get a real frame:

```bash
Xvfb :99 -screen 0 1600x1000x24 & sleep 3
DISPLAY=:99 godot --path . --rendering-driver opengl3 res://scenes/dev_sandbox.tscn &
sleep 25                       # let the scene settle
DISPLAY=:99 import -window root shot.png
```

`--quit-after N` counts *frames*, not seconds, and will often quit before the
scene has settled — prefer `sleep` + an explicit `kill`.

For a before/after on a visual change, shoot both, then compare numerically
rather than by eye — ImageMagick over a small crop makes it objective:

```bash
magick shot.png -crop 60x35+765+760 +repage -format "mean=%[fx:mean] max=%[fx:maxima]" info:
```

This is how the self-loop HDR lift was verified: `max` went 0.592 → 1.000
(i.e. it now crosses `glow_hdr_threshold` at all) and the regional `mean`
roughly doubled, which is the bloom halo bleeding into neighbouring pixels.
A `max` below 1.0 is proof that nothing can bloom, whatever the CPU-side colour
function returns.

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

This is not hypothetical. It is exactly the blind spot that let **#413 ship
invisible edges** past every headless probe: the whole batched-edge render path
was verified by a suite that could not see it.

**Instead, expose the computation as a pure function and assert that.**
`ui/frontmatter/menu_edge_view.gd` is the pattern — `segment_transform(from, to)`
and `instance_transform()` are static/pure, fully testable, and the
`set_instance_transform_2d` call site shrinks to a one-liner with nothing left
to get wrong:

```gdscript
func _push_transform() -> void:
	multimesh.set_instance_transform_2d(0, instance_transform())
```

Instance **colours and custom data do** round-trip today. Do not lean on it —
the same driver owns them, and nothing guarantees the asymmetry survives an
engine bump.

Anything that must be verified as *actually drawn* needs a real frame — see
"Screenshotting the running game" above. Headless can verify the arithmetic that
feeds the GPU; it cannot verify that the GPU did anything with it.

## `add_child` fails SILENTLY on a busy parent — and a directly-run scene has `root` busy*

`Node.add_child()` does not raise when the parent is "busy setting up children".
It prints an error and **does nothing** — the child stays unparented, and the
next line runs as if it worked.

`root` is exactly that while the `SceneTree` is adding a scene that was run
DIRECTLY: F6 in the editor, or `run/main_scene`. So any `_ready()` in that scene
which reaches for `get_tree().root.add_child(...)` is doing it inside the one
window where it cannot succeed.

This shipped as a real crash (#589/C1): `MenuFanHarness.measure()` parents itself
to `root` for one synchronous call, because `Container.fit_child_in_rect()`
early-returns on anything not `is_visible_in_tree()` and a detached Control
measures every rect as `0x0`. On a direct run it never parented — and the first
symptom was a null `get_parent()` three calls later, then a missing dictionary
key, then an assertion naming an unrelated thing. **None of the three errors
named the cause.**

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

## Capturing a real rendered frame headlessly — xvfb + opengl3 + x11*

`--headless` renders nothing (dummy driver), so it cannot answer "does this look
right". To get real pixels without opening a window on the user's desktop:

```
timeout 60 xvfb-run -a -s "-screen 0 1440x960x24" godot --path . <scene.tscn> \
    --rendering-driver opengl3 --display-driver x11 --quit-after 180
```

Both flags are load-bearing. **Vulkan does not work under Xvfb** — it fails with
*"None of the devices supports both graphics and present queues"* — and without
`--display-driver x11` Godot tries Wayland first and dies on
*"Can't connect to a Wayland display"*.

To screenshot rather than just check for errors, run a throwaway scene that
instantiates the target, `await RenderingServer.frame_post_draw`, then
`get_viewport().get_texture().get_image().save_png(...)`. Two gotchas:

- **`add_child` the target deferred** (`add_child.call_deferred`) — see the
  section above; doing it inline reproduces the busy-parent failure.
- **`Input.action_press()` does not drive `_input`/`_unhandled_input`.** A splash
  or menu waiting on a real event will not advance. Use
  `Input.parse_input_event()` with an actual `InputEventKey`, pressed then
  released.

**Why it matters.** A green suite proves the mechanism, not the picture. The
#589 swarm shipped six units with the suite green throughout while the menu
crashed on every direct run, and while one unit's headline visual change was
invisible on screen. Delete the throwaway scene + script afterwards.
