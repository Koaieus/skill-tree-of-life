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
| **sim** | `identity settings archetypes stats_system skill_node graph entity effects combat attack aspects systems entity/controller` | the rules: identity, player settings the rules read, stats, nodes, topology, entities (the model), effects, combat math, attack plans/resolve, aspects, the gameplay systems, and the controllers that decide for an entity |
| **spine** | `session procgen command network` | the run (`GameSession`'s data), the map generator, the single mutation path (`CommandApplier`), the wire |
| **shell** | `presentation ui scenes autoload` | drawing, HUD, composition roots, singletons |

`procgen` sits just above `session`: it may read sim and session.
`entity/controller/` is its own module, ranked above `attack` and `systems`
because a controller drives both; the rest of `entity/` is the model.

## The direction

A module may reference **itself and anything below it** in that list. A
reference is a `class_name` token in code (comments and strings stripped) or a
`"res://…"` path (`preload`, `load`, bare). Granularity is the top-level
directory; `addons/ test/ tools/` are outside the map. Only `.gd` files are
scanned, and only under layered directories — scene/resource `ext_resource`
paths (`.tscn`/`.tres`) and every non-.gd directory are not.

Three standing exceptions, all permanent:

- **`autoload/` is reachable from everywhere** — it is the bus. Its *own*
  outgoing references are still checked like any other layer's.
- **`Emissive` (`ui/theme/emissive.gd`)** is a colour-tier primitive every layer
  may name (see `hdr-color.md`), not UI.
- **`attack` ↔ `combat` are declared peers** — both directions allowed. They
  share the hit vocabulary (`HitInstance`, `DamageInstance` under `attack/`;
  `EntityCombat`, `NodeCombat` under `combat/`): one layer split across two
  directories.

## The allowlist — today's debt, only shrinking

Every upward edge that existed when the check landed is allowlisted verbatim,
each with the issue that retires it or "no retiring issue" — none has a retiring
issue today. `mise run lint-module-deps -- --explain skill_node→systems` prints one
entry; `-- --json` lists every file:line behind every edge.

- **A new upward edge fails `check`.** Invert it (inject, emit a signal, move
  the type down) before reaching for an allowlist line; adding one is an
  architectural call and names its retiring issue or why it is permanent.
- **A removed edge is a one-line delete** in the same landing as the refactor;
  the script warns on a stale entry.

Known shape of the debt, not fixed here: `skill_node` still reaches up into
most of sim (the node is still the model); `attack→command` is codec types
(`WireFields`), not submission — moving `command` below `attack` was measured and
would swap that one line for three. `attack/melee/skill_blade.gd` is view code
inside a sim directory, and file granularity inside mixed directories is parked
until the directories are honest. The spine's own edges (`command→network`,
`session→network/ui`, `systems→network`) are done: none is allowlisted.

## Forward fit

Which seam a milestone stresses is read off the allowlist, not kept here:
`mise run lint-module-deps -- --explain <src>→<dst>` prints an edge and what
crosses it. The standing guidance: new visuals go in `presentation/`/`ui/` (the
`skill_node→ui` and `systems→ui` edges must not grow); new spells and addons keep
their references downward by moving shared types down rather than widening the
allowlist; a save format must not pull `network→` anything new; `procgen` reads
only sim and session.
