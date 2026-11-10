Elements, child "terrain-ui": how terrain shows on the skill node. It covers the south-side capacity bars, the one label per element, the tooltip rows, the band glow, and the world-turn spread cue. Parent hub #1716; design home `docs/design/elements.md`. It is not on the spine's critical path. It blocks only #{forge-ui}, which keeps its look consistent with it.
Blocked by: #{terrain}, #{flow}
Blocks: #{forge-ui}

## Acceptance spec

**Decisions**
- *"neat UIs of "element capacity" in blocks e.g. when hovering nodes. Hover leaf node and see N*degree empty blocks for heat/cold and maybe sparkles inside for counting blips of Charge"* (owner, 2026-11-08). The settled pass proposal (`docs/design/elements.md:217-233`):
  - One block is `degree` stacks: 2 inert blocks, then 2(k − 1) primed blocks.
  - Heat and Cold share one bar, red or blue. Charge gets a second bar of the same shape, with sparkles.
  - The overflow is a few blocks past the frame that flicker and fade.
- *"since these are terrain properties, something tells me UI bars for these should be at the south side of the skillnode"* (owner, 2026-11-09; `:235-238`).
- *"show total with different name, and tooltip indeed"* (owner, 2026-11-09; `:239-243`). The label is one entry per element, updated in place: `Heat 6/6`, `Burning 7/6`, `Heat 5/6`. The tooltip gives the excess and the power it buys, never a second entry.
- Blaze and inferno are display names on the excess curve, not bands (settled doc text under the owner's 2026-11-09 bands call, `:836-840`; the ladder is the owner's 2026-11-06 *"ramping up fire der states to blaze to inferno"*, `:882`).
- The node announces a band crossing (`terrain_band_changed`), and the bar, the glow and the light listen to it (pass pick, tentative; `:842-848`).
- Visuals ride their mechanics unit; a large display surface is its own unit behind them (owner, 2026-11-10: *"option 1"*). This is that unit for child 2.

**Knobs** (tentative defaults, easy to change)
- `TerrainBars.block_size`, `gap`, `bar_height`, `south_offset` (px, drone's defaults). Editor feedback: setter redraw (`@tool`).
- `TerrainBars.max_overflow_blocks` = 3, `@export_range(0, 8, 1)`. The visual tail past the frame. Feedback: setter redraw.
- `TerrainBars.flicker_period` = 0.4 s. Feedback: sandbox tab.
- `NodeVisualsComposite.terrain_primed_tier` = `Emissive.Tier.VALUE` and `terrain_overflow_tier` = `Emissive.Tier.ALERT`. These are named tiers, never HDR floats (`docs/domain/hdr-color.md:61-74`), on the pattern of `channel_step_tier`. Feedback: setter re-applies.
- The excess display names (blaze above 2 × T, inferno at the overflow) are an ordered `(threshold as a multiple of T, name)` list on the Burning band. Pass pick, tentative. Empty on Frozen/Shocked, whose label is their band name.

**Composition**
- **Facts are read, never re-derived.** The counts, T, k, cap, band and excess come from #{terrain}'s accessors and band function on the node. The colour, icon and name come from the element's `Identity` and band `Identity` (#{defs}). Below the first band, the label is the terrain `StatusDef`'s name (Heat / Cold / Charge).
- **Change signal.** #{terrain} announces band crossings only. This unit adds a live-only `SkillNode.terrain_changed` at the same write door, fired whenever an int moves and never on a shadow (as `notify_statuses_changed` is), unless #{terrain} already ships one. It also adds a live-only `CombatWorld.terrain_settled(changed)`, emitted once per world turn from #{flow}'s pass with the changed set `TerrainSettle` already returns.
- **`TerrainBars`** (new `@tool` Node2D under `Visuals`, south of the node; the health bar sits north at `offset_top = -59`). It draws both bars and the label in `_draw`. It is shown while hovered or pinned (`pin_health_bar`, `skill_node.gd:278-283`), on owned and unowned nodes alike. It subscribes through `SubBag` while shown (`now()` for first paint, `clear()` on hide).
- **Glow.** `SkillNode` listens to `terrain_band_changed` and pushes a band glow into `NodeVisualsComposite` through a sibling of `set_status_tint`: the element colour at the band's tier. It composes with the status tint and never replaces it.
- **Tooltip.** `EffectReadoutPanel` gets a third sibling loop after its status rows (`effect_readout_panel.gd:12-17`): one row per nonzero element, showing the name, count/T, excess, the band's travel verb, and the power line from the band's `GoOff` when it is non-null. `has_content` counts these rows, so an unowned node with terrain shows the panel.
- **Spread cue.** On `terrain_settled`, every changed node briefly shows its bars (fade in, hold, fade out) when it is not hovered. That way the player sees where heat moved and what decayed this world turn. Charge decays in the same pass (owner, 2026-11-10), so a Charge-only node flashes too.
- **What dies:** nothing.

**Files touched**
- `skill_node/terrain_bars.gd` + `.tscn` (new), instanced in `skill_node/skill_node.tscn` under `Visuals`.
- `skill_node/skill_node.gd`: the `terrain_changed` signal, the bars onready, the glow push.
- `skill_node/visuals/node_visuals_composite.gd`: the two tier exports and the band-glow channel.
- `combat/combat_world.gd`: `terrain_settled` (shared with #{flow}'s code; this unit only adds the emit).
- `ui/tooltip_fan/panels/effect_readout_panel.gd`: the terrain loop.
- The Burning band `.tres` (#{defs}'s): the display-name list.
- `addons/sandbox_host/tabs/77_terrain_tab.tscn` + panel (new; copy a tab per `docs/domain/sandbox-framework.md:100-108`). It sets t / Charge on a small graph, steps a world turn, and pins bars.
- `docs/domain/skillnode-visuals.md`: a "Terrain bars" section.
- Tests: `test/unit/skill_node/test_terrain_bars.gd` (new), `test/unit/ui/test_effect_readout_terrain.gd` (new).

**Acceptance**
1. `test_terrain_bars.gd`, a pure layout function (count, degree, k) → blocks:
   - The frame is `2k` blocks, the first 2 inert.
   - Fill is `count / degree` blocks, so a leaf counts stacks exactly.
   - Overflow blocks are `ceil((count − kT) / degree)`, capped at `max_overflow_blocks`.
   - Sign picks red or blue.
   Assert ratios over a sweep, never the defaults.
2. `test_terrain_bars.gd`, label text across the bands:
   - Heat 6/6 on a degree-3 node reads `Heat 6/6`; at 7 it reads `Burning 7/6`; it uses the blaze/inferno names past their thresholds.
   - Cold past T reads `Frozen n/T`, and Charge past T reads `Shocked n/T`.
   - There is exactly one label per element.
3. `test_terrain_bars.gd`: the bars show on hover and pin on an unowned node. They hide on unhover. A shadow-world write emits no `terrain_changed`.
4. On a Frozen node holding Charge, both bars draw and the Charge count stays readable (asserted on the layout output). The *trapped* styling belongs to #{pairs}, which builds the trap.
5. `test_effect_readout_terrain.gd`: an unowned node with Heat past T has content. Its row shows the excess and the travel verb. With no `GoOff` on the band, the power line is absent, not "0".
6. A band crossing changes the composite's band-glow input to the element colour at the band's tier. Returning below T restores it, and an existing status tint survives both.
7. Exact behaviour, sandbox tab 77: stepping a world turn on a hot node makes its neighbours' bars flash. The overflow blocks visibly flicker and fade as the overflow decays.
8. `mise run check` is clean, and `test:dir` passes on `test/unit/skill_node/` and `test/unit/ui/`.

**NOTES**
- The look may be handed to a sub-agent working in this same worktree once the hook it draws from (signal, record field, scene stub) exists; the unit's drone stays the owner and reviewer of the result.
- The blade speed/drag cue in the child-2 audit moved to #{blade-elements}, which builds the sweep-speed curve.
- The Catalyst crystal layer under the bars is #{catalyst}'s.
- The Burning light source (vision) is #{fire}'s.
- The concrete power figures (disc radius, hops) arrive with #{burning} / #{lightning}'s `GoOff`s.
- Status icons stay rows. The terrain bars never join `StatusOverlay`.

**Stubs on master**: none. The shapes are named in Composition, and the drone adds them.

```drift-stamp bd800181
docs/design/elements.md:217-243 — the bar's shape, colours, overflow tail, south placement, one label per element
docs/design/elements.md:830-848 — bands on the def, display names, terrain_band_changed listeners
docs/design/elements.md:855-859 — the travel verbs the tooltip shows
docs/design/elements.md:880-884 — the owner's blaze/inferno ladder: Burning's power grows with the excess
docs/design/elements.md:79-113 — power = the excess; what the tooltip's power line means
skill_node/health_bar.gd:186-207 — the show/hide gate and SubBag binding to copy
skill_node/skill_node.gd:275-292 — pin_health_bar and the Visuals onreadies
skill_node/skill_node.gd:1565-1597 — notify_statuses_changed (live-only) and _sync_status_tint
skill_node/skill_node.tscn:81-127 — the Visuals children; the health bar sits north
skill_node/visuals/node_visuals_composite.gd:150-195 — channel_step_tier, the named-tier export pattern
ui/tooltip_fan/panels/effect_readout_panel.gd:1-27 — the sibling-loop rule for status rows
ui/tooltip_fan/panels/effect_readout_panel.gd:89-100 — bind and has_content
docs/domain/hdr-color.md:61-74 — named tiers, never floats
docs/domain/sandbox-framework.md:100-108 — adding a host tab
docs/domain/tunables.md:18-41 — knob DX: setter redraw, sandbox tab
skill_node/skill_node.gd — seam: signal, bars, glow push
skill_node/skill_node.tscn — seam: instances TerrainBars under Visuals
skill_node/visuals/node_visuals_composite.gd — seam: band-glow channel
ui/tooltip_fan/panels/effect_readout_panel.gd — seam: terrain rows
ui/status_overlay/status_overlay.gd — seam: stays rows only; untouched
combat/combat_world.gd — seam: terrain_settled emit
addons/sandbox_host/tabs/71_blast_tab.tscn — seam: the tab to copy
```
