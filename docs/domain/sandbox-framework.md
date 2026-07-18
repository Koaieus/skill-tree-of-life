# Unified sandbox framework (design)

Status: **design / in progress.** Tracks the plan to fold the project's
single-module sandboxes + editor plugins into one host. Phase 0 (the allocation
VFX showcase) shipped; the rest is sequenced below. This doc is the source of
truth for *why the obvious first step is a trap* and what to do instead — read it
before touching `game_root.tscn` for "anti-drift" reasons.

## The goal

We have several module-testing surfaces, each set up differently:

| Surface | Form today | Mode it wants |
|---|---|---|
| Spell cast / hop tuning | `addons/spell_playground/` (plugin) | live-edit |
| VFX / projectile launcher | `addons/vfx_playground/` (plugin) | live-edit |
| Stat-board visualizer | `addons/stat_board_visualizer/` (plugin) | live-edit |
| Allocation / dealloc / death VFX | `scenes/dev/allocation_vfx_showcase.tscn` (scene) | **played** |
| Melee blade | `blade_playground` (scene, stale) | played |
| Ranged | — (none yet) | played |
| Loot | — (foreseen) | played |

Each re-derives graph + nodes + edges + entities + systems its own way, so they
drift from real gameplay. **If a sandbox mismatches the game, it's not proving
anything.** The vision: one full-screen editor host with tabs; tab-able classes
expose a button that jumps to their tab; the host stays in sync with Inspector
edits; eventually it auto-discovers tabs.

## The load-bearing distinction: two execution modes

"Live in the editor, no reload" is free **only for `@tool`-amenable content** —
stat-board link graphs, spell-hop tuning, VFX *look*. The allocation / battle /
loot / death surfaces run **non-`@tool` gameplay systems driven by a sequenced
`await` loop**; those do not execute live in-editor unless we make
`BattleSystem`/`AllocationSystem` `@tool` (invasive — and we explicitly do *not*
want `TurnManager`/AI ticking inside the editor).

So the tab base must **declare its mode**:

- **live-edit tab** (`@tool`, reacts to the Inspector instantly): stat
  visualizer, VFX look, spell hops.
- **played tab** (runs on play, drives real systems): allocation, melee, ranged,
  loot, death.

Don't promise "live for everything" — that's exactly where it breaks.

## Why the naive `systems.tscn` extraction is a trap

The instinct for anti-drift is: extract `GameRoot`'s `Systems` subtree into a
reusable `systems.tscn` so everyone instances one wiring source. **Don't** — four
findings (all verified 2026-06-28) undermine it:

1. **Level scenes already inherit `game_root.tscn`.** `dev_sandbox`,
   `first_level_sandbox`, and `procgen_play_sandbox` are *inherited scenes* of
   `game_root.tscn`, so they already share the Systems wiring for free. There is
   no drift *between the real levels*. The drift victims are the **standalone
   playgrounds**, which don't inherit it.
2. **Standalone playgrounds want a *subset*, not the whole bundle.** The
   allocation showcase deliberately omits `TurnManager` (no turn loop),
   `VisionSystem` (fog would hide its nodes), `UIRoot`, input, and `LootSystem`
   (would mutate the dead core). A monolithic bundle forces dormant-but-present
   systems that actively misbehave (Vision fogs; Loot drops addons).
3. **`%` unique names don't cross an instance boundary.** Verified: a node marked
   `unique_name_in_owner` inside an instanced sub-scene is **not** reachable via
   `%Name` from the instancing scene (returns null). `GameRoot` reads
   `%AllocationSystem` … and `procgen_play_sandbox` reads `%VisionSystem`;
   extraction forces an accessor rewrite (typed properties on the bundle root).
4. **Inherited scenes override `Systems` children by path/index.**
   `dev_sandbox.tscn` overrides `Systems/PlayerInputController.player` and
   `Systems/VisionSystem.viewers` (declarative, the project's preferred style —
   see `scene-composition.md`). Moving `Systems` into a sub-scene breaks those
   overrides; the only repairs are (a) migrate them to code (degrades
   dev_sandbox's clean declarative wiring) or (b) editable-children on the
   instance (the fragile pattern we rejected). Either way fog/input break in a
   way **unit tests won't catch**.

Net: a monolithic `systems.tscn` adds risk to the most central scene while
serving no consumer that isn't already served by inheritance. It's the wrong
abstraction.

## What anti-drift actually needs: a subset-capable, code-level scaffold

The standalone playgrounds need *"a graph + a chosen subset of the real systems,
wired exactly as the game wires them, in one place."* That's a **`SandboxWorld`
composition helper** (code), not a scene extraction — each played tab declares
which systems it needs and the helper instantiates + `bind`s them with the same
calls `GameRoot._ready` uses.

**Built** (`scenes/dev/sandbox_world.gd`) once the second played consumer — the
loot showcase — made the shared shape empirical rather than guessed. The two
sandboxes request different subsets (allocation: the default core; loot:
`{loot = true}` → adds TurnManager + LootSystem), which is exactly what proved
the scaffold must be subset-capable. It's a `class_name`-less duck-typed helper:
`build(graph, opts)` instantiates + wires the requested systems with GameRoot's
exact calls and exposes them as properties.

**Caveat — it's a parallel wiring source, not GameRoot's.** It mirrors
`game_root.tscn`'s wiring; it does not share it (GameRoot wires declaratively in
the .tscn, which we keep). So it unifies wiring *across sandboxes*, but must be
**kept in sync with game_root.tscn** if a system gains a required dependency.
True single-source would mean GameRoot composing systems in code — a regression
of its clean declarative composition, not worth it.

If we later still want `GameRoot` and `SandboxWorld` to share one wiring source,
the safe refactor is to extract a `wire_systems(graph)` *helper function* both
call — not a scene — leaving `game_root.tscn`'s declarative structure (and the
inherited overrides) intact.

## Sequencing

| Phase | Work | Risk | Gate |
|---|---|---|---|
| 0 ✅ | Allocation VFX showcase as a played scene | low | shipped (`a65bfce`) |
| ✅ | LootSystem showcase (2nd played sandbox) + per-side-effect kill-switches | low | shipped (`147f7f6`, `def5e3d`) |
| 2 ✅ | `SandboxWorld` subset-capable system composition (built once the 2nd consumer existed) | low | both showcases share it |
| 1 ✅ | Plugin host: main-screen `EditorPlugin` + `TabContainer`; `SandboxTab` base declares mode (live/played); explicit registration. The 3 playground plugins folded into one host (`addons/sandbox_host/`); showcases are played launch cards. | med | loads clean headless; **GUI behaviour pending human verify** |
| 3 | (partial — done) Inspector "Open in…" buttons now reveal the host main screen + select the tab (`set_main_screen_editor` + `current_tab`). (remaining) Jump-to-tab `@export_tool_button` on tab-able resource classes + finer live Inspector sync (`_edit`/`_handles` + resource `changed`). | low | button jumps; knob edits reflect w/o reload |
| 4 ✅ | Auto-discover tabs — **scene-directory scan**, NOT the `get_global_class_list` class scan the issue first sketched (see below: a dedicated `tabs/` dir is a cleaner declaration). Drop a `*.tscn` whose root is a `SandboxTab` in `addons/sandbox_host/tabs/`; the host loads + adds it, ordered by filename. | low | tabs appear without manual registration |

## The host (`addons/sandbox_host/`)

One main-screen `EditorPlugin` replacing the three bottom-panel playground
plugins. **Everything is scene-composed** (per `scene-composition.md`): the host
is a scene, and every tab is a scene whose root is a `SandboxTab`. The `.tscn`
files are *generated* by `tools/gen_sandbox_tabs.gd` (run headless), not
hand-authored — that dodges the uid-mismatch / field-strip landmines in
`godot-workflow.md`. Re-run it after changing the tab roster.

Files:

- `plugin.gd` — the `EditorPlugin`. `_has_main_screen() → true`; instances
  `sandbox_host.tscn` into `EditorInterface.get_editor_main_screen()` (a
  `VBoxContainer` — the host needs `SIZE_EXPAND_FILL` or it renders collapsed)
  and shows/hides it on `_make_visible`. **Reuses the three playgrounds' own
  `EditorInspectorPlugin` scripts verbatim** and routes their signals → load the
  resource into the matching tab (by `tab_id`) + `set_main_screen_editor` +
  select the tab. So the "Open in…" buttons + the spell auto-sync still work;
  they just target the host now. Icon: `icon.svg`.
- `sandbox_host.tscn` / `.gd` (`class_name SandboxHost`) — a `Control` + a
  `Tabs` `TabContainer`. **Auto-discovers tabs**: scans `tabs/*.tscn`, loads
  each, asserts the root is a `SandboxTab`, adds it, titles it from
  `get_tab_title()`. Numeric filename prefixes (`10_…`, `20_…`) fix tab order.
- `sandbox_tab.gd` (`class_name SandboxTab`) — the mode-declaring base
  (`Mode {LIVE_EDIT, PLAYED}`) every tab scene roots on. The directory-scan
  contract replaces the issue's class-list scan; the `class_name` survives only
  as the runtime `is SandboxTab` guard, not a discovery mechanism.
- `sandbox_live_tab.gd` (`SandboxLiveTab`) + `sandbox_live_tab.tscn` (the
  **scenic base**) — embeds an `@tool` panel via the `panel_scene` `@export`
  (DI); forwards the inspected resource to its `loader_method` by name. `tab_id`
  is the host's routing key. The base `.tscn` carries the shared chrome: a
  toolbar with a **source-path breadcrumb** (click a folder → reveal it in the
  FileSystem dock; click the file → open the panel scene for tuning, via
  `EditorInterface`, editor-guarded) over a `%PanelHost` slot the panel is
  injected into. A concrete live tab is a one-node **inherited scene** of this
  base overriding only the four exports (see `tabs/18_fan_trace_tab.tscn`, the
  reference migration). Tree stays scenic (per `scene-composition.md`); the
  script only wires + acts, and the breadcrumb — being path-length-variable — is
  built into the scenic `%Breadcrumb` container in code.
  - **Backward-compatible:** a legacy bare-node tab (root = `MarginContainer` +
    this script, no chrome children) still works — the panel falls back onto
    `self` and every chrome hook null-guards to a no-op. The 9 un-migrated tabs
    run on this path; migrating each to the inherited base is mechanical work.
  - **Generator is now legacy-shaped.** `tools/gen_sandbox_tabs.gd` `_gen_live`
    still emits the *bare single-node* form (`SandboxLiveTab.new()` + save) — the
    original "generate to dodge uid landmines" approach, and the very reason tabs
    opened empty with no back-ref. Its roster covers spell/vfx/statboard/procgen +
    the played showcases; it does **not** include fan_trace/gimbal/node_visuals
    (hand-added later), so it won't clobber the migration. Update it to emit
    inherited scenes of the base (or retire it) as part of the migration.
- `sandbox_played_tab.gd` (`SandboxPlayedTab`) — a launch card (title +
  description + optional `preview: Texture2D` + ▶ Run → `play_custom_scene`).
  Played scenes are non-`@tool` and can't run in-editor, so the host never
  embeds them; the showcase *content* stays code-composed (its own docstring
  defends that), only the tab *wrapper* is a scene.
- `test/unit/test_sandbox_host_tabs.gd` — lints every tab scene: loads, root is
  a `SandboxTab`, all exports resolve non-null (the `godot-workflow.md` guard
  against a silently-nulled `@export`).

**Previews:** `EditorResourcePreviewGenerator` does NOT help the played tabs —
the showcases build their content in `_ready`, which doesn't run during preview
generation, so it would thumbnail an empty graph. A meaningful thumbnail must be
a captured screenshot wired into `SandboxPlayedTab.preview` (slot exists,
unpopulated for now).

**Migration is reversible.** The three old plugin folders are untouched; the
swap is one line in `project.godot`'s `[editor_plugins] enabled=` array (host in,
the three playgrounds out — `gut` + `procgen_preview` stay). Re-adding the three
entries restores the old bottom panels.

**Known pre-existing carry-over:** the spell tab spams *"Node not found:
Navigator/Entities/Nodes"* on load — `spell_playground/playground_panel.tscn`
hand-authors a partial bare `Graph` (the exact anti-pattern `scene-composition.md`
warns about) instead of instancing `graph.tscn`. The host only *surfaces* this
bug (it embeds the same panel); it doesn't cause it. Fixing the panel to build
its world via `graph.tscn` / `SandboxWorld` is its own cleanup.

## Mechanism notes (all verified Godot 4.x patterns)

- **Full-screen host:** `EditorPlugin._has_main_screen()` + `_make_visible()` —
  the mechanism 2D/3D/Script/AssetLib use.
- **Jump-to-tab:** `@export_tool_button` → `EditorInterface.set_main_screen_editor(<name>)`
  then select the tab.
- **Live Inspector sync:** `_edit()`/`_handles()` to receive the selected object +
  the resource's own `changed` signal (the project already leans on `@tool` +
  `emit_changed()` — `GlowStyle` is the template; see `skill-node-visuals.md`).
- **Auto-discovery:** `ProjectSettings.get_global_class_list()` exposes each
  script's `base`; filter for the tab base. Cheap, no scene loads.
- **Reset/mute for played tabs:** `AllocationVFX.muted` (added in phase 0) is the
  pattern — a played tab's silent SETUP beat replays the real primitives with
  cosmetics muted. Other VFX layers can grow the same switch as needed.

## Cross-refs

- `docs/domain/allocation-vfx.md` — the phase-0 showcase + the VFX it exercises.
- `.claude/rules/scene-composition.md` — when a scene vs code; why declarative
  wiring (the thing the naive extraction would break) is preferred.
- `.claude/rules/godot-workflow.md` — `@tool` injection-timing + don't refresh a
  user's open editor (relevant to phase 1 plugin enablement).
