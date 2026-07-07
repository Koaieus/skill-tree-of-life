---
description: Godot project workflow — class cache refresh, scene round-trip safety
---

# Godot workflow

> "*" at end of header: No need to inform user on any of this.

## Refreshing the class cache after class_name changes*

After renaming a `class_name` or adding a new one, the project's
`.godot/global_script_class_cache.cfg` is stale. Runtime parse fails with
*"Could not find type X"* even though the source is correct. The cache
only rebuilds when the editor enumerates the project. Force it via:

```bash
godot --headless --editor --quit
```

## Always git status after a refresh*

The editor pass round-trips any scene OR `.tres` it briefly touches and
can silently mutate them. Observed:

- **Dropped node instances** — `[node name="UIRoot" ...]` vanished from
  `dev_sandbox.tscn` during a refresh, with the matching ext_resource
  removed too. Runtime then failed on `$UI/UIRoot` lookup.
- **Regenerated sub_resource ids** — `Resource_umwfs` → `Resource_qrijo`,
  with the consumer reference updated in lockstep (cosmetic, but noise).
- **Position normalisation** — node positions tweaked by a few pixels
  if the editor briefly re-laid out something.
- **Stripped `.tres` fields + sub-resources** — `spark.tres` lost its
  `damage = 5` line, its `range_finder` sub-resource, and the
  `HopRangeFinder` ext_resource entry. The author code (`SpellDef.damage`,
  `SingleHostileNodeTargeting.range_finder`) was correct; the editor
  re-serialized with a *stale view* of the class's field set, omitting
  fields it didn't recognise at that moment. Functionally castrates the
  resource silently — runtime parses it fine, behaves wrong.

Position/id noise is fine. Dropped instances and stripped fields are not.
Mandatory pattern:

```bash
git status                   # before refresh
godot --headless --editor --quit
git diff scenes/ '*.tres'    # immediately after
# restore anything load-bearing that disappeared
```

For `.tres` files specifically: also boot and exercise the resource's
behaviour if you can — silent strip won't cause a parse error, so the
diff is your only signal until the bug surfaces in gameplay.

## Don't refresh while the user is editing

If the user has the editor open and is actively saving, a second
`--editor --quit` invocation can race their autosave and lose work.
Either:

- Wait until they confirm they're done, or
- Leave the parse error visible — they'll see it next time they open
  the editor, which triggers its own refresh.

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
[entity-death.md](entity-death.md).

### Typed variable + freed dict entry = crash before is_instance_valid*

`var t: FloaterToaster = dict.get(key)` — if the dict holds a freed instance,
the typed assignment crashes before `is_instance_valid` gets a chance to run.
Read into an untyped var first:

```gdscript
var stored = dict.get(key)
var t: MyType = stored if is_instance_valid(stored) else null
```

### Git
## Closing an issue?
Mention "Closes #{id}" in the commit message.
## Worktrees (#86)
Use `mise run worktree:new -- <issue|name>` / `worktree:ls` / `worktree:rm -- <fuzzy>`
(see `mise.toml`) to get an isolated checkout under `.worktrees/<slug>/`
instead of editing the main checkout directly. The `warp` skill
(`.claude/skills/warp/SKILL.md`) drives the full issue → worktree →
implement → approval → merge → close → teardown cycle on top of these tasks.

Each worktree has its own gitignored `.godot/` — confirmed empirically (#86
spike) that a fresh worktree's cold `godot --headless --editor` import
neither touches nor corrupts the main checkout's `.godot/`, and is fully
independent (own import cache, own class cache).

The main checkout itself is still a **shared, un-worktree'd surface** —
other agents may be doing stuff there directly, or there may be uncommitted
WIP. If tests suddenly start failing there, don't spend too much time on it,
so far you can still get another part done. If things are in your scope or
quick fixes, apply — but check what was happening. It might be a first step
of a refactor, if so see if you can follow its lead, verify with user for
alignment.
User likes clean codebase. Refactoring into scenes, DI via `@export`ed vars, inherited
scenes where needed, always try and take it to the next level, keeping common
conventions for YAGNI but the opposite of YAGNI may pay off too: planning ahead. Case by case care works best.
