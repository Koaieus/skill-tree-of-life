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
| `RunOutcome` | `session/run_outcome.gd` | Pure data: `winning_camp`, `turn_count`. Point-of-view-free. |
| `ContestantRule` | `session/victory/contestant_rule.gd` | The **who**. Pure `includes(ent) -> bool`, owned by the condition. |
| `ExcludeGroupRule` | `session/victory/exclude_group_rule.gd` | The one rule so far: everyone except a Godot group (`scenery`). |

The split is the point: a mode that wants a different rule swaps a resource and
inherits latching, signal timing and the death trigger for free.

## The rule

**Owner call 2026-08-21:** "be the only camp that survives — no living hostile
entities remain. **Dormant Cores do not count** (`blocker` in code — see
`docs/domain/dormant-core.md`); they are inert scenery, not a
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

## Contest membership is a rule the condition owns (#517)

*Was* `Faction.counts_for_victory`, a bool per camp. That could not express a
**per-entity** exception without minting a faction for it, so it became a
predicate instead.

**Owner call 2026-08-22:** *"i feel like the game mode decides the victory
conditions, and entities themselves just should be agnostic of all this... i
think a predicate (customizable to any condition) would be a more useful
construct than a single bool... i feel like victorycond would be the one to
apply them anyway."*

`VictoryCondition.contestants` is a `ContestantRule`, defaulting to
`session/victory/rules/exclude_scenery.tres` — everyone except members of the
Godot group `scenery`, which `entity/blocker/blocker_entity.tscn` authors on
itself. `Entity` gains no field and learns nothing about victory; a group *is*
the engine's per-unit tag, and it is the same shape XCOM 2 (unit traits queried
by the mission objective) and Unreal (`AGameMode` owns match state, actors carry
`Tags`) landed on. **A null rule means everyone counts** — never a crash, never
a run that can no longer end.

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
  rule. Owner call 2026-08-22: the per-entity exception is *"a free consequence,
  not the justification"* — take it because a group read costs the same either
  way, but do not grow `ContestantRule` to anticipate a tutorial.

**A historical trap, still worth knowing:** Dormant Cores and AI opponents both sat
on `npc.tres` (`entity.gd`'s default faction, and what
`procgen_play_sandbox.gd` hands every AI participant). Under the old per-camp
flag, opting `npc.tres` out would have left one counting camp at spawn and ended
every run instantly — invisible to a hand-built two-camp test. Per-entity
membership removes that whole failure class: the handle is on the *scene*, not
on a resource other entities share.

### The sibling flag: `Faction.targeted_by_ai`

`blocker.tres` still authors `targeted_by_ai = false`, and it deliberately did
NOT follow contest membership off `Faction`. "Worth an NPC's AP" is genuinely
camp-level — you shoot at camps, not individuals. (A per-entity version reading
the same `scenery` group would be a drop-in, since `AiRecon` already resolves
the flag per owning entity, but that is its own decision.)

`targeted_by_ai` is filtered inside `AiRecon.visible_enemy_nodes()` — the one
chokepoint every NPC target list flows through (growth's directional bias, the
`saw_hostile` short-circuit, and ranged/magic/melee candidate enumeration all
consume what it returns). It is emphatically **not** expressed in
`Entity.attitude_to()`: a Dormant Core must stay `HOSTILE` so the *player* can clear
it and so damage, the forced-dealloc cascade and XP gating treat that as a real
kill. `test_ai_recon.gd` holds a guard test asserting the relation is still
HOSTILE, so relocating the filter into the attitude method goes red.

**Known consequence, deliberately unsolved:** an NPC whose only route out of
its region is through a Dormant Core will never clear it, and grows in place
forever. Placement (#477) samples uniformly at random over regular
nodes (only starters and keystones are excluded), so nothing structurally
prevents one landing on a cut vertex — this is possible, just unobserved
so far. The fix, if it's ever needed, is an AI-side "boxed in → treat them
as targets" fallback, not a change to this flag.

Side effect worth knowing: giving them their own faction id makes them
**hostile to the NPC camp** too, where before they were allied by sharing
`npc`. AI opponents can now target Dormant Cores.

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

`Events.game_over` is **gone** (#526). It went emitter-less when #517 moved the
run-end presentation onto `run_ended`, and #526 deleted it rather than leave a
dangling signal — along with `test_entity_death.gd`'s hand-emitted "regression
guard", which only ever exercised the HUD's own listener.

## The outcome has no point of view (#517)

`RunOutcome` names the winning camp and nothing else. There is no `local_result`
and no `local_camp` anywhere: a run has ONE winner and as many points of view as
there are machines watching it, so "did I lose" is a fact about a screen.

`HudRoot._on_run_ended` makes that reading, and makes it from `SeatPolicy`:

- **Banner** — camp-authored, always: `"%s wins!" % winning_camp.display_name`,
  tinted `winning_camp.color` (via `AnnouncementRequest.make_tinted`, not
  `make_for_entity` — there is no acting entity for it to go stale against). A
  camp with two living heroes announces once, as a camp, and plural phrasing for
  coop is an authoring choice in the faction `.tres`, not a code branch.
- **Overlay** — `RunEndOverlay`, raised on EVERY outcome since #526, because it
  carries the way out of the level. Seating decides its *copy*, never its
  visibility: `Seating.COUCH` reads `NEUTRAL` ("RUN OVER" — two rivals share one
  screen, so there is no camp for it to have lost from), `Seating.SEAT` reads
  `VICTORY`/`DEFEAT` from the seated hero's camp, and no winner at all reads
  `DRAW`. Gating visibility on the reading is what left a draw with a banner and
  no exit.

**Why seating and not the bound player.** `GameRoot.bind_player` set
`victory_system.local_camp = player.faction`, and `rebind_player` fires on every
hot-seat handover (#459) — so on a versus couch the banner resolved from
whichever rival acted last. Deriving it from `HudRoot._player` would have moved
the identical bug one layer down. Reading `_player` under SEAT specifically *is*
sound, because `follows_active_turn()` is false there and the bound hero never
re-points — including after it dies, which is why the overlay cannot be found by
walking `Entity.GROUP` (GameRoot pulls corpses out of it synchronously).

`HudRoot` binds the `GameRoot` and reads `seat_policy` at run-end time rather
than caching the policy: `game_root.gd` initialises a default couch and a roster
*replaces the object* during `_setup_level`, so a cached policy can be stale.

## What is deliberately not here

- **`GameSession`** is an autoload now (#457). It supplies the `RunConfig` whose
  `resolved_victory_condition()` GameRoot installs, and records the outcome as
  the run's terminal state. `VictoryContext` is still built by `VictorySystem`,
  not by the session — the conditions never changed shape when it landed.
- **A results screen** is out of scope (#461). The way out is
  `GameRoot.route_to_meta_now()` — one latched `SceneDirector.goto(META_ROOT)`
  with two callers (#526): the overlay's *to main menu* button, and
  `run_end_route_delay` as the fallback for a player who never presses it.
  `route_to_meta_on_run_end` vetoes both, so tooling does not teleport itself to
  the menu. The action row still appears under the veto, and the press then
  dismisses the overlay — both dev sandboxes set that export, and a permanent
  full-screen dim with a dead button over a level you were still poking at is
  worse than the banner-only run-end this replaced.
