# Procgen sizing and playground

Poisson-disk sizing and the playground panel, moved out of source comments. The pipeline overview is procgen.md.

## Procgen playground panel (`procgen/playground/playground_panel.gd`)

Procgen playground panel (#166) — a live-edit sandbox tab for tuning what
procgen rolls, without booting a level.

Layout: a left sidebar (preset folder access + the sampling controls shared
by both sub-tabs) beside a `TabContainer` with "Map Sample" / "Node Graph".
The tree itself is fully authored in `playground_panel.tscn` (#264) — this
script resolves it via `%unique_name` and keeps only behaviour.

Sidebar:
- "Open Presets Folder" reveals `res://procgen/presets/` in the editor's
  FileSystem dock, creating the folder first if this is a fresh checkout.
- "Sample as:" (archetype) + "Reseed" are shared sampling state — both
  sub-tabs roll through the same `_rng` and `_sample_once`,
  so they belong here once, not duplicated per tab.

Inspector live-sync (#166): `load_config` (the `SandboxLiveTab`
loader hook) fires when a `GraphProcgenConfig` becomes the inspected
object — a fresh duplicate is taken as the working `_config` (never mutate
the on-disk resource) and `_source_config` remembers the *live* reference.
`refresh_from_config` is what the editor plugin calls on every
`property_edited` (including edits on nested sub-resources like
`budget_policy` or a `ScalarField` child) — it re-duplicates
`_source_config` and re-renders both sub-tabs in place: the map keeps its
clicked marker and re-samples at it, the graph keeps its node positions
(same seed) and just re-colours/re-samples. Tweaking a field preset in the
inspector is meant to feel instant, not like re-opening the tab.

Sub-tab "Map Sample": renders a `GraphProcgenConfig`'s budget-field heatmap
(`FieldMapView`); clicking a spot rolls a batch of independent draws there
(budget via `BudgetPolicy` + content via the phased v3 draw) and lays them
out as cards, so a designer gets an at-a-glance feel of what a node in that
territory tends to roll. Each card also shows the roll's factor breakdown
(raw draw + whichever multipliers departed from neutral) via
`_breakdown_text`. Hovering the map shows the field value + base
range at that point before you commit to a click.

Sub-tab "Node Graph": generates a small preview graph via `NodeGraphView` —
positions + edges + archetypes (coloured borders) but no content rolled.
A node here is a *location* to sample; clicking one runs the same
`_sample_once` roll a map click does. Node fill + the translucent
background layer both show the continuous `BudgetPolicy.budget_field` value.
Stamp simulation (#166): toggle "Paint Mode", pick an archetype + radius,
click a node to stamp — nodes inside the region get the stamp's archetype
colour; "Clear Stamps" restores the original BFS-grow assignments.

Self-contained: defaults to a duplicated `first_level.tres` so it works with
nothing inspected.

## Poisson-disk auto-scale sizing (`procgen/graph_procgen.gd`)

Poisson-disk auto-scale sizing (#164, retuned in #566). The disc area a
ShapeMask needs to hold `node_count` points at spacing `d = min_dist`.

This is ONE MEASURED NUMBER, not a derivation. It is the area per point
Bridson actually achieves inside a mask — measured as `π·(R/d)² / uncapped
fill`, 6 seeds per cell, and identical to three digits across d = 100 / 150
/ 250 (the whole pipeline is expressed in units of `min_dist`, so
`node_radius` and `node_padding` only zoom the board — retuning either
needs no change here):

    R/d     8.0    12.0    16.0    21.4    30.0
    n      ~130    ~292    ~519    ~928   ~1824
    area/pt 1.489  1.511   1.536   1.550   1.562

It drifts ~5% with n (a mask-clipped rim point spends less exclusion area
than an interior one, so more perimeter per unit area → a lower ratio).
1.60 sits just above that whole curve, which is the side to err on:
ABOVE means the disc outlasts the `max_points` cap and
`PoissonDiskSampler.sample` exits mid-flood, stranding the unplaced points
in one contiguous arc — the #566 ragged rim; BELOW means the level author
asks for `node_count` and silently gets fewer. At 1.60 the flood exhausts
exactly as it hits the cap: `placed == node_count` at every n from 150 to
3000 over 20 seeds, ring density within ±2% of uniform.


#163 (territory stamping) PREDICTS a stamp's node count from this ratio
rather than resampling locally, so don't retune without re-checking
test_procgen_sizing.gd.
