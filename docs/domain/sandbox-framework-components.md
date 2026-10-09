# Sandbox live-tab reusable components

Reusable pieces for `SandboxLiveTab` panels (`addons/sandbox_host/`). Tab/host
structure is in [sandbox-framework.md](sandbox-framework.md).

## The base chrome

Every live tab is a one-node inherited scene of `sandbox_live_tab.tscn`:

```
Layout(VBox)
├── Toolbar        (breadcrumb + reload)
└── Split (HSplitContainer)
    ├── Sidebar    (%Sidebar, VBox, visible = false by default)
    └── PanelHost  (%PanelHost)
```

The split lives in the **base**, not an inherited scene: `%PanelHost` is an
inherited node and an inherited scene cannot reparent it into a new split. A leaf
tab opts into the sidebar by flipping `%Sidebar.visible = true` (an always-legal
inherited-node override) and dropping a component in; collapsed, the tab is
single-column. The panel is baked as a scenic child of `%PanelHost` in each tab's
own `.tscn`, and `_mount_panel()` adopts it (no DI export). Swapping a tab's
panel for a WIP variant is one `instance=ExtResource(...)` edit on that node; there
is no in-tab switcher. Panels bundle their own controls, so the base has no
tab-level controls row.

## `DirectoryCardList`

`components/directory_card_list.{gd,tscn}` — a `@tool` `ScrollContainer` with no tab
knowledge. It scans `directory` (`@export_dir`; optionally `recursive`) for
`extensions` (suffix match, default `[".tres"]`) and renders one radio-toggle
`Button` card per entry (a `ButtonGroup`). It emits `selected(path)` and
`selected_resource(res)`; `entries()` lists the current paths and
`select_path(path)` presses one programmatically.

`SandboxLiveTab._wire_sidebar` connects `selected_resource` of any `%Sidebar` child
that has the signal to `load_object`, so a tab needs no wiring code. Consumers:
`tabs/12_spell_tab.tscn` (`res://attack/spell/defs`) and `tabs/35_procgen_tab.tscn`
(`res://procgen/presets`). Tested by `test/unit/test_directory_card_list.gd`.

## `SandboxTooltipFanMount` — the real hover tooltip in a tab's world

`addons/sandbox_host/components/tooltip_fan_mount.{gd,tscn}`. A tab whose world
is a graph in a SubViewport instances the mount in its panel scene, calls
`mount(<any node inside the world SubViewport>, graph)` once the world exists
(again after every rebuild — it retires the old fan), and
`attach_motion(<the SubViewportContainer>, <the panel's own hit-test>)`. The
hit-test is `func(local_pos: Vector2) -> SkillNode` (null = empty space), the
same one the tab already uses for clicks.

Three things differ from the HUD's fan, all set by the mount:

- **Screen-space layer.** The fan anchors at the node's canvas position, so it
  sits in a `CanvasLayer` inside the world viewport — the nodes' viewport, not
  their camera.
- **Driven, not subscribed.** `TooltipFan.listen_to_events = false`; the mount
  calls `show_for` / `hide_fan`. `Events.skill_node_hovered` is global, and
  every live tab shares the tree: a subscribed fan would pop in every tab.
  Editor-embedded tabs also never get `mouse_entered` (physics picking is off,
  and `SkillNode` only emits hover at runtime), so the motion hit-test is the
  only hover source anyway.
- **Gate open, units pinned.** `force_more_info` holds the Shift gate open (an
  editor tab has no key intent, and may not have the action in its InputMap);
  `unit_filter = pinned_units` (default `NodeStats` + `EffectReadout`) keeps the
  rest down across every live rebind. Roots (the mod-slab stack) always show.

The Status tab does NOT use it: it pins one node's fan open permanently
(`status_bench.gd`) rather than following the pointer.

Tested by `test/unit/test_tooltip_fan_mount.gd`; consumers are the arrow-gallery, spell-playground and melee-sandbox panels.
