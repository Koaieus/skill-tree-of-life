# Handoff — keystone → hand-authored SkillNode scenes

Written against `41c3127`. **Authoritative home is [#336](https://github.com/Koaieus/skill-tree-of-life/issues/336)**, which carries the full argument, the settled forks and the dispatch order. This file exists only for the cross-issue couplings and the working-tree hazards, which are not issue material.

## State

`#336` is a `design` hub with **all three forks now settled or reduced**:

- **① carve home — settled.** Hand-authored in the concrete SkillNode scene. Reduced to one regression test; no `carve_shape` slot on `SkillNode`. Capability question belongs to #245.
- **② tooltip predicate — settled.** `get_node_effects().size() > 0`, *not* a name/description check. This is what makes it survive #288.
- **③ placement surface — split.** #330's half is answered (#155: the *placement* carries `node_scene`). Clusters (#165/#180) are genuine remaining design, written up in two long #165 comments.

The hub is therefore **swarmify-ready**, not yet `Ready` — children still need filing with acceptance specs.

## Couplings — the part that would be lost

- **#179 gates everything else in #336.** Narrowed to a single `display_name` export, no `description`; it also owns flipping the `id_chip_panel` predicate. The landmark migration and #330 both wait on it.
- **#288 is why the predicate is effect-based.** Settle these together or the chip breaks silently when generated names land.
- **#327 was de-swarmified** — its spec builds the `.tres` keystones #336 deletes. Its `Role` deletion half is unaffected and can still proceed. It keeps its #321 parent. (Briefly promoted to `Ready` in error on 2026-08-02 and moved back to `Needs design` — its `## Swarmable spec` heading reads settled but is stale.)
- **#339 is independent of all of the above** and can go first.

## Ready to dispatch

Wave 1, no dependencies, parallel:
- **#339** — procgen single-component assertion + dropped-anchor warning. Acceptance written; no forks. Not in `Ready` (hasn't been through the gate) — since resolved: promoted to `Ready` 2026-08-02.
- Delete `entity/keystone/keystone_skill_node.tscn` — verified zero references.

Wave 2 is sequential and specified in #336's "Dispatch order" section. Wave 3 (clusters) is not ready.

## Live numbers

- `Keystone.stamp()` has **one** production caller: `graph_procgen.gd:207`. Plus `test_keystone.gd:44`, `test_tooltip_v2_accessors.gd:57`.
- **Six** authored `Keystone` `.tres`, **five** carrier scenes (four landmarks under `instances/`, plus `natural_xp_node.tscn` one level up). None sets `carve_shape`, `icon`, `color`, `radius` or `addon_scenes`.
- `keystone_skill_node.tscn` and `natural_xp_node.tscn`: zero references anywhere.

## Working-tree hazards at time of writing

Not committed, not mine, flagged rather than touched:

- ~~`skill_node/addons/skill_node_addon.tscn` is back as an untracked file.~~ **Resolved 2026-08-02** — deleted again, never committed. `fc124de` and `.claude/rules/scene-composition.md` stand.
- **Live procgen WIP:** `stat_pool.gd`, `wisdom.tres`, `specimen_pool_set.tres`, and `first_level.tres` tuning (`base_max` 4→3, `budget_field.inner_radius` 200). `stat_pool.gd:64` reads `jitter: float = 0.` — looks mid-keystroke. **Don't swarm procgen files onto this checkout until it's settled.**
- The four `*_keystone.tres` diffs are benign (uid addition + default elision per `godot-workflow.md`) and are about to be deleted anyway.

## Delete this file when

#179 and the #336 landmark migration have both landed — at that point the hub and the issues carry everything here.
