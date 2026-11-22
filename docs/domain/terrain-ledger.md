# Terrain ledger: graph-wide Heat / Cold / Charge counts (#1845)

A balancing readout for the go-off knobs (ADR 0098's revisit-when: *effect
minting outrunning void + decay*). Three parts, each knowing only the one below:
`HitGather` books, `CombatWorld` raises, `TerrainLedger` counts;
`TerrainLedgerOverlay` (F4) draws it.

## What is booked, and where

`TerrainBook` holds one commit's **applied** amounts per element
(Heat, Cold, Charge) × field: `PRODUCED`, `EFFECT`, `VOIDED` (node-paid),
`VOIDED_INCOMING` (a blade copy's pay: off the graph), `DECAYED`,
`ONTO_OPPOSITE`. As a `SettleReader` appended **last** to a commit's readers it
sees each node's pre ints and final sums, and splits them the way
`TerrainSettle.settled_t` lands them: Heat adds, then Cold adds (the part that
lands on the opposite sign is `ONTO_OPPOSITE` — 1 Heat on 3 Cold books produced
1, onto Cold 1, and the node reads 2 Cold), then the pull toward zero on the
side t ends on. Charge's subtraction is clamped at what is there. Whatever an
earlier reader added (a Catalyst conversion) books as `PRODUCED`.

| Commit | Book | Where |
|---|---|---|
| a head's rider (through its row) | `book_landing`, produced | `HitGather._land_riders` |
| the land batch (copy riders, Catalyst) | produced | `HitGather._generation` |
| the spend batch (costs, effects, shatter) | effect / voided | `HitGather._generation` |
| a copy's incoming cost | voided_incoming, what it had | `HitGather._pay` |
| diffusion | Heat that met Cold → Heat onto_opposite | `CombatWorld.diffuse_temperature` |
| decay | decayed | `CombatWorld.decay_terrain` |
| a degree drop's prime read | produced | `CombatWorld.prime_threshold_drops` |
| an unstaged terrain rider's `land_on` | `book_landing`, produced | `OutcomeApplier.land_one` (live only) |

The gather's beat sum rides the beat's first head as `HitInstance.terrain_sums`
(record columns `tr_sn` / `tr_s`, beside `tr_*`), never on a copy. Per beat, not
per hit: the beat nets its nodes as one, as `terrain_ops` does. It is read-only
telemetry: `terrain_ops` alone mutates terrain. `OutcomeApplier.land_one` raises
it via `CombatWorld.book_terrain`, which a shadow world refuses — so only the
live replay counts, on every peer alike.

## The sample

`TerrainLedger` (Systems/TerrainLedger in `game_root.tscn`) closes one sample on
`TurnManager.world_turn_ended`, keeping `window_turns` (40, tentative). Per
element: the booked fields, `from_opposite` (the other side's `onto_opposite`),
`total` and `primed` from `CombatWorld.terrain_nodes()`. Per element every
sample satisfies

    Δtotal = produced + effect − voided − decayed − onto_opposite − from_opposite

(both opposite terms subtract: a Heat landing on Cold adds no Heat and removes
Cold). `voided_incoming` is outside it: a copy's store is not graph terrain. A
`GraphSnapshot.decode` raises `CombatWorld.terrain_rebased`, and the ledger
clears its history and takes a new baseline. Session-only: never saved.

**Not booked**: any other direct `NodeCombat.add_terrain` / terrain
`apply_status` (a test's or the terrain sandbox tab's arrange writes, and any
caller outside the attack pipeline, unaudited). Such a write breaks the identity
for that sample.
