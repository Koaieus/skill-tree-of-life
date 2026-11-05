# Snapshot encoding

Encoding details for GraphSnapshot and EntitySnapshot rows, moved out of source comments. The overview is entity-snapshot.md.

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

## GraphSnapshot decode (reconcile) and restore_hp (`network/graph_snapshot.gd`)

Decode a payload built by `encode` into `graph` — a RECONCILE,
not a rebuild (#561 D6). A node whose `stable_id` is already present is
updated in place; only a genuinely-new id mints a `SkillNode`, only a
genuinely-absent one is removed, and the same holds edge-by-edge.

**Decoding into a POPULATED graph is therefore safe, and that is the
resync backstop's whole contract** (#561; the join case is just the
degenerate one where the graph starts empty and every row is new). The
alternative the design offered — tear the world down and replay — was rejected
because `StatBoard.read_dict` reconciles rather than wipes precisely so a live
entity's `initialize()` signal wiring survives a resync, and freeing every
`SkillNode` would strand every `EffectInstance.source_node` and every
`Navigator` mirror that a repair has no business disturbing. A repair that
touches nothing when nothing drifted is also what keeps a resync silent.

**The existing id index is built ONCE, up front, and every lookup below
reads it rather than `Graph.get_by_stable_id`.** Not a
micro-optimization: every `add_skill_node` marks the graph's topology dirty,
so a per-row lookup through the graph would rebuild the whole index once per
row — an O(nodes^2) decode at the 2000-node scale this payload exists for,
the exact shape `.claude/rules/graph.md` says this repo has shipped twice.

**`restore_hp`** re-applies nothing but each node's CURRENT HP (#715). Run it LAST, after
`EntitySnapshot.resolve_graph_refs`.

**`node_health` is a POOL, and a pool clamps.**
`SkillNode.restore_current_hp` writes through
`PoolStat.set_current`, which cannot exceed the pool's cap — and that
cap is derived: `NodeCombat.get_local_value` merges the node's own
board with its OWNER's, so it moves with whatever the owner has been granted.
`decode` therefore restores HP at a moment when the owner's board is
only partly rebuilt: the node-sourced effects an owner holds are granted in
`EntitySnapshot`'s PASS 2, which by construction runs after this. Every node
whose true HP sat above the not-yet-raised cap is silently clamped down, and
nothing ever raises it again — the value is simply lost.

**It only surfaced once a peer stopped generating its own world (#715).**
A client that had just run the same procgen already held caps within a
rounding error of the authority's, so the clamp had nothing to bite. Starting
from an empty graph it bites on every owned node at once: measured over the
shipped 800-node preset, 125 owned nodes lost ~2-4 HP each and the
accumulated fold disagreed on the first compare while ownership and topology
agreed exactly. That signature — `own` and `topo` equal, `accum` off — is what
this method exists to keep from coming back.

Idempotent and cheap: one pool write per node, no signals
(`SkillNode.restore_current_hp` bypasses damage/heal by design).

## Rebuilding the by-value spell book (`network/entity_snapshot.gd`)

Rebuild the by-value book `_encode_spell_ids` sent (#726).

**A no-op when the membership already agrees, and that guard is what makes
this idempotent** — the property every other step of this decode has, and
the one a mid-run repair depends on (#715: a resync applies even when the
fingerprints agree, because the fold covers neither tags nor effects). A
rebuilt book carries no `SpellBook._sources`, which is right for a
blocker — `duplicate_pruned` drops them too, the copy being a loot pool whose
every spell reads as innate — and WRONG for a hero on a second decode: pass 2
would not put them back, because `_grant_effects` skips a
`SpellGrant` whose `EffectInstance` is already in the ledger. The spell would
stay in `spells` with nothing behind it, and the next
`Entity.revoke_effects_from` would find no source to drop and keep a
spell the authority had already taken away.

Comparison is by `SpellDef.id` and in ORDER, which is safe only
because the peer's book is never written except by this method — so its order
is always the one that last crossed. `SpellGrant` is what could write it out
of band, and no SpellGrant crosses: every one in the repo is built with
`.new()` (`GraphProcgenSpellGrants.distribute`, `SkillDustAddon`), so it has
no `resource_path` and `_encode_entity` drops it from the effect list
by the same rule it drops a path-less effect. **Author a SpellGrant `.tres`
and this reasoning expires** — `test_pruned_spellbook_crosses.gd` has a
tripwire on exactly that. Two things would then need looking at: an
unordered compare here, and the fact that `add_spell` on a book whose
`_sources` this method left empty APPENDS a second copy of a spell already in
`spells`.

When it does rebuild it is always a FRESH `SpellBook`, never the entity's own
book narrowed in place. What this peer holds is a level-side assumption
(`EntityFactory.spawn_blocker`'s tier default), and reconciling INTO it
would make the result depend on that assumption; and a caller that handed
over an authored `.tres` directly — a fixture, a sandbox — does not get that
shared const narrowed under it.

## Spawning a row's missing entity (`network/entity_snapshot.gd`)

Ask `spawner` for the `Entity` a row names when this peer does not have
it (#715). Null when there is no spawner, or when it declines.

**This relaxes #560 D7, and the premise D7 rested on is what changed.**
That decision — "it decorates, it never spawns" — was justified by "#528 and
#553 both shipped, so a joining client's entities exist by the time state
arrives": the roster spawns exactly the named set, so a spawning snapshot
would be a second minting path racing it. That held while BOTH peers ran
procgen. Since #715 the client runs none, and procgen spawns entities the
ROSTER NEVER NAMES — one `Entity` per removable blocker (#477), ~120 of them
on the shipped 800-node preset. They have no other way to arrive, and without
them the client decodes their nodes as UNOWNED, which moves
`WorldFingerprint.compute`'s ownership fold on the very first compare.

**It is not a second minting path.** The id is the AUTHORITY's, taken from
the row and stamped before the entity enters `entities_container` —
`Graph._mint_entity_id` assigns only to an entity whose `entity_id` is
still `0`. It is the exact mirror of `_prune_entities`, which already
deletes an entity the payload does not name: the payload is the authority's
entity SET, and both directions of that set now cross.

**Why a CALLBACK and not an `instantiate()` here.** The row's scene path is
carried (`_R_SCENE`) and this class could instantiate it — but a
blocker's `EntityStatBoard` is assigned in CODE per tier
(`EntityFactory.spawn_blocker`), not authored in `blocker_entity.tscn`, and
`StatBoard.read_dict` cannot rebuild a board from nothing:
`EntityStatBoard` refuses to mint a stat it has no field for, by design. A
bare instantiate would therefore produce a blocker with no board and no
health, which the accumulated fold would then disagree about instead. So the
LEVEL builds it — it is the one that knows what a blocker is — and this class
keeps knowing only about rows. See `EntityFactory.spawn_snapshot_entity`.

## Spell book membership by value (`network/entity_snapshot.gd`)

The membership of a spellbook that has no `resource_path` to intern, by
value — and `null` for every book that HAS one (#726).

**Which is, in practice, every book.** `Entity._ready` deep-copies
whatever `spellbook` it was handed, so no two entities share the authored
`.tres` object — and a `duplicate` carries no `resource_path`. So
`_R_SPELLBOOK`'s interned path, which predates this, has always been
-1 for a live entity and the spellbook has never actually crossed. The `null`
branch below is therefore only reachable from a hand-built fixture; it is kept
because the two channels answer different questions and the path is the
cheaper answer whenever it IS available.

**What made it visible.** A blocker's book is additionally a #586
`SpellBook.duplicate_pruned` slice — a random subset of its tier's
authored book — and since #715 the client does not run the procgen that drew
it, so it cannot re-derive the slice either.
`EntityFactory.spawn_snapshot_entity` hands the rebuilt blocker its tier's
WHOLE authored book instead, and a player inspecting one sees a longer spell
list on the client than the host has. The ids are how the slice crosses.

**ids, not paths** — `SpellDef.id` is the only legal cross-process
reference to a spell (#511, owner call 2026-08-21), resolved back through
`SpellCatalog.by_id`. A def with an empty id is dropped, the same rule
`_encode_entity` applies to a path-less effect one method up: real
content is authored, an id-less def is a fixture.

**`null` and `[]` are different answers** and both are load-bearing: the
prune chain is documented to be able to run all the way to EMPTY, so a
path-less book with zero spells is a real outcome that must not read as
"this row says nothing about the spellbook".
**Interned, not spelled out per row.** Nine authored spells share ~120
blocker rows on the shipped preset, so the ids are the most repetitive thing
in the payload; `spell_table` collapses each to an int and sends every
distinct id once. Same trick `res` plays on resource paths, and for the same
reason interning is what stops a per-entity cost being per-entity.
