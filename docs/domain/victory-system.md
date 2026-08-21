# VictorySystem — how a run ends (#460)

Before this, a run had no terminal state: you played until you stopped. Now one
system decides the run is over, once, and says who won.

## The pieces

| Thing | File | Role |
|---|---|---|
| `VictorySystem` | `systems/victory_system.gd` | The **when** and the **once**. Reacts to death, latches, emits. |
| `VictoryCondition` | `session/victory/victory_condition.gd` | The **what**. Pure `evaluate(ctx) -> RunOutcome?`. |
| `LastCampStandingCondition` | `session/victory/last_camp_standing_condition.gd` | The first and default rule. |
| `VictoryContext` | `session/victory_context.gd` | Everything a condition may read, snapshotted per evaluation. |
| `RunOutcome` | `session/run_outcome.gd` | Pure data: `winning_camp`, `local_result`, `turn_count`. |
| `Faction.counts_for_victory` | `entity/faction.gd` | Authored inertness. |

The split is the point: a mode that wants a different rule swaps a resource and
inherits latching, signal timing and the death trigger for free.

## The rule

**Owner call 2026-08-21:** "be the only camp that survives — no living hostile
entities remain. **Blocker NPCs do not count**; they are inert scenery, not a
camp that can win or lose." And, pluggable, "because multiplayer setups will
want different conditions" — last-camp-standing is "the first and the default,
not the only one".

Two consequences that are easy to get wrong:

- **Survival is measured in living entities, not roster seats.** A camp whose
  participants are all dead has lost, even though its `Participant`s are still
  in the roster.
- **Camps are compared by `Faction.id`**, matching `Entity.attitude_to` — two
  copies of one `.tres` are one camp, not two.

Single-player needs no special case: the player is one counting camp and the AI
is another, so dying is a LOSS and clearing the board is a WIN, straight out of
the same rule.

## Inertness is authored, never inferred

`Faction.counts_for_victory` is `false` on **`entity/factions/blocker.tres`**
only — the "dormant cores" camp that removable blockers (#300) belong to. A
hard-coded `if faction.id == &"npc"` at the check site would be a second
definition of "who is a real camp", living somewhere no designer looks.

**The trap this avoids:** blockers and AI opponents both sat on `npc.tres`
(`entity.gd`'s default faction, and what `procgen_play_sandbox.gd` hands every
AI participant). Flipping the flag on `npc.tres` — which the issue's original
wording said to do — would have left exactly one counting camp at spawn and
ended every run the instant it started. A hand-built two-camp test still passes
under that bug; only the real level breaks. If you touch faction authoring,
check what the *live levels* actually assign, not what the names suggest.

Side effect worth knowing: giving blockers their own faction id makes them
**hostile to the NPC camp** too, where before they were allied by sharing
`npc`. AI opponents can now target blockers.

## Evaluate on death, coalesced — and why DRAW depends on it

The only thing that can change last-camp-standing's answer is an entity dying,
so VictorySystem listens to `Events.entity_death_shown` (the last of the three
death phases — see `.claude/rules/entity-death.md`) rather than polling.

Evaluation is then **deferred, one per frame**. That is not an optimisation:

> Deaths arrive one signal at a time. Evaluating inline would see the
> second-to-last death leave one camp standing and announce a WIN before the
> last death ever fired — making `DRAW` unreachable dead code.

Coalescing lets a mutual wipe inside one mutation batch be judged as the single
event it is. VictorySystem mutates nothing, so this is not "frame-ordering a
mutation" in the sense `.claude/rules/multiplayer-sync.md` forbids — it reads a
world the mutation loop has already settled.

`outcome` is the latch. Every death after the terminal one still fires the
signal and must be ignored.

## One definition of "the run ended"

`Events.run_ended(outcome)` is it, and `VictorySystem` is the sole emitter.

`Events.game_over` survives as the HUD overlay's cue but is now **derived**:
`GameRoot._on_run_ended` re-emits it when `local_result != WIN`. It no longer
fires off player death directly — that was a second, competing answer to the
same question, and it got hot-seat coop wrong (a dead player with a living ally
would have ended the run).

## What is deliberately not here

- **`GameSession`** (#457) does not exist yet — it is an owner-decision unit
  with open forks, and a parameter cannot be typed as a class that isn't
  written. `VictoryContext` is the shape GameSession will populate; the
  conditions do not change when it lands. `TODO(#457)` marks the two sites:
  who supplies the `RunConfig`, and who records the outcome durably.
- **`local_camp`** comes from `GameRoot.bind_player` reading `player.faction`,
  because a run has no roster yet. `TODO(#461)` — it becomes the local
  `Participant`'s camp once the lobby builds a real `ParticipantRoster`.
- **A results screen** is out of scope (#461). The route is a delayed
  `SceneDirector.goto(META_ROOT)`, off by default in the dev sandboxes
  (`route_to_meta_on_run_end`) so tooling does not teleport itself to the menu.
