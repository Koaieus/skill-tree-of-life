# TurnManager: adopting and abandoning a turn

The quick reference (single-phase turn, initiative, hooks) is
`.claude/rules/turn-manager.md`. This doc holds the two non-obvious turn-cursor
entry points in `systems/turn_manager.gd`, which exist beside `start_turn` /
`end_turn` for cases where nobody decided to start or end a turn.

## `abandon_turn(entity)`: the actor died mid-turn

Ends the acting entity's turn without handing the clock on. Caller:
`GameRoot._pull_from_turn_loop`. A corpse must not hold the turn, and without
this the cursor would be nulled from the outside so `turn_ended` never fires for
a turn that ended by death. The only guard on that invariant would be
`start_turn`'s `assert`, compiled out of a release build, while the listeners
that go stale are real (`ActionCluster` leaves the End Turn button live, the
initiative bar keeps the acting tint, `PlayerInputController`'s act-gate never
re-emits).

- **It does not tick on to the next entity**, unlike `end_turn`. The handoff is
  command-ordered: `EndTurnCommand` exists so `_tick_until_ready`'s group-order
  tiebreak runs at the same point of the command stream on every peer, and a
  clock advanced locally out of a death handler reopens that hazard. A status
  tick killing the actor at its own turn end runs inside `end_turn` after the
  cursor is nulled, so the call is a no-op and `end_turn` does the handoff. Chip
  damage and core overflow kill the defender during the attacker's turn; a
  mid-turn death of the actor (thorns / counter-damage, per `LootSystem`'s
  killer-attribution note) is the unbuilt case this guards.
- **It never ticks statuses:** an abandoned turn (a death, the status sandbox's
  `disarm`) was not played out; see `Entity.resolve_turn_end`.
- **No-op unless `entity` holds the turn:** death fires for bystanders too, and
  `Entity.die()` is re-entrant from inside a forced-dealloc cascade, so a second
  arrival must not emit a second `turn_ended`.
- **A side-effect-bearing emit inside the `entity_died` phase:**
  `Entity.finish_turn` runs on the corpse, moving its unused AP into a DP/MP
  surplus and dispatching `_on_turn_end`. Whether that lands before or after
  `AllocationSystem`'s strip is decided by child order in `game_root.tscn`,
  scene-authored and identical on every peer, so it is deterministic, not a sync
  hazard; the surplus is written to an entity that never takes another turn.

## `adopt_turn(entity, total_turns_taken, rounds, round_open, waiting, ...)`: the cursor as a result

The resync half of "the mirror never starts a turn on its own". `start_turn` is
a decision: it consumes readiness, tallies a turn and fires the upkeep. This is
the same cursor arriving as a result, from `EntitySnapshot.restore_turn_cursor`,
on a peer whose whole world was just overwritten by the authority's. It sets what
`start_turn` sets and runs none of what it runs (no `Entity.begin_turn`, only
`Entity.mark_turn_adopted`) because the payload it came with is the world after
all of that already happened.

- `total_turns_taken` is the authority's `turns_taken`, adopted outright: it is
  what `RunOutcome.turn_count` reports, and a repaired mirror counting its own
  gave different turn counts on host and client.
- **No `turn_ended` for the entity being displaced.** That signal mutates
  (`Entity.finish_turn` moves unused AP into next turn's surplus), and the
  surplus the repair should end with is already in the restored board. A repair
  has no presentation semantics and must never acquire any.
- A no-op when the cursor already agrees (the ordinary mid-run repair), which
  keeps it idempotent like every other step of a resync decode.
- `rounds`, `round_open` and `waiting` are the authority's round state
  (`rounds_completed`, whether a round is open, `round_waiting`), adopted
  outright for the same reason as the tally: a mirror counting its own would end
  a turn-limited run on a different turn. `rounds < 0` leaves round state
  untouched. Never emits `round_completed`.
- `world_progress` is the authority's `world_turn_progress`, adopted with the
  round state (and only then); never emits `world_turn_ended`.
