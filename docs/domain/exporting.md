# Exporting a build

`mise run build` produces the two artifacts a LAN session needs, and nothing
else — no packaging, no upload.

```
mise run build:templates        # once per engine bump: ~1GB of export templates
mise run build                  # linux + windows, release
mise run build -- linux         # one platform
mise run build -- windows --debug
mise run build -- --dirty       # export from an uncommitted tree, honestly stamped
```

Artifacts land at `export/linux/skill-tree-of-life-<sha>.x86_64` and
`export/windows/skill-tree-of-life-<sha>.exe` — the commit is the only version
this project has, so it goes in the name as well as in the stamp, where a
directory listing or a chat attachment can read it without launching anything.
A `--debug` export gets a further `-debug` suffix, so it cannot overwrite the
release build off the same commit. Nothing is pruned: old builds accumulate
until you delete them, which is what lets you run two shas side by side.

Both **embed their pck**, so each is one file to copy to the other machine, and
`export/` is gitignored. Only `mise run build` names and stamps artifacts this
way — an export from the editor's own dialog still lands at the preset's
default path with no stamp at all.

## Templates are a separate task on purpose

Godot has no CLI for fetching export templates, and the `.tpz` is a ~1GB
monolith covering every platform — there is no linux+windows slice. So
`build:templates` is its own rarely-run task rather than a step of `build`,
and it derives the version from `godot --version` so a bump to `[tools]` in
`mise.toml` needs no edit here.

**The directory name is load-bearing**: the engine looks up
`export_templates/4.7.2.stable/`, with the engine's own `x.y.z.stable`
spelling — *not* the mise pin's `4.7.2-stable`. Any other spelling reports
"no export template found for the platform" as though nothing were installed.

## The build stamps its own commit, and why that is not cosmetic

An exported build has no `res://.git`, so [`BuildInfo`](../../autoload/build_info.gd)
would report an empty sha. That matters because `CommandLink`'s #546 hello gate
**compares shas and refuses a mismatched link** — and with no stamp, two
*different* builds both announce `""`, compare equal, and go on to desync on
the wire instead of refusing at link-up. That is precisely the silent failure
#546 exists to kill, reintroduced by the act of exporting.

So `mise run build` writes `build_stamp.cfg` (gitignored, generated per export,
deleted afterwards) from the exporting checkout's HEAD, the presets pack it via
`include_filter`, and `BuildInfo` falls back to it when there is no `.git`.
`is_dev` stays false — it means "running from a checkout", which a build is not
— but the pause-menu footer now shows whenever a sha is *known*, so a machine
can answer "which build am I running" without diffing two exes.

### `--dirty`

A dirty tree makes the stamped sha a lie, so the default is to refuse and print
`git status --short`. `--dirty` is the escape hatch and it does **not** weaken
the gate: the stamp becomes `<sha>+<digest>` where the digest hashes the full
working diff plus the untracked file list, so two builds off the same tree
still match and any difference still refuses. The diff is written to
`export/<digest>.diff` so the state stays reproducible rather than merely
labelled.

## What the presets exclude, and the two things they must not

`export_filter="all_resources"` plus an `exclude_filter` — not the
`"resources"` (scene-dependency) filter, which would drop everything this
project reaches by `load()` at runtime: content-pack `.tres`, procgen pools,
spell defs. The sharpest single proof is
[`carve_atlas.gd`](../../skill_node/visuals/emblem/carve_atlas.gd) — it holds
the atlas path as a plain `String` const, so Godot records no dependency on it
and a dependency-based export would ship a game with no emblems on it.

Excluded: the dev-only addons, `test/`, `docs/`, `tools/`, `scratchpad/`,
`.mise/`, `*.md`. That takes the payload from ~130M of project content down to
**~6M** — a 76M linux artifact, almost all of which is the ~70M engine template.

Two exclusions look obvious and are wrong, both because *shipped code reaches
into a dev addon*:

- **`addons/at-icons/control/` is gameplay art.** Every `entity/factions/*.tres`
  points its emblem at an SVG in there (`bird`, `dragon`, `chess_king`, …), and
  the editor picker offers all 618, so the whole subdirectory stays. The other
  five subdirectories (`animation/`, `mesh/`, `node/`, `node2d/`, `node3d/`) are
  the same icon set retinted for other node types, nothing references them, and
  they are ~25M — those are excluded.
- **`addons/stat_board_visualizer` is preloaded by shipped UI** —
  `ui/stat_board_overlay/stat_board_overlay.gd` `preload`s
  `stat_board_graph.tscn`. Excluding it breaks the overlay at load, not at use.

Before adding an exclusion, check for references from outside the directory:

```
grep -rl "res://addons/<name>/" --include="*.tscn" --include="*.tres" --include="*.gd" .
```

### `all_resources` ships the whole of `assets/`, referenced or not

`assets/` is a *stock of material*, not a manifest of what the game uses. With
`all_resources`, everything in it ships whether a scene points at it or not — in
2026-09 that was **17M of the 22M of packed art with zero references**, mostly
purchased packs kept for six files each.

That was first fixed by excluding them and then fixed properly by **deleting
them** (owner call 2026-09-04): the six pause-menu icons that justified keeping
`Icon set 1` were re-cut from game-icons.net through `mise run icons:update`, and
the packs went. Prefer that order — an exclusion is the holding pattern, a
delete plus a pipeline-baked replacement is the answer, and it leaves nothing to
go stale. The archives still in `assets/` (`icons.zip`, `border_pack.rar`, …)
are repo weight only: Godot has no importer for them, so they were never packed.

If you do reach for an exclusion, two traps:

- **`*` crosses `/`.** `assets/*.png` does not mean "the loose pngs in
  `assets/`" — it matches every png at any depth under it, including live
  `emblem_luts/` and `icons/spells/` art. Name loose files individually.
- **A directory can be partly live.** `Icon set 1/` shipped at three
  resolutions with six files used from one of them. `assets/emblem_luts/` is the
  standing example: the spell LUTs feed the CARVE atlas, while the `addon_*` and
  `armed_*` LUTs the icon bake also emits there are referenced by nothing
  (~348K, known, not yet cleaned).

The audit is a text grep over what itself ships, and it is trustworthy here
because the project holds **no binary `.res`/`.scn`/`.theme`** — every reference
is in a file grep can read. Confirm that still holds before believing a new
audit:

```
find . -name '*.res' -o -name '*.scn' -o -name '*.theme' | grep -v '/.godot/'
```

And **no test can catch an over-aggressive exclusion** — the suite runs in the
checkout, where every asset exists. The filter only exists in the pack, so
verification is the export itself: `grep -aF "<name>" <artifact>` on the
embedded pck answers both "did it go" and "did the live neighbour stay".

## Verifying an export

**Godot's exit code is not the check** — `--export-release` has returned 0 on a
failed export in 4.x, so the task asserts each artifact exists and is non-empty
and prints its size. Two other traps it handles:

- A cold `.godot/` has no import cache, and a headless export against one
  produces an artifact missing every imported asset. The task runs
  `--headless --import` first.
- Windows icon and version metadata are deliberately left empty. Stamping them
  needs `rcedit` under wine configured in the editor settings; without it the
  export warns, and with it it is a separate concern from producing a runnable
  build.

## What only an export can show you

The first real export of this project (2026-09-01) booted, and printed **two**
classes of failure that `mise run check`, the GUT suite and `godot --path .`
cannot produce. Assume any new one of these shapes is invisible until someone
exports. (It printed a third, `res://<null>`, which *was* reproducible from
source — see the section below; the export got the blame for a while and did
not deserve it.)

**1. A runtime `DirAccess` scan finds nothing in a PCK.** `StatRegistry` scanned
`stats_system/defs/` for `*.tres`. The exporter rewrites each `.tres` into a
`.res` + `.tres.remap` pair, so the filter matched nothing, the registry came up
empty, and every stat lookup in the build failed — 20 `unknown stat id` /
`def missing` warnings on frame one, 0 from source. This is #640's bug, which
was fixed for `CoreClass` and left live here. The rule that prevents it is
**#597 D13: directory scan for editor and test code, authored array for
runtime** — see [`StatDefRoster`](../../stats_system/stat_def_roster.gd) and
`test/unit/test_stat_def_roster.gd`, which fails if the roster and the
directory drift apart.

**2. Naming an editor-only global is a PARSE error under an export template.**
`ui/tooltip_fan/fan_anchor_driver.gd` mentioned `EditorInterface` in a function
that already returned early on `not Engine.is_editor_hint()` — irrelevant, since
the failure is at parse time, before any guard runs, and it killed the *whole
script*. `Engine.is_editor_hint()` cannot fix this; reach the singleton
indirectly instead:

```gdscript
var editor := Engine.get_singleton(&"EditorInterface")
editor.set_main_screen_editor("Sandbox")
```

Note the second-order trap: the returned value is untyped, so `var x := editor.foo()`
then fails to infer. Annotate the type (`var host: Node = …`).

This only matters for scripts that ship. Inside `addons/` — excluded from the
export — naming `EditorInterface` directly is fine, which is why the codebase is
full of it.

## A boot error with no backtrace: `res://<null>`

Three `Resource file not found: res://<null>` errors at boot, fixed 2026-09-01.
The three `sampler2D` entries in `project.godot`'s `[shader_globals]`
(`vision_circles_tex`, `vision_tile_index_tex`, `vision_tile_indices_tex`) were
serialized with `"value": null`. The rendering server resolves every sampler
global by path at startup, and `String(null)` is `"<null>"`, which localizes to
`res://<null>`. Setting each value to `""` silences all three (verified
2026-09-01, editor and running game).

Two things hid it for weeks. It needs a **real renderer** — every `--headless`
run, which is the whole test suite, is clean, so it looks export-only when it
is not. And it carries **no GDScript backtrace**, because no script is
involved: it fires during server/scene init, before any autoload.

`--verbose` is what cracks that shape. The load stream names the failing path in
order (`Loading resource: res://<null>`), so what loaded *just before* it points
at the caller — here, immediately after `res://theme.tres`.

**Watch for a regression** — the editor's *Shader Globals* project-settings
panel is a plausible source of the `null`s, so re-check `git diff project.godot`
after touching it.

## Testing multiplayer across two machines

Both machines run the **same** build — the sha gate refuses a mismatch at hello
and prints both stamps, which is the whole point of the stamping above. One
hosts from the frontmatter menu's HOST leaf (it asks for a port), the other
takes JOIN and types the host's LAN address and that port. Nothing needs a
checkout, an editor, or a CLI flag.

The `--role=host/--role=client` CLI harness in `scenes/dev/` is a *dev* path and
stays that: an exported build always enters `Boot`'s menu route, and cannot be
handed a scene to run. See [multiplayer-harness.md](multiplayer-harness.md).
