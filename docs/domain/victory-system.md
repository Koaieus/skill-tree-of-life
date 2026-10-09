# VictorySystem — how a run ends

One system decides the run is over, once, and says who won.

## The pieces

| Thing | File | Role |
|---|---|---|
| `VictorySystem` | `systems/victory_system.gd` | The **when** and the **once**. Reacts to death, latches, emits. |
| `VictoryCondition` | `session/victory/victory_condition.gd` | The **what**. Pure `evaluate(ctx) -> RunOutcome?`. |
| `LastCampStandingCondition` | `session/victory/last_camp_standing_condition.gd` | The first and default rule. |
| `TurnLimitCondition` | `session/victory/turn_limit_condition.gd` | After N rounds, the highest-scoring camp wins (a bonus, below). |
| `VictoryContext` | `session/victory_context.gd` | Everything a condition may read, snapshotted per evaluation. |
| `RunOutcome` | `session/run_outcome.gd` | Pure data: `winning_camp`, `turn_count`. Point-of-view-free. |
| `ContestantRule` | `session/victory/contestant_rule.gd` | The **who**. Pure `includes(ent) -> bool`, owned by the condition. |
| `ExcludeGroupRule` | `session/victory/exclude_group_rule.gd` | The one rule so far: everyone except a Godot group (`scenery`). |

The split is the point: a mode that wants a different rule swaps a resource and
inherits latching, signal timing and the death trigger for free.

## The rule

**Last camp standing:** you win by being the only camp that survives, with no
living hostile entities left. **Dormant Cores do not count** (`blocker` in code —
see `docs/domain/dormant-core.md`); they are inert scenery, not a camp that can
win or lose. It is the default condition, not the only possible one — why the
rule is a swappable resource rather than something `VictorySystem` hardcodes is
[ADR 0009](../adr/0009-the-victory-condition-is-a-swappable-resource.md).

Two consequences that are easy to get wrong:

- **Survival is measured in living entities, not roster seats.** A camp whose
  participants are all dead has lost, even though its `Participant`s are still
  in the roster.
- **Camps are compared by `Faction.id`**, matching `Entity.attitude_to` — two
  copies of one `.tres` are one camp, not two.

Single-player needs no special case: the player is one counting camp and the AI
is another, so dying is a LOSS and clearing the board is a WIN, straight out of
the same rule.

## Contest membership is a rule the condition owns

Who counts as a contestant is a predicate the condition owns, not a flag on
`Faction` — the grounds, and the per-camp bool it replaced, are
[ADR 0010](../adr/0010-contest-membership-is-a-rule-the-condition-owns.md).

`VictoryCondition.contestants` is a `ContestantRule`, defaulting to
`session/victory/rules/exclude_scenery.tres` — everyone except members of the
Godot group `scenery`, which `entity/blocker/blocker_entity.tscn` authors on
itself. `Entity` gains no field and learns nothing about victory; a group *is*
the engine's per-unit tag. **A null rule means everyone counts** — never a crash,
never a run that can no longer end.

Four things to keep straight:

- **The group means OUT, never IN.** `VictorySystem` lives in `game_root.tscn`,
  so a GUT fixture or a sandbox tab has none to stamp anyone; under an "in"
  polarity every evaluation would be an instant DRAW. Only the exception
  authors itself, and today that is `blocker_entity.tscn` alone.
- **It is a filter, not a second enumeration.** `build_context` walks
  `Entity.GROUP` exactly once. A rival walk would silently drop every
  `Entity.new()` fixture and sandbox entity out of victory evaluation.
- **Membership is pulled at evaluation time, never pushed at spawn.** A
  run-start sweep would have to run after `victory_system.condition` is
  assigned — later than `_setup_level` — and would then re-stamp anything a
  level deliberately un-stamped, because a boolean group cannot tell "not yet
  stamped" from "deliberately out". There is also no `entity_spawned` signal and
  four creation paths. A materialised *view* computed from the same rule stays
  purely additive if save/replay/spectating ever wants one.
- **Bespoke run-end logic is a `VictoryCondition` subclass**, not a cleverer
  rule. Do not grow `ContestantRule` to anticipate a tutorial.

Membership sits on the *scene*, never on a resource other entities share — which
is what keeps Dormant Cores separable from the AI opponents they share `npc.tres`
with. [ADR 0010](../adr/0010-contest-membership-is-a-rule-the-condition-owns.md)
records the run-ends-at-spawn failure that shape was chosen to remove.

### The sibling flag: `Faction.targeted_by_ai`

`blocker.tres` authors `targeted_by_ai = false`; it does not follow contest
membership off `Faction`, because "worth an NPC's AP" is camp-level. It is
filtered in the AI's target predicate, never in `Entity.attitude_to()` — a
Dormant Core stays `HOSTILE`. Mechanics and rationale:
[ownership-vocabulary.md](ownership-vocabulary.md), and the per-entity
alternative in [ADR 0010](../adr/0010-contest-membership-is-a-rule-the-condition-owns.md).

**Known consequence, deliberately unsolved:** an NPC whose only route out of its
region is through a Dormant Core will never clear it, and grows in place forever.
Placement samples uniformly over regular nodes, so a cut vertex is possible but
unobserved. The fix, if needed, is an AI-side "boxed in → treat them as targets"
fallback, not a change to this flag. Dormant Cores have their own faction id, so
they are **hostile to the NPC camp** too: AI opponents can target them.

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

## The turn limit — a bonus on the clock

`TurnLimitCondition` (`session/victory/turn_limit_condition.gd`): after `limit`
rounds (or entity-turns — the `unit` enum, `ROUNDS` by default) the camp with
the highest score wins. Score = `(Σ lifetime XP via GrowablePoolStat.total(),
owned nodes)` over the camp's living contestants, compared lexicographically —
owned territory breaks an XP tie (owner, 2026-10-02); a tie on both is a DRAW.
Lifetime XP rather than level + bar because those don't add across several
members (owner pick, 2026-10-03, #1312). Territory is one walk of `ctx.graph`
per evaluation, bucketed by camp, with the same valid/living/contestant filter
as the XP sum. The scoring is one private method (`_camp_score`) so it can
become a knob later.

It ships as a **bonus** under `CombinedVictoryCondition`
(`session/victory/turn_limit.tres`, `limit = 15`), so last-camp-standing still
ends the run early. The lobby offers it as a lobby option through
`victory_options.tres` (a `target: "victory_condition"` override),
and the `mp:e2e` autoplay host picks it so every run is short. The lobby
label is **derived, not authored**: `VictoryCondition.describe()` says what a
condition is (`"Turn limit (15 rounds)"` from `limit` + `unit`; a combinator
reports its bonuses, else its floor), and `LobbyOption.display_label()` shows
that whenever an option's `label` is empty — so the round count is authored
once, in `turn_limit.tres`.

- **A round is the classic initiative round**, owned by `TurnManager`: it opens
  with a roster of every living initiative carrier and completes when the last
  member still waiting *ends* its turn (`rounds_completed`, `round_completed`).
  A fast entity may act twice inside one; a mid-round joiner waits for the next
  roster; a member that dies leaves it. Only turn order counts, so a uniform
  change to initiative gain changes nothing.
- **Sync:** the bookkeeping runs at the `turn_ended` sites, which
  `EndTurnCommand` reaches on every peer at the same point; the resync
  (`EntitySnapshot`'s turn cursor → `TurnManager.adopt_turn`) carries
  `rounds_completed` and the open roster with `turns_taken`, adopted outright.
- **Trigger:** `VictorySystem` also evaluates on `TurnManager.turn_ended` — a
  clock condition has no death to wake it. A played-out turn is judged **on the
  spot**, not deferred: `end_turn` hands the clock on synchronously and the host's
  AI may act in the same frame, so a deferred read would see a later turn on the
  host than on the mirror. A turn ended by death (`abandon_turn`, mid-cascade)
  stays deferred like the death trigger. The round bookkeeping runs just before
  `turn_ended`, so the judgement reads the round that turn closed. The condition
  reads `VictoryContext.rounds_completed`, never `TurnManager`.

## One definition of "the run ended"

`Events.run_ended(outcome)` is the only run-end signal, and `VictorySystem` is its
sole emitter.

## The outcome has no point of view

`RunOutcome` names the winning camp and nothing else. There is no `local_result`
and no `local_camp` anywhere: a run has ONE winner and as many points of view as
there are machines watching it, so "did I lose" is a fact about a screen.

`HudRoot._on_run_ended` makes that reading, and makes it from `SeatPolicy`:

- **Banner** — camp-authored, always: `"%s wins!" % winning_camp.display_name`,
  tinted `winning_camp.color` (via `AnnouncementRequest.make_tinted`, not
  `make_for_entity` — there is no acting entity for it to go stale against). A
  camp with two living heroes announces once, as a camp, and plural phrasing for
  coop is an authoring choice in the faction `.tres`, not a code branch.
- **Overlay** — `RunEndOverlay`, raised on EVERY outcome, because it carries the
  way out of the level. Seating decides its *copy*, never its visibility:
  `Seating.COUCH` reads `NEUTRAL` ("RUN OVER" — two rivals share one screen, so
  there is no camp for it to have lost from), `Seating.SEAT` reads
  `VICTORY`/`DEFEAT` from the seated hero's camp, and no winner at all reads `DRAW`.

**Seating, not the bound player.** `rebind_player` fires on every hot-seat
handover, so a banner derived from the bound player (or `HudRoot._player`) resolves
from whichever rival acted last. Reading `_player` under SEAT *is* sound, because
`follows_active_turn()` is false there and the bound hero never re-points —
including after it dies, which is why the overlay cannot be found by walking
`Entity.GROUP` (GameRoot pulls corpses out of it synchronously).

`HudRoot` reads `seat_policy` at run-end time rather than caching it: a roster
*replaces the object* during `_setup_level`, so a cached policy can be stale.

## What is deliberately not here

- **`GameSession`** supplies the `RunConfig` whose `resolved_victory_condition()`
  GameRoot installs, and records the outcome as the run's terminal state.
  `VictoryContext` is built by `VictorySystem`, not by the session.
- **A results screen.** The way out is `GameRoot.route_to_meta_now()` — one latched
  `SceneDirector.goto(META_ROOT)` with two callers: the overlay's *to main menu*
  button, and `run_end_route_delay` as the fallback. `route_to_meta_on_run_end`
  vetoes both so tooling does not teleport itself to the menu; the action row
  still appears under the veto and the press then dismisses the overlay.
