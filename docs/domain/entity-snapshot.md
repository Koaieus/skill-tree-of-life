# EntitySnapshot — the entity half of the join handshake

`network/entity_snapshot.gd`. Sibling to `GraphSnapshot`: one encoder, one
subject, composed alongside it at the same handshake point with its own
`CommandLink.KIND_ENTITIES` envelope. `GraphSnapshot` carries which `Entity`
owns each `SkillNode`; this class carries what each entity *has accumulated* —
its board, its effects, its tags, its core — so a joining peer's boards match
the authority's from the first frame. The sync model it serves is
`docs/domain/multiplayer-sync-model.md`; this page is the class contract.

## The bug it exists to close

`GraphSnapshot._decode_node` sets `node.owned_by` directly, bypassing
`AllocationSystem`, so nothing rebuilds the owner's `EntityStatBoard` from
decoded ownership. Without this class a client joining mid-run held boards
missing every allocated node's grants and every looted relic. Because
`NodeCombat.get_local_value` merges a node's board with its OWNER's, and
`node_health` is a borrowed stat with the entity carrying the baseline, a
missing `+5 CON` moved every health bar that entity owns at once — silently
(#560).

## Three tiers, same as GraphSnapshot

- **Authored** — `CoreClass`, `Faction`, `SpellBook`, each granted `Effect` —
  crosses as an INTERNED REF into a per-snapshot path table, exactly as
  archetypes and addons do next door.
- **Accumulated** — per-stat `base_value` and the applied modifier list, every
  `PoolStat.current`, `SkillPointStat`'s `wounded` / `staked`,
  `SurplusPoolStat.surplus`, the granted `EffectInstance`s with their source
  node's `stable_id`, active tags, `Entity.entity_tier`, `Entity.core_location`
  by `stable_id` — crosses BY VALUE.
- **Derived** — board totals, `Stat.bins`, aura contributions, vision — NEVER
  crosses. The receiver recomputes.

**Modifiers cross by value, not interned, and that is not a tier violation.**
The `Entity.stat_board` setter stores a `duplicate(true)` at assignment
(`initialize()` duplicates only in the editor), and a
duplicated sub-resource carries no `resource_path`, so a LIVE board's
intrinsics and class modifiers have nothing to intern. The authored/accumulated
split collapses to by-value for modifiers on any board actually in play — the
only kind this class ever encodes.

## Decorate, prune, materialize

The payload is the authority's entity SET, and both directions of that set
cross:

- Every row resolves through `Graph.get_by_entity_id` and DECORATES an entity
  the roster already spawned.
- A row whose entity is absent asks `_materialize` (an optional spawner
  callback, `CommandLink.entity_spawner` → `GameRoot.spawn_snapshot_entity`,
  which accepts blockers only) and, if that declines, is SKIPPED with a
  warning — mirroring how `GraphSnapshot._decode_node` decodes an unresolvable
  `owner_id` as unowned rather than inventing an entity. This is not a second
  `entity_id`-minting path: the id is the authority's, read off the row and
  stamped before the entity enters `entities_container`. The decision that
  relaxed the original "never spawns" rule, and its grounds, are in
  `docs/domain/multiplayer-sync-model.md` ("The resync backstop").
- An entity the payload does NOT name does not exist in the authority's world,
  and `_prune_entities` drops it. A join never needed that (the roster spawns
  exactly the named set); a resync does.

## Two passes, and the order is load-bearing

`decode` runs BEFORE the graph decodes — it needs no nodes.
`resolve_graph_refs` runs AFTER, because `core_location` and an effect's
`source_node` resolve entity → node, the opposite direction from
`GraphSnapshot._decode_node`'s `owner_id`. Both passes are idempotent: effects
are granted only if an equal grant is not already present, tags only if not
already held, and `StatBoard.read_dict` reconciles rather than rebuilds. That
is what lets pass 2 re-run the board restore to absorb the node-sourced
effects it just granted. Order between the graph and entity snapshots
therefore does not matter; hello still has to be last (see
`docs/domain/multiplayer-harness.md`, "Rung 2").

## Effects are granted BEFORE the board is restored, in each pass

`EffectContext.grant` puts a modifier on the board and records the HANDLE in
the `EffectInstance` ledger, which revokes by object identity. Grant first,
then reconcile: the reconcile recognises the effect's own modifier by wire
form and leaves the handle in place, so a later `Entity.revoke_effects_from`
on the client actually removes something. Restoring the board first and
granting after would double every effect's contribution instead — the very
failure mode the class exists to kill.

## No `var_to_bytes(obj, full_objects = true)`

It instantiates arbitrary objects from script paths in the payload (owner
decision on #560). Everything object-shaped goes through `StatModifierCodec`
or an interned resource path.

## Row layout

Rows are positional (`_R_*` consts), same convention as `GraphSnapshot` and for
the same reason: string keys roughly double a naive payload.
