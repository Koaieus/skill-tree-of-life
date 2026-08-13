# Codebase audit 2026-08-13 — shared brief

## Phase 0 baseline

- `mise run check`: **clean**, all scripts compile.
- Working tree at start: 4 modified files, all owner WIP on self-loops
  (`dev_sandbox.tscn` + `spell_playground/playground_panel.tscn` gained a self-loop
  Edge and a `self_loops` node_path; `reverberator.tres`/`bruiser.tres` are editor
  resave churn + one unused `rank_pass.gd` ext_resource added to bruiser).
- Dirty-tree suite: 1443/1449 pass, **6 failures** across 4 scripts:
  - `test/unit/spell/test_spell_defs.gd::test_reverberator_preset_well_formed`
    ("reverberator uses SUM merger", "ramps multiplicatively")
  - `test/unit/test_node_visuals_contract.gd` × 2 (fog composite instance state)
  - `test/unit/test_tooltip_v2_accessors.gd::test_spike_ring_keeps_its_authored_title_and_payload`
  - `test/unit/ui/test_fan_scene.gd::test_every_fan_traces_terminus_is_self_consistent`
    (FOCUS lane E item 7 already knows `test_fan_scene` is broken → #362)
- Pristine-HEAD baseline: see `pristine-test.log`.

## Phase 1 mechanical sweep (grep, whole first-party tree)

Clean — **zero** violations of:
- degree rule (`get_neighbours().size()`) — 0 hits anywhere, incl. tests
- PoolStat raw `base_value =` writes — 0 hits outside tests

Real hits:
1. **6 sandbox tabs still on the legacy `panel_scene` runtime-injection path**
   (`.claude/rules/sandbox-host.md` says this is wrong: tab previews empty, reload
   diverges from cold open). Offenders: `tabs/10_spell_tab.tscn`,
   `15_node_visuals_tab.tscn`, `30_statboard_tab.tscn`, `35_procgen_tab.tscn`,
   `50_loot_tab.tscn`, `60_toast_tab.tscn`. Only `70_bloom_tab.tscn` uses the
   blessed inherited-scene + `%PanelHost` form.
2. **Bare `Dictionary`/`Array` without type params** — ~220 occurrences:
   ui 40, procgen 38, attack 34, skill_node 28, tools 23, systems 21,
   stats_system 16, entity 12, scenes 5.
3. **Missing `-> ` return types**: attack 26, procgen 22, ui 9, skill_node 5,
   entity 5, autoload 4. Untyped `var` is rare everywhere (≤3/dir, except tools 11).
4. `set_shader_parameter` in per-node visuals (`skill_node/visuals/rim_ring.gd`,
   `inner_disk.gd`) — check against `.claude/rules/rendering-performance.md`
   (per-instance uniforms break batching at 500–2500 nodes).

## Owner-reported smells — auditors must address these explicitly

1. **Graph scene has both `Edges` (Node2D) and `EdgeMesh` (MultiMeshInstance2D).**
   Confirmed in `graph/graph.tscn`. Two parallel structures maintained. Is the
   split model-vs-renderer (defensible, badly named) or a half-finished migration?
   Consumers: `graph/graph.gd`, `graph/edge.gd`, `ui/fog_overlay/fog_overlay.gd`,
   `test/unit/test_edge_mesh_render.gd`, `test/unit/test_edge_z_order.gd`.
2. **Self-loops don't render like regular edges** — they lack the emissive glow
   normal edges get. Suspicion: self-loops are drawn on a different path that
   never joined the multimesh / HDR-emissive path.
3. **Adding a self-loop in the spell playground made all other edges vanish.**
   Suspicion: zero-length edge poisons a multimesh buffer rebuild / instance count.
   Also check whether that tab's graph is genuinely pre-authored or rebuilt at
   runtime (it IS a legacy `panel_scene` tab — see hit #1 above).
4. **HDR/emissive bloom is under-applied.** Real glow now exists
   (`.claude/rules/hdr-color.md`, `ui/theme/emissive.gd`, 63 `Emissive.` call
   sites / 20 files) but places that *fake* glow predate it and were never
   migrated — notably the segmented gauge UI (`ui/gauges/pool_gauge.gd`,
   `composite_bar_gauge.gd`, `capacity_pip.gd`). Flag every faked/absent glow.

## Going-in hypotheses (don't re-derive; verify or refute)

- `skill_node/skill_node.gd` — 1608 lines, 34 commits in 3 weeks. God object.
- `attack/` — 80 files for 4.6k LOC (~57 lines/file). Over-fragmentation /
  indirection. Same shape suspected in `ui/` (123 files).
- First-party TODOs are prior agents flagging their own shortcuts — treat as
  pre-filed findings: `ui/vfx/coordinator/magic_bounce_coordinator.gd` ("think
  through a class decomposition instead of `waves, beats, pending`"),
  `effects/effect_context.gd` ("carefully review all these splits"),
  `attack/outcome/healing_instance.gd` (shared parent with `DamageInstance`),
  `attack/outcome/propagation_event.gd` (two vars → one typed to parent),
  `ui/hud/combat_readout/combat_card_magic.gd` + `combat_card_defense.gd`
  (inherited-scene refactor left half-done; `combat_card_melee.gd` reproduces
  stale innate-modifier logic), `ui/tooltip_fan/fan_live_sandbox.gd` (untyped
  dicts, `Entity.new()` instead of scene instantiate),
  `attack/spell/on_hit/healing_effect.gd` (nothing consumes it),
  `ui/announcement_layer/callout_band.gd` (hardcoded style colors).

## MANDATORY report contract (every auditor)

You are **read-only**. Make ZERO edits to the repo. Your only write is your report
file. Do not run `mise run test`, do not run the game, do not commit.

Before auditing, read: `/home/bramh/skill-tree-of-life/CLAUDE.md`, this brief, and
every `/home/bramh/skill-tree-of-life/.claude/rules/*.md` whose `paths:` frontmatter
covers your files. Several rules are one-line "breadcrules" pointing at
`docs/domain/<topic>.md` — follow the pointer when it bears on your slice.

Read every `.gd` in your scope **in full**, plus the `.tscn`/`.tres` that compose
them. Read outside your scope only to understand a dependency.

What counts as a finding, small to large:
- **NIT** — bad function split, dead code, duplicated logic, untyped `var`, missing
  `-> ` return type, bare `Dictionary`/`Array` where a typed collection belongs,
  magic numbers, stale/lying comments and names.
- **MEDIUM** — wrong seam between two classes, logic in the wrong layer, a scene
  that should be an inherited scene, a code-composed `X.new()`+`add_child` tree that
  should be a `.tscn` instance, DI via `get_node` instead of exported NodePaths,
  per-frame work that should be cached, a rule-file violation.
- **LARGE** — wrong modelling of the domain, god object or the opposite (indirection
  with no payoff), a half-finished migration leaving two parallel mechanisms, an
  abstraction that no longer matches what the game actually does.

Report shape — obey exactly:

```
### <N>. SEVERITY | path/file.gd:LINE | <=10-word title
**Defect:** one sentence.
**Breaks:** one sentence naming what is wrong today, or what future change this makes harder.
**Fix:** one sentence.
```

- Max **25** findings, ranked most-severe first. 15 sharp findings beat 25 padded ones.
- **Quality filter:** drop any finding whose only justification is style preference.
  Every finding must name a concrete consequence.
- No code blocks longer than 3 lines.
- End with `## Verdict` — max 5 sentences on whether this slice is well-modelled.

## Excluded from all audits

`addons/gut/`, `addons/godot-neovim/` (vendored), `.worktrees/`, and the
scratchpad `pristine/` worktree.
