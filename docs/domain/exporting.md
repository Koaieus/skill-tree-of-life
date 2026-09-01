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

Artifacts land at `export/linux/skill-tree-of-life.x86_64` and
`export/windows/skill-tree-of-life.exe`. Both **embed their pck**, so each is
one file to copy to the other machine. `export/` is gitignored.

## Templates are a separate task on purpose

Godot has no CLI for fetching export templates, and the `.tpz` is a ~1GB
monolith covering every platform — there is no linux+windows slice. So
`build:templates` is its own rarely-run task rather than a step of `build`,
and it derives the version from `godot --version` so a bump to `[tools]` in
`mise.toml` needs no edit here.

**The directory name is load-bearing**: the engine looks up
`export_templates/4.7.1.stable/`, with the engine's own `x.y.z.stable`
spelling — *not* the mise pin's `4.7.1-stable`. Any other spelling reports
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
spell defs.

Excluded: the dev-only addons, `test/`, `docs/`, `tools/`, `scratchpad/`,
`.mise/`, `*.md`. That takes the payload from ~130M of project content to
**~13M** on top of the 70M engine template.

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

The first real export of this project (2026-09-01) booted, and printed three
classes of failure that **zero** of `mise run check`, the GUT suite, and
`godot --path .` can produce. Assume any new one of these shapes is invisible
until someone exports.

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

**3. Three `No loader found for resource: res://<null>` errors at boot.**
Present in a control export with an empty `exclude_filter`, so *not* caused by
the exclusions above, and absent when run from source. Unattributed as of
2026-09-01 — harmless so far, but it is an export-only defect and worth an
issue rather than a shrug.

## Testing multiplayer across two machines

Both machines run the **same** build — the sha gate refuses a mismatch at hello
and prints both stamps, which is the whole point of the stamping above. One
hosts from the frontmatter menu's HOST leaf (it asks for a port), the other
takes JOIN and types the host's LAN address and that port. Nothing needs a
checkout, an editor, or a CLI flag.

The `--role=host/--role=client` CLI harness in `scenes/dev/` is a *dev* path and
stays that: an exported build always enters `Boot`'s menu route, and cannot be
handed a scene to run. See [multiplayer-harness.md](multiplayer-harness.md).
