# Architecture — the layer map

One page on which top-level module may depend on which. The **fact** — the
layer order, the reachable-from-all set, the permanent primitives and the
allowlist of today's exceptions — lives as data in
[`.mise/tasks/lint-module-deps`](../.mise/tasks/lint-module-deps), which
`mise run check` runs. This page is prose about that script; when they
disagree, the script wins and this page is stale.

## The layers, lowest first

| Tier | Modules | What lives there |
|---|---|---|
| **sim** | `archetypes stats_system graph skill_node entity effects combat attack systems` | the rules: topology, stats, nodes, entities, effects, combat math, attack plans/resolve, the gameplay systems |
| **spine** | `session procgen command network` | the run (`GameSession`'s data), the map generator, the single mutation path (`CommandApplier`), the wire |
| **shell** | `presentation ui scenes autoload settings` | drawing, HUD, composition roots, singletons, player settings |

`procgen` sits just above `session`: it may read sim and session.

## The direction

A module may reference **itself and anything below it** in that list. A
reference is a `class_name` token in code (comments and strings stripped) or a
`"res://…"` path (`preload`, `load`, bare). Granularity is the top-level
directory; `addons/ test/ tools/` are outside the map. Only `.gd` files are
scanned — scene and resource `ext_resource` paths (`.tscn`/`.tres`) are not.

Two standing exceptions, both permanent:

- **`autoload/` is reachable from everywhere** — it is the bus. Its *own*
  outgoing references are still checked like any other layer's.
- **`Emissive` (`ui/theme/emissive.gd`)** is a colour-tier primitive every layer
  may name (see `hdr-color.md`), not UI.

## The allowlist — today's debt, only shrinking

Every upward edge that existed when the check landed (2026-09-27, #1134) is
allowlisted verbatim, each with the issue that retires it or "no retiring
issue". `mise run lint-module-deps -- --explain skill_node→systems` prints one
entry; `-- --json` lists every file:line behind every edge.

- **A new upward edge fails `check`.** Invert it (inject, emit a signal, move
  the type down) before reaching for an allowlist line; adding one is an
  architectural call and names its retiring issue or why it is permanent.
- **A removed edge is a one-line delete** in the same landing as the refactor;
  the script warns on a stale entry.

Known shape of the debt, not fixed here: `graph→skill_node` and
`combat/effects→attack` are large because the sim order is aspirational in
places (the node is still the model, #1130; hit/damage instances live under
`attack/`). `attack/melee/skill_blade.gd` is view code inside a sim directory —
file granularity inside mixed directories is parked until #1130 makes the
directories honest.

## Forward fit — which seam each milestone stresses

- **MVP playable loop / Metagame (save baseline)** — spine: the join-time
  snapshots in `network/` are the save seed; a save format must not pull
  `network→` anything new.
- **AI v2** — sim↔scene: lookahead beyond combat needs a scene-free model;
  `entity→systems/scenes` edges are what it fights (#1131).
- **Procgen v3 / v5** — `procgen` reading only sim + session; the existing
  `procgen→scenes` edge is the one to retire, not extend.
- **Multiplayer** — spine DAG: `command→network`, `session→network/ui`,
  `systems→network` (#1133).
- **VFX & juice / SkillNode-visuals-v2** — sim→presentation: new visuals go in
  `presentation/`/`ui/`; `skill_node→ui` and `systems→ui` must not grow.
- **Content depth / Crits / Ranged2.0** — within sim: new spells and addons add
  `skill_node→attack` and `effects→attack` references; keep them downward by
  moving shared types down rather than widening the allowlist.
- **Cross-cutting / infra** — this check itself; CI (#433) would run it.
