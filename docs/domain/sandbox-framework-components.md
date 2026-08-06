# Sandbox live-tab reusable components (proposal — #252 / #253 / #254)

> **Status: PROPOSAL, pending approval.** Design pass for the reusable-component
> layer #249 called out. Not yet built. Supersedes nothing until approved.

## The shape of the problem (grounded, not guessed)

After #250 every live tab is a one-node inherited scene of `sandbox_live_tab.tscn`
(toolbar breadcrumb + reload over a `%PanelHost` slot). Two patterns recur across
the embedded panels, and they want *different* reuse:

1. **Directory browsers.** A handful of surfaces want to pick one entry from a
   folder of resources/scenes and preview it (presets, spell defs, procgen
   configs). Today each re-invents the list. → **#253**
2. **"The dedicated <aspect> scene."** Most live panels *are* a single authored
   scene the tab embeds and you tune by hand (tooltip_fan, node_visuals, gimbal).
   The friction is: (a) the tab previews empty in-editor because the panel is
   injected at `_ready`, and (b) there's no in-tab way to swap the main scene for
   an in-progress **v2** while keeping the main one on screen for comparison.
   → **#254** (+ the v2-switch idea)

**Load-bearing finding:** the panels **bundle their own controls** (tooltip_fan's
control column lives *inside* `fan_live_panel.tscn`; node_visuals is a
self-contained `Control`). So a tab-level *controls row* is redundant for today's
panels — the layout variants of #252 only earn their keep when they host a **new**
tab-level affordance (the #253 card list, the #254 switcher, a Reset). We should
**not** build speculative control-row layouts no panel will fill.

## The component set (compose, don't pre-render a tower)

Per the brief — *"provide basics and compose the rest from reusable elements…
self-wire to the tab best they can."* Three reusable **element** scenes + one
**scaffold** layout, not a deep inheritance tree:

### A. `DirectoryCardList` — reusable element (#253)

A composable `Control` (ScrollContainer → VBox), no tab knowledge:

- `@export var directory: String` — folder to scan.
- `@export var extensions: PackedStringArray` — e.g. `[".tres"]`, `[".tscn"]`.
- `@export var card_scene: PackedScene = null` — optional custom card; a plain
  default (name label + optional thumbnail) when null.
- Renders one card per entry as a **radio group** (single selection via
  `ButtonGroup`).
- Emits `selected(path: String)` and `selected_resource(res: Resource)`.
- `@tool` so the card list populates in-editor from the exported directory.

A tab wires it in one line: `card_list.selected_resource.connect(tab.load_object)`
— or the scaffold self-wires it (below).

### B. In-place panel baking (#254)

Resolve the two `sandbox_live_tab.gd` TODOs. **Decision to pin (recommended):**
author the default panel as a **scenic child of `%PanelHost`** in each tab (so the
tab previews non-empty at edit time), and keep `panel_scene` DI **only** as the
reload/rebuild source. The base's `_instantiate_panel` becomes: *if `%PanelHost`
already has an authored child, adopt it; else instance `panel_scene`* — so both
the scenic child and the reload path coexist without double-instancing.

### C. `SceneSwitcher` — reusable element (#254, the v2 idea)

An optional toolbar dropdown: `@export var variants: Array[PackedScene]` (main +
v2…). Swaps the embedded scene at runtime while the **main stays authored
in-scene** for editor scenic feedback. Off by default (single-scene tabs ignore
it). This is the "little DX for our DX" — comparing a shipping look against a WIP
one without leaving the tab.

### D. A `%Sidebar` slot in the **base**, not a scaffold layer (#252)

**Revised after review.** The tempting shape — a `live_tab_sidebar.tscn`
*inherited* scene that adds an `HSplitContainer` beside `%PanelHost` — is
impossible: `%PanelHost` is an inherited node, and an inherited scene **cannot
reparent it** into a new split. It would render as PanelHost still stacked
vertically with an empty split dangling below.

So the split goes into the **base** itself:

```
Layout(VBox)
├── Toolbar        (breadcrumb + reload + optional SceneSwitcher)
└── HSplit
    ├── Sidebar    (VBox, %Sidebar, visible = false by default)
    └── PanelHost  (%PanelHost)
```

Now #252's "variants" are **not** a scaffold-inheritance tower — they're one
property override on an inherited node: a leaf tab flips `%Sidebar.visible = true`
(always-legal inherited-node override) and drops a `DirectoryCardList` in. Today's
tabs leave it collapsed → pixel-identical to now. This deletes the whole scaffold
layer the first draft proposed.

> Verify empirically when building that a collapsed `HSplit` child leaves the
> single-column look unchanged (drag handle hidden when a side is `visible=false`).

**Deferred (YAGNI until a tab needs it):** two-column-for-controls and runtime
toggle-ordering from #252 — no current panel exposes tab-level controls to
arrange, so building them now is speculative. Revisit when a panel externalizes
its controls.

## Swarm decomposition (the payoff)

**All base edits are the orchestrator's, done before dispatch — not a worker
unit.** The adopt-or-instance panel change, the `%Sidebar`/`HSplit` restructure,
the `DirectoryCardList` self-wire, and the toolbar `SceneSwitcher` hook **all**
touch `sandbox_live_tab.gd` / `sandbox_live_tab.tscn`. If four workers each edited
the base they'd contend one file — the leaked-decomposition trap. So the base
lands as **one orchestrator commit** first; workers then own strictly disjoint
*new* files:

- **Orchestrator prerequisite (before dispatch):** every `sandbox_live_tab.gd`/
  `.tscn` change — adopt-or-instance, `%Sidebar` split, self-wire hook, switcher
  mount point.
- **Unit 1:** `DirectoryCardList` element scene + script + lint test. New files only.
- **Unit 2:** `SceneSwitcher` element scene + script + lint test. New files only.
- **Unit 3:** optional default card scene for `DirectoryCardList`. New files only.
- **Per-tab adoption:** one unit per opting-in tab, each owning only its own
  `tabs/NN_*.tscn` — bake the panel in-place / flip `%Sidebar` / mount a card list.

#251 (live-sync on source-file change) stays a **separate spike** — an open
`EditorInterface`/scene-reload research question, not mechanical.

## Pinned decisions (consumers named)

`DirectoryCardList` has **real consumers this round**, so it's not speculative:

- **Procgen tab** — a sidebar of procgen config `.tres` → `load_config`.
- **Spell tab** — a sidebar of spell `.tres` → `load_spell` (today reachable only
  via the Inspector "Open in…" route).
- **StatBoard tab** — a scrollable sidebar of stat `.tres`.

`SceneSwitcher` is **deferred (YAGNI).** No v2 scene is queued. Its motivating
concern — *not hard-coupling the tab to a single scene, so trying a v2 later
doesn't mean diving into the tab's internals* — is already satisfied by #254's
design keeping `panel_scene` (a plain `@export`) as the swap point. Swapping a
scene = change one exported reference, no internals. So no switcher UI is built
now; the decoupling is structural, not a feature.

## Adjacent threads surfaced — tracked, NOT in this swarm

- **Core Classes authoring tab** (new): tune/author `CoreClass` designs live — a
  small graph of nodes + a core node, previewing an Effect's proximity-based
  buffs/nerfs to owned (and occasionally unowned) nodes by hop / euclidean
  distance. This is a **real feature**, not a mechanical drop-in — it needs its
  own design + issue, and would *consume* the sidebar + `DirectoryCardList` once
  they exist. File it under #249; don't swarm it as boilerplate.
- **AllocationVFX / Loot played tabs are externally-launched** (`SandboxPlayedTab`
  → `play_custom_scene`) with thin scenic backing. `sandbox-framework.md` defends
  this deliberately (they drive non-`@tool` gameplay systems that can't tick
  in-editor). Revisiting whether they *can* get real in-editor scenic backing is a
  design question against that rationale — a separate discussion, not this swarm.
