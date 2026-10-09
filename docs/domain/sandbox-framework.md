# Unified sandbox framework

Status: **built** — one main-screen host with a live tab per module. Phase 3
(jump-to-tab buttons on tab-able classes, finer live Inspector sync) is partly
open. This doc is the source of truth for *why the obvious first step is a trap*
and what to do instead — read it before touching `game_root.tscn` for
"anti-drift" reasons.

## The goal

Module-testing surfaces each re-derived graph + nodes + edges + entities +
systems their own way, so they drifted from real gameplay. **If a sandbox
mismatches the game, it's not proving anything.** One full-screen editor host
with tabs; every tab drives the real systems.

| Surface | Home | Mode |
|---|---|---|
| Spell cast / hop tuning | `addons/spell_playground/` via `tabs/12_spell_tab.tscn` | live-edit |
| VFX / projectile launcher | `addons/vfx_playground/` via `tabs/20_vfx_tab.tscn` | live-edit |
| Stat-board visualizer | `addons/stat_board_visualizer/` via `tabs/30_statboard_tab.tscn` | live-edit |
| Allocation / dealloc / death VFX | `tabs/40_allocation_tab.tscn` | live-edit |
| Loot | `tabs/50_loot_tab.tscn` | live-edit |
| Melee blade | `addons/melee_sandbox/` via `tabs/10_melee_tab.tscn` | live-edit |
| Status effects (one-node bench: apply / tick / log) | `addons/status_sandbox/` via `tabs/55_status_tab.tscn` | live-edit |
| Ranged — arrow looks (every `ammo_type_roster.tres` type, volley 1–20, board presets, fired through `BattleSystem.launch_attack` on a fresh `SandboxWorld` board per fire) | `addons/arrow_gallery/` via `tabs/11_ranged_tab.tscn`; `20_vfx_tab`'s primitive gallery stays the spell-coordinator parts catalogue and `75_outcome_tab` the recorded-replay proof for spells | live-edit |
| Ranged — played turn flow | — (none yet) | played |

## The load-bearing distinction: two execution modes

Allocation, Battle, Loot and Vision are all `@tool`, so the systems run in-editor.
The kernel:

> **auto-tick = played; explicit-step = live.**

`@tool` gates exactly one thing: whether the engine auto-fires a script's
lifecycle callbacks (`_ready`/`_process`/`_input`) while `Engine.is_editor_hint()`.
It does **not** gate method dispatch — any method of any system is callable by a
`@tool` driver in-editor. So a surface is "played" only if it *auto-drives*
itself (a `_process` + `await create_timer` beat loop, the turn clock, AI); a
surface whose beats are explicit triggers (a button calling the real system
methods) runs live for free. The one thing we still deliberately do NOT want
ticking inside the editor: **`TurnManager` / AI**. Sandbox panels never
`start_turn` / `end_turn` / `tick` — loot attribution only *adopts* the
cursor (`turn_manager.adopt_turn(killer, tm.turns_taken)`, silent) before a kill.


So the tab base **declares its mode**:

- **live-edit tab** (`@tool`, runs in-editor): every shipped tab. Surfaces drive the
  real systems from explicit **▶ Play beat** / **▶ Kill** buttons in a
  `SubViewport` world.
- **played tab** (launch card, runs on play): only for a surface that genuinely
  *auto-drives* (full turn loops). No shipped tab uses it; the class is kept for
  that case. When a surface is *mostly* explicit-step with one auto-driven part
  (melee's `MeleePreview` idle ghost loop), gate that part on tab focus rather than
  demoting the whole surface to played.

The line is "who drives the clock", not "which systems".

## Why the naive `systems.tscn` extraction is a trap

Extracting `GameRoot`'s `Systems` subtree into a reusable `systems.tscn` for
anti-drift is the wrong abstraction:

1. **Level scenes already inherit `game_root.tscn`** (`dev_sandbox`, `level`,
   `procgen_play_sandbox`; `first_level_sandbox` inherits `level`), so there is no
   drift between the real levels. The drift victims are the standalone playgrounds.
2. **Standalone playgrounds want a *subset*.** The allocation showcase omits
   `TurnManager`, `VisionSystem` (fog would hide its nodes), `UIRoot`, input and
   `LootSystem` (would mutate the dead core); a monolithic bundle forces systems
   that actively misbehave.
3. **`%` unique names don't cross an instance boundary** — `GameRoot` reads
   `%AllocationSystem` and `procgen_play_sandbox` reads `%VisionSystem`; extraction
   forces an accessor rewrite.
4. **Inherited scenes override `Systems` children by path** (`dev_sandbox.tscn`
   sets `Systems/PlayerInputController.player` and `Systems/VisionSystem.viewers`
   declaratively, per `scene-composition.md`). Moving `Systems` into a sub-scene
   breaks them in a way unit tests won't catch.

## What anti-drift needs: a subset-capable, code-level scaffold

`scenes/dev/sandbox_world.gd` is a `class_name`-less duck-typed helper:
`build(graph, opts)` instantiates and wires the requested subset of systems with
`GameRoot._ready`'s exact calls and exposes them as properties (allocation: the
default core; loot: `{loot = true}` adds TurnManager + LootSystem).

It is a parallel wiring source, not GameRoot's: it mirrors `game_root.tscn`'s
wiring and must be **kept in sync** if a system gains a required dependency. If
the two ever need one source, extract a `wire_systems(graph)` *helper function*
both call — not a scene.

## Remaining work

- Jump-to-tab `@export_tool_button` on tab-able resource classes (Inspector
  "Open in…" buttons already reveal the host main screen and select the tab via
  `set_main_screen_editor` + `current_tab`).
- Finer live Inspector sync (`_edit`/`_handles` + the resource's `changed`).

## The host (`addons/sandbox_host/`)

One main-screen `EditorPlugin` (enabled in `project.godot`'s `[editor_plugins]`
alongside `gut` and `procgen_preview`). **Everything is scene-composed** (per
`scene-composition.md`): the host is a scene, every tab a scene rooted on a
`SandboxTab`. Only `sandbox_host.tscn` is *generated*, by
`tools/gen_sandbox_tabs.gd` (run headless); tab scenes are hand-authored
inherited scenes — to add one, copy an existing file under
`addons/sandbox_host/tabs/` and swap `tab_title` / `tab_id` / `loader_method`.

Files:

- `plugin.gd` — the `EditorPlugin`. `_has_main_screen() → true`; instances
  `sandbox_host.tscn` into `EditorInterface.get_editor_main_screen()` (a
  `VBoxContainer` — the host needs `SIZE_EXPAND_FILL` or it renders collapsed) and
  shows/hides it on `_make_visible`. It registers the playgrounds' own
  `EditorInspectorPlugin` scripts and routes their signals → load the resource into
  the matching tab (by `tab_id`) + `set_main_screen_editor` + select the tab, so the
  "Open in…" buttons and the spell auto-sync target the host. Icon: `icon.svg`.
- `sandbox_host.tscn` / `.gd` (`class_name SandboxHost`) — a `Control` + a
  `Tabs` `TabContainer`. **Auto-discovers tabs** with a `DirAccess` scan of
  `tabs/*.tscn`: loads each, asserts the root is a `SandboxTab`, adds it, titles
  it from `get_tab_title()`. Numeric filename prefixes (`10_…`, `20_…`) fix tab
  order. `reload_tab()` rebuilds the **whole tab** from its `.tscn`, so reload and
  cold open take the same path.
- `sandbox_tab.gd` (`class_name SandboxTab`) — the mode-declaring base
  (`Mode {LIVE_EDIT, PLAYED}`); `is SandboxTab` is the runtime guard on discovery.
- **Bake the panel into the tab scene.** A tab instances its panel scene inside its
  own `.tscn` under `%PanelHost`, and `_mount_panel()` adopts that child — the tab
  previews non-empty in the editor and reload takes the cold-open path. Every tab
  is baked; `70_bloom_tab.tscn` is the reference. Baking is not a glow fix
  (`docs/domain/hdr-color.md`, failure mode 5).
- `sandbox_live_tab.gd` (`SandboxLiveTab`) + `sandbox_live_tab.tscn` (the **scenic
  base**) — embeds an `@tool` panel under `%PanelHost`; forwards the inspected
  resource to its `loader_method` by name; `tab_id` is the host's routing key. The
  base `.tscn` carries the shared chrome: a toolbar with a **source-path
  breadcrumb** (click a folder → reveal it in the FileSystem dock; click the file
  → open the panel scene, editor-guarded) over `%PanelHost`. A concrete live tab
  is a one-node **inherited scene** of the base overriding only `tab_title` /
  `tab_id` / `loader_method` (reference: `tabs/18_tooltip_fan_tab.tscn`). Every
  tab under `tabs/` is such a scene. The breadcrumb, being path-length-variable,
  is built into the scenic `%Breadcrumb` container in code. Shared pieces for tab
  panels live in `components/` — see `sandbox-framework-components.md`.
- `sandbox_played_tab.gd` (`SandboxPlayedTab`) — a launch card (title +
  description + optional `preview: Texture2D` + ▶ Run → `play_custom_scene`) for
  surfaces that auto-drive. `EditorResourcePreviewGenerator` does not help it (the
  content builds in `_ready`, which doesn't run for previews); a thumbnail must be
  a captured screenshot wired into `preview`.
- `test/unit/test_sandbox_host_tabs.gd` — lints every tab scene: loads, root is a
  `SandboxTab`, all exports resolve non-null (the `godot-workflow.md` guard against
  a silently-nulled `@export`).

**Authored edges render for free.** A `@tool` panel hosting a `Graph` (via
`graph.tscn` or `SandboxWorld`) gets its `.tscn`-authored `Edge`s wired into the
shared `edge_mesh` MultiMesh automatically: `Graph._ready` calls
`_backfill_edge_render()` above the `Engine.is_editor_hint()` guard. A panel hosts
`graph.tscn`, never a hand-authored partial `Graph` (`scene-composition.md`).

## Mechanism notes (all verified Godot 4.x patterns)

- **Full-screen host:** `EditorPlugin._has_main_screen()` + `_make_visible()` —
  the mechanism 2D/3D/Script/AssetLib use.
- **Jump-to-tab:** `@export_tool_button` → `EditorInterface.set_main_screen_editor(<name>)`
  then select the tab.
- **Live Inspector sync:** `_edit()`/`_handles()` to receive the selected object +
  the resource's own `changed` signal (the project already leans on `@tool` +
  `emit_changed()` — `GlowStyle` is the template; see `docs/domain/skillnode-visuals.md`).
- **Live-world panels:** a live tab hosting a 2D gameplay world wraps it in a
  `SubViewportContainer` + `SubViewport` (`stretch = true` → viewport pixels ARE
  panel pixels, no camera needed; lay the world out on `world.size_changed`).
  Reference: `addons/spell_playground/playground_panel.gd`, and the allocation /
  loot panels.
- **Explicit-step live beats:** a live panel never auto-runs its scenario. Beats are
  button-triggered (`▶ Play beat`, `▶ Kill victim`), gated while in flight (`_busy`),
  and labels refresh on demand instead of `_process` polling.
- **TurnManager in the editor:** a panel never *auto-drives* the clock — no
  `_process`, timer or `await` loop may call `start_turn` / `end_turn` / `tick`.
  A single button-bound step is explicit-step and allowed: the Status tab's
  ▶ Tick turn calls `end_turn()` once per click, which with a lone entity rolls
  synchronously into that entity's next `start_turn`. The host instantiates every
  live tab into one tree, so the bench's TurnManager is scoped (`entity_root` = its
  Graph) or an unscoped tick serves another tab's entity. An entity never binds to
  a TurnManager — it is served only by the manager that calls `begin_turn` on it.
  Build that TurnManager with `TurnManager.new()` from `@tool` code (hand it to
  `sandbox_world.build` as `adopt_turn_manager`) — `turn_manager.gd` is not `@tool`,
  so one authored in a `.tscn` is a placeholder in the editor. Killer attribution
  without a turn is `adopt_turn(killer, tm.turns_taken)` (loot panel), cleared
  between kills (`adopt_turn(null, …)`).
- **Reset/mute:** `AllocationVFX.muted` is the pattern — a panel's silent SETUP beat
  replays the real primitives with cosmetics muted.

## `Engine.is_editor_hint()` is TRUE inside a live tab — and no test can see it

A live tab instantiates **runtime, non-`@tool` scripts from tool code**
(`sandbox_world.gd` does `PlayerInputController.new()`). Godot runs those scripts
normally, but with the editor hint set. So any `_ready` that opens with

```gdscript
if Engine.is_editor_hint():
    return
```

is **silently half-built in every live tab**: the object answers method calls
(clicks route, plans build) while every signal subscription below the guard is
absent. It reads as "feature X just doesn't work in the sandbox", with no error
(the melee tab's reform slot was dead this way: written from `attack_launched`,
subscribed below the guard).

**GUT cannot catch this.** The suite is headless, `is_editor_hint()` is false, the
guard never fires, and the test passes for the wrong reason; the durable protection
is the shape of the guard. `mise run lint-editor-hint-guard`
(`.mise/tasks/lint-editor-hint-guard`, wired into `mise run check`) greps every
tracked `@tool` script for `if Engine.is_editor_hint():` as the first statement of
`_ready()` whose entire body is a bare `return`, and fails outside its allowlist. A
narrow guard — one that does work before returning, or isn't the function's first
statement — is untouched. The allowlist entries in that file record the judgement
calls that are correct to keep.

**How to apply:**

- Never guard a whole `_ready` on the editor hint. Guard the individual things
  that reach for **the OS or the edited scene** — `_unhandled_input`, a
  `Input.set_default_cursor_shape` call, a subscription to a node's own physics
  pick — at their own call sites, with a comment saying which.
- The one thing a live tab genuinely must NOT wire is **physics picking**: the
  panel hand-routes clicks (`route_left_click`) because picking through an
  editor-hosted SubViewport is unreliable, and wiring both double-routes whichever
  pick does land.
- When a tab "does nothing", diff what its systems subscribe to against an
  editor-hint grep of those scripts before suspecting the panel.
- The hint also turns on the engine's **editor debug overlays**: a
  `VisibleOnScreenNotifier2D` paints its rect in translucent magenta, a
  `CollisionShape2D` its shape, a `Camera2D` its limits — inside a live tab
  exactly as in the 2D editor. Any such node created in code as an internal
  mechanism (the halo on-screen gate) must switch its overlay off
  (`show_rect = false`). Don't reach for an alpha-0 modulate instead — the
  canvas cull pass returns on alpha before it evaluates the visibility
  notifier, so the overlay would vanish along with the gate it exists for.

## Cross-refs

- `docs/domain/allocation-vfx.md` — the allocation showcase + the VFX it exercises.
- `.claude/rules/scene-composition.md` — when a scene vs code; why declarative
  wiring (the thing the naive extraction would break) is preferred.
- `.claude/rules/godot-workflow.md` — `@tool` injection-timing + don't refresh a
  user's open editor.
