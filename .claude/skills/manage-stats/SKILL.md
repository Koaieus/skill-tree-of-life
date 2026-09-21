---
name: manage-stats
description: Add a stat (scalar or pool), a modifier, or a derived scaling rule to the stat system. Use when the user asks to add a new stat, add a modifier to a stat, wire a derived relationship between stats ("PER scales vision_range"), or place a modifier in the right layer. This is the checklist — each step names the file it lands in and the test that catches skipping it.
---

# Manage Stats — the checklist

This skill is **process, not catalogue**. Read `.claude/rules/stats-system.md`
first: it is the authoritative reference for the pipeline, the board
classes, pool behaviour, intrinsics and the current stat IDs, and it is what
every step below points at instead of restating. If your change alters the
*system* (pipeline, display contract, pool semantics), update that rule; this
file changes only when the *procedure* changes.

## Checklist: scalar stat

Each step: the file the artefact lands in → what catches forgetting it.

1. **Definition.** A `StatDef` `.tres` in `stats_system/defs/<id>.tres`
   (copy a neighbour, e.g. `stats_system/defs/armor.tres`; no hand-written
   `uid=` is needed). `id` is the file stem.
   → caught by nothing on its own; the next step's test fails if the file
   exists and is not rostered.
2. **Roster.** Append it to `stats_system/stat_def_roster.tres` (`defs`
   array; see `stats_system/stat_def_roster.gd` for why it is an authored
   array and not a directory scan).
   → `test/unit/test_stat_def_roster.gd` — `test_roster_lists_every_authored_def`
   red on omission, `test_every_rostered_def_has_a_unique_id` on an id clash.
3. **Typed field.** `@export var <id>: ScalarStat` on `EntityStatBoard`
   in `stats_system/entity_stat_board.gd`, under the right
   `@export_group`; the property name must equal the def `id` exactly
   (`get_stat(id)` is `Object.get(id)`).
   → `mise run check`; a name/id mismatch surfaces as "unknown stat id"
   in the first test that touches it — there is no dedicated pin.
4. **Instance.** A `ScalarStat` sub-resource wired to the def on
   `entity/default_entity_board.tres`, the live board every entity boots
   from (copy the pattern of any existing scalar in that file).
   → **unpinned.** No test asserts every board field has an instance; a
   null scalar silently falls back to the def default. Check it by hand.
5. **No scene copies.** There are none to update: every scene points at
   `entity/default_entity_board.tres` as an `ExtResource`. **A
   scene-specific value is a modifier granted in that scene's script, never
   a forked board** — `scenes/dev_sandbox.gd:_setup_level` is the worked
   example (`grant_core_modifier` on `blade_size`); the rule is
   `.claude/rules/godot-scene-authoring.md` → "a board is an ExtResource,
   a deviation is a modifier on top".
   → `test/integration/test_authored_entity_boards.gd` —
   `test_no_scene_carries_an_inline_entity_board`.
6. **Value type.** Pick `StatDef.value_type` deliberately; `BOOL` is
   presence, not magnitude (`stats-system.md` → `StatDef.ValueType.BOOL`).
   Say nothing about rounding: the rule owns coercion semantics.

## Checklist: pool stat

Steps 1–6 above, with:

- **1.** The def is a `PoolStatDef` subclass — `StandardPoolStatDef`
  (fixed cap: health, mana, AP), `GrowablePoolStatDef` (fill-and-level:
  XP), `CyclicPoolStatDef` (recurring threshold: initiative). Copy the
  matching neighbour (`stats_system/defs/action_points.tres` is a standard
  pool). Set `per_turn_mode` (`NONE` / `REFILL` / `ADD` / `CUSTOM` /
  `HOST_ADD`) and the cap-rise / cap-fall policy — semantics in
  `stats-system.md` → "Pool stats" and "Turn-start upkeep".
- **3.** The field is `@export var <id>: PoolStat`.
- **4.** A `PoolStat` sub-resource on `entity/default_entity_board.tres`.
  → still **unpinned**, and a null pool can break turns, so verify this
  one in a running scene, not just by reading.
- A pool with a companion per-turn scalar (`<pool>_per_turn` /
  `per_turn_stat_id`) is two scalar-checklist passes plus this one.

## Checklist: modifier / derived formula

Do not hardcode a rate or write `base_value` to force a number — the knob
and bin procedure is `docs/domain/stat-knobs-and-bins.md`; pick from it.
Then decide where the modifier hangs, and only there:

- **Board intrinsic** (every entity, always — e.g. CON scales the health
  cap): a `StatModifier` with a formula on the target stat's instance in
  `entity/default_entity_board.tres`; `stats-system.md` → "Intrinsic
  scaling". Formulas: `stats_system/formulas/` (`LinearFormula`,
  `ExpressionFormula`); a cycle is rejected at load, see
  "Dependency-cycle rejection".
- **Class identity** (this class only): the `CoreClass` resource under
  `entity/core/`; `stats-system.md` → "Class identity modifiers".
- **Node-local** (varies per skill node): the node's sparse
  `NodeStatBoard`; `stats-system.md` → "Local stats".
- **Granted at runtime** (an effect, a scene, a relic): `grant_core_modifier`
  / effect-granted modifiers; `stats-system.md` → "Effect-granted
  modifiers".

→ `mise run check` for the wiring; a behavioural claim ("PER scales
vision_range") gets a unit test in `test/unit/` seen red first
(`.claude/rules/red-green.md`).

## Decision checkpoint — downstream homes

Adding the stat makes it exist and scale. Before declaring done, answer
each; "no" is an answer, record it in the def's `description`:

- **Procgen content** — could a generated node roll this stat as a bonus?
  Then it needs a `TierPool` in a `StatPack` under `procgen/pools/`
  (`<archetype>.tres`, or a cross-cutting pack), bundled by
  `specimen_pool_set.tres`. Mechanics and template: `docs/domain/procgen-v4.md`
  and the neighbouring pack. → unpinned; the checkpoint is the catch.
- **HUD visibility** — should the player see it, where, and when?
  `docs/domain/stat-ui-visibility.md`; the panel wires stats by id, there
  is no metadata-driven panel (`stats-system.md` → "No metadata-driven
  stat panel").
- **Node board: borrow or own** — should this stat vary per node, or is it
  entity-scope only? `docs/domain/stat-board-classes.md`; an entity-only
  stat stays out of every procgen pool and says so in its description.

## Verify

```
mise run check
mise run test:one -- res://test/unit/test_stat_def_roster.gd
mise run test:one -- res://test/integration/test_authored_entity_boards.gd
```

Then `test:dir` on the directory your behavioural test lives in. Never the
full suite for a stat addition.
