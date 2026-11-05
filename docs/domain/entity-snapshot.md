# EntitySnapshot — the entity half of the join handshake

`network/entity_snapshot.gd`. Sibling to `GraphSnapshot`: one encoder, one
subject, composed alongside it at the same handshake point with its own
`WorldSyncChannel.KIND_ENTITIES` envelope. `GraphSnapshot` carries which `Entity`
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
  by `stable_id`, and the two per-turn fields a mid-turn arrival (resync, load)
  would otherwise lose — `Entity.volleys_launched_this_turn` (else the volley
  budget refills) and the turn-start reload leaves (`get_turn_start_leaves`)
  by `stable_id`, resolved in pass 2 like `core_location` — crosses BY VALUE.
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
  callback, `WorldSyncChannel.entity_spawner` → `EntityFactory.spawn_snapshot_entity`,
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
`resolve_graph_refs` runs AFTER, because `core_location`, the turn-start
leaves and an effect's `source_node` resolve entity → node, the opposite direction from
`GraphSnapshot._decode_node`'s `owner_id`. Both passes are idempotent: effects
are granted only if an equal grant is not already present, tags only if not
already held, and `StatBoard.read_dict` reconciles rather than rebuilds. That
is what lets pass 2 re-run the board restore to absorb the node-sourced
effects it just granted. Order between the graph and entity snapshots
therefore does not matter; hello still has to be last (send order: see
`docs/domain/multiplayer-harness.md`, "THEN hello").

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
the same reason: string keys roughly double a naive payload. A slot added after the
first release is width-guarded on decode (`row.size() > _R_X`), so a shorter
hand-built fixture row reads as "says nothing" rather than as zero.

## GraphSnapshot encoding (`network/graph_snapshot.gd`)

Encoder/decoder for #527's "a joining client receives a serialized graph;
it does not regenerate one" contract. Procgen is deterministic, but
serializing also covers the cases regenerating can't: mid-run join,
hand-authored levels, and (later) save/load. See
#527's acceptance spec, and #463's 2026-08-24 sync-model decision comment.

**Three tiers, split per-moment not per-system** (the issue's own
table):
- Authored (archetype, addon placements, the node's own scene, and
  node-direct `effects` — #527's Decisions section named keystones here;
  since #929 a landmark's effects ride in its scene) crosses as an
  INTERNED REF into a resource-path table built once per snapshot. 7
  archetypes / 6 addon scenes repeated per-node as full paths is the
  single biggest lever the issue's arithmetic calls out — ~230 KB of
  repeated strings collapses to a handful of bytes plus a once-sent
  table. An effect built via `.new()` rather than loaded from a shared
  `.tres` (real gameplay content never does this — only tests) has no
  `resource_path` and is silently dropped rather than crossing broken;
  that mirrors how `_encode_node` already treats an addon with no
  `scene_file_path`. An effect EMBEDDED in the node's own scene (a
  landmark's SubResource `StatEffect`, path `<scene>::<id>`) is not
  interned either: the scene is re-instantiated on the create path and
  brings it along, and `_reconcile_authored` leaves it in place.
- Accumulated (owner, HP, stake/allocation level, regen stacks, the
  modifier LIST) crosses BY VALUE — no formula rederives history.
- Derived (`StatBoard` totals, aura contributions, vision/fog) never
  crosses. Not this class's problem at all.

**An addon's own modifiers are NOT double-encoded.** Re-instantiating an
addon's `.tscn` on decode re-attaches its `entity_modifiers` /
`local_modifiers` for free (`.claude/rules/skill-node-addons.md` —
attaching is just `add_child`). So `_encode_node` strips any
modifier on `SkillNode.modifiers` that's also present on one of the
node's attached addons before encoding it, and `_decode_node`
attaches addons FIRST, then appends the residual (the node's own "offered"
modifiers) on top — reproducing the same list the source node had.

**Rows are POSITIONAL** (arrays, not dictionaries with string keys) —
string keys like `allocation_level` roughly double a naive payload's size,
per the issue's own measurement. The whole structure goes through
`var_to_bytes` then `PackedByteArray.compress(COMPRESSION_ZSTD)` before it
leaves this class — wire time on LAN is 1-7ms either way, so this is a
tidiness requirement, not a performance one, but paths-per-node would have
been the embarrassing omission.

**Ownership resolves through the RECEIVING graph's own entities.** An
owner id with no matching `Entity` (via `Graph.get_by_entity_id`)
decodes as unowned — spawning entities and minting their ids is #528's
concern (`RunConfig` / `ParticipantRoster`), not this unit's. A mid-run join
is expected to land its roster before (or alongside) its graph snapshot.
