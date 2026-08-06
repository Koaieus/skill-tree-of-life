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

The old line was "allocation / battle / loot are non-`@tool` gameplay systems and
don't run live in-editor" — **stale since the systems went `@tool`** (Allocation,
Battle, Loot, Vision are all `@tool` now, #260 audited). The real kernel is
narrower and holds:

> **auto-tick = played; explicit-step = live.**

`@tool` gates exactly one thing: whether the engine auto-fires a script's
lifecycle callbacks (`_ready`/`_process`/`_input`) while `Engine.is_editor_hint()`.
It does **not** gate method dispatch — any method of any system is callable by a
`@tool` driver in-editor. So a surface is "played" only if it *auto-drives*
itself (a `_process` + `await create_timer` beat loop, the turn clock, AI); a
surface whose beats are explicit triggers (a button calling the real system
methods) runs live for free. The one thing we still deliberately do NOT want
ticking inside the editor: **`TurnManager` / AI**. Sandbox panels never
`start_turn` / `end_turn` / `tick` — loot attribution only *writes*
`turn_manager.current_entity` (a plain var) before a kill.

So the tab base must **declare its mode**:

- **live-edit tab** (`@tool`, runs in-editor): stat visualizer, VFX look, spell
  hops — and since #260 also the allocation / loot / death surfaces, which drive
  the real (already-`@tool`) systems from explicit **▶ Play beat** / **▶ Kill**
  buttons in a `SubViewport` world.
- **played tab** (launch card, runs on play): only for surfaces that genuinely
  need the runtime-only machinery to *auto-drive* — melee, ranged, full turn
  loops. No shipped tab uses played mode since #260; the class is kept for
  those.

"Don't promise live for everything" still holds — the line moved from "which
systems" to "who drives the clock".

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

The standalone sandboxes need *"a graph + a chosen subset of the real systems,
wired exactly as the game wires them, in one place."* That's a **`SandboxWorld`
composition helper** (code), not a scene extraction — each sandbox declares
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
| 2 ✅ | `SandboxWorld` subset-capable system composition (built once the 2nd consumer existed) | low | both live panels share it |
| 1 ✅ | Plugin host: main-screen `EditorPlugin` + `TabContainer`; `SandboxTab` base declares mode (live/played); explicit registration. The 3 playground plugins folded into one host (`addons/sandbox_host/`); showcases are played launch cards. | med | loads clean headless; **GUI behaviour pending human verify** |
| ✅ | Allocate + loot (and toast) played launch cards converted to **live tabs** — `@tool` panels embedding the real systems in a `SubViewport` world, driven by explicit ▶ Play beat / ▶ Kill buttons; the played showcase scenes deleted (standalone sandbox variants are "if-all-else-fails" surfaces, ideally zero of them). | low | shipped (#260) — the panels are `addons/allocation_sandbox/` + `addons/loot_sandbox/` |
| 3 | (partial — done) Inspector "Open in…" buttons now reveal the host main screen + select the tab (`set_main_screen_editor` + `current_tab`). (remaining) Jump-to-tab `@export_tool_button` on tab-able resource classes + finer live Inspector sync (`_edit`/`_handles` + resource `changed`). | low | button jumps; knob edits reflect w/o reload |
| 4 ✅ | Auto-discover tabs — **scene-directory scan**, NOT the `get_global_class_list` class scan the issue first sketched (see below: a dedicated `tabs/` dir is a cleaner declaration). Drop a `*.tscn` whose root is a `SandboxTab` in `addons/sandbox_host/tabs/`; the host loads + adds it, ordered by filename. | low | tabs appear without manual registration |

## The host (`addons/sandbox_host/`)

One main-screen `EditorPlugin` replacing the three bottom-panel playground
plugins. **Everything is scene-composed** (per `scene-composition.md`): the host
is a scene, and every tab is a scene whose root is a `SandboxTab`. Only
`sandbox_host.tscn` is *generated* by `tools/gen_sandbox_tabs.gd` (run headless)
— that dodges the uid-mismatch / field-strip landmines in `godot-workflow.md`;
tab scenes are hand-authored inherited scenes in every mode (see below).

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
  - **All live tabs are now migrated** (#250) and since #260 **every shipped
    tab is live**: spell / vfx / statboard / procgen / node_visuals / gimbal_3d /
    fan_trace / toasts / allocation / loot are each a one-node inherited scene of
    the base, so every live tab carries the breadcrumb chrome. The
    backward-compatibility path — a legacy bare-node tab (root = `MarginContainer`
    + this script, no chrome children) where the panel falls back onto `self` and
    every chrome hook null-guards to a no-op — still exists in the script as a
    safety net, but no shipped tab uses it.
  - **Generator no longer emits tabs** (#250 live tabs, #260 the last played
    cards). `tools/gen_sandbox_tabs.gd` now builds only the host scene. Tabs in
    every mode are hand-authored inherited scenes (an inherited scene can't be
    expressed via `PackedScene.pack`, and it hand-authors cleanly — path-resolved
    ext_resources, no uid landmines), and regenerating them would silently
    clobber hand-authored files (the 60_toast landmine this retired). To add a
    tab, copy an existing one under `addons/sandbox_host/tabs/` and swap the
    four exports.
- `sandbox_played_tab.gd` (`SandboxPlayedTab`) — a launch card (title +
  description + optional `preview: Texture2D` + ▶ Run → `play_custom_scene`).
  Played scenes can't run in-editor because they *auto-drive* (turn loop / AI /
  `await` beat cycle) — not because their systems are non-`@tool`, which they
  aren't anymore (see the modes section above). Kept for genuinely
  auto-driven surfaces (melee / ranged / full turn loops); **no shipped tab uses
  played mode since #260**. The showcase *content* stays code-composed (its own
  docstring defends that), only the tab *wrapper* is a scene.
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
- **Live-world panels:** a live tab hosting a 2D gameplay world wraps it in a
  `SubViewportContainer` + `SubViewport` (`stretch = true` → viewport pixels ARE
  panel pixels, no camera needed; lay the world out on `world.size_changed`).
  Reference: `addons/spell_playground/playground_panel.gd`, and the allocation /
  loot panels built on that pattern (#260).
- **Explicit-step live beats (#260):** a live panel must never auto-run its
  scenario — the "auto-tick = played" line. Beats are button-triggered (`▶ Play
  beat`, `▶ Kill victim`), gated while in flight (`_busy`), and labels refresh
  on demand instead of `_process` polling.
- **TurnManager in the editor:** never `start_turn` / `end_turn` / `tick` from a
  panel. Killer attribution is a plain write to `current_entity` (loot panel),
  and that slot must be cleared between kills (set to `null` on reset).
- **Reset/mute:** `AllocationVFX.muted` (added in phase 0) is the pattern — a
  panel's silent SETUP beat replays the real primitives with cosmetics muted.
  Other VFX layers can grow the same switch as needed.

## Cross-refs

- `docs/domain/allocation-vfx.md` — the phase-0 showcase + the VFX it exercises.
- `.claude/rules/scene-composition.md` — when a scene vs code; why declarative
  wiring (the thing the naive extraction would break) is preferred.
- `.claude/rules/godot-workflow.md` — `@tool` injection-timing + don't refresh a
  user's open editor (relevant to phase 1 plugin enablement).
