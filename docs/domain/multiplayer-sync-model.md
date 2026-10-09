# The multiplayer sync model

**This page is the *how*. The *why* is
[ADR 0002](../adr/0002-host-authoritative-sync-not-lockstep.md)** — the decision,
the grounds it actually rests on, and every alternative with its dead arguments
marked as dead. **Read it before re-arguing this**: the call has already been
made three times, and three of the grounds it originally rested on are retired.

This is the architecture every networked and hot-seat feature hangs off. Read
this before touching input routing, `BattleSystem`'s launch path, or the AI
controller.

The game-design side of what a player is *allowed to know* lives in
[../design/info_gating.md](../design/info_gating.md); this doc covers the code
shape.

---

## The model

**Host-authoritative, intent-up / confirmed-command-down.**

One peer — the host — is the only thing that decides anything. A client sends an
*intent*. The host validates it, broadcasts the *confirmed command* plus a
resolved payload for anything the client cannot recompute, and **then** applies
it. Every peer, the host included, applies world changes through one applier,
through the same *post-confirmation* half of it, so the authority is not
structurally a mutation window ahead of everyone it is telling.

Single-player and hot-seat are not a special case: they run the same path
through a loopback transport. That is the whole point — if offline play works,
the networked path is already exercised.

```
click / AI decision
        │
        ▼
   Intent ──(transport)──▶ Host: validate → confirm ─────┐
                                              │          │
                                              ▼          │
                                         Host applies    │
                    (the same post-confirmation half     │
                     every peer runs — not a private     │
                      authority path, and not first)     │
        ┌────────────────────────────────────────────────┘
        ▼
  ConfirmedCommand (+ resolved payload) ──▶ CommandApplier (every peer)
                                                       │
                                                       ▼
                                            world mutation (synchronous)
                                                       │
                                                       ▼
                                            VFX — pure observer
```

The confirm sits **between** validate and apply, for every verb without
exception: `validate → apply → broadcast` would put the host a full mutation
window ahead of everyone it is telling.

---

## What the model rests on

Four properties of this codebase that the model is shaped around. Which of them
were *arguments* when the model was chosen, and which of those arguments have
since been retired, is
[ADR 0002](../adr/0002-host-authoritative-sync-not-lockstep.md).

1. **The mutation surface is ~9 verbs, not 863 lines.** `PlayerInputController`
   is mostly *local plan-building* — the armed-mode stack, hover, pin, the
   core-drag ghost, blade member toggling. None of that crosses a wire. What
   actually mutates the world is `allocate`, `deallocate`, `deallocate_set`,
   `stake`, `extract`, `move_core`, `launch_attack`,
   `apply_armed_temp_upgrade_to`, `end_turn`, plus loot picks. Every
   `AllocationSystem` entry point is synchronous, gated, `-> bool`, and takes
   `(node, entity)` — already wire-shaped once `SkillNode` becomes `stable_id`.

2. **Mutation is not entangled with animation.** The VFX call is un-awaited
   and mutation runs on its own `OutcomeApplier`/`BeatClock` loop, paced by
   authored `arrival_time` — see [presentation-clock.md](presentation-clock.md).
   VFX is a pure observer. `BattleSystem.is_launching` is the reentrancy guard.

3. **Combat is nearly RNG-free — but not entirely.** Initiative, allocation
   gating, mitigation, blade hit-scan and AI scoring are pure arithmetic. Two
   real exceptions:
   - `PropagationContext`'s crit RNG falls back to `crit_rng.randomize()` when
     none is injected.
   - `SkillDustAddon`'s global unseeded `Array.shuffle()`. **Not a hazard
     here:** the roll is host-only and its *result* is what crosses the wire, so
     there is nothing for a peer to reproduce — see
     [ADR 0013](../adr/0013-host-only-rolls-and-the-seed-is-a-procgen-input.md).

4. **AI is frame-shaped, but its mutations are commands.** `AIController` awaits
   `create_timer(turn_delay)` between decisions and submits every mutation
   through `_submit_and_wait`. Its *decisions* are deterministic; its *timing*
   is not, and that timing is host-local pacing with no sync meaning.

## The determinism obligation

**This model does not buy freedom from determinism; it bounds it.** Derived
stats are recomputed **locally on every peer** — nothing about `max_hp`, AP
regen, or any board total rides a record. So the stat pipeline must produce
identical results on every machine, and that obligation is real today.

**The obligation reaches exactly one subsystem: the stat pipeline** — which is
what makes it auditable with a grep.

Two rules follow, the stat-pipeline analogue of the stable hitscan sort:

- **No transcendentals in a value a peer recomputes.** `sqrt` is fine (IEEE
  requires it correctly rounded). `log` / `exp` / `pow` / `sin` / `cos` /
  `tan` / `atan` are not. The ban's reach is exactly the table above: the
  derived tier every peer computes for itself from replicated state — the
  stat pipeline, aura contributions, anything a resync does *not* carry. It
  does **not** reach a value a peer *receives*: attack and spell resolution
  ships as an `AttackRecord` (`attack/melee/sim/`, `attack/spell/propagation/`
  run on the authority's shadow world, and `apply_launch_command` on a peer
  is a deserialize, never a re-resolve), and the map ships as a
  `GraphSnapshot` (`procgen/`'s Gaussian bumps and Poisson rolls are real
  math that would be wrong to rewrite). Presentation is likewise exempt —
  `vision_system.gd`'s `exp` is a frame-rate ease inside `_process`, and every
  `skill_node/visuals/`, `entity/core/sigil/` and `graph/edge.gd` use is
  drawing.

  `mise run lint-transcendentals` enforces this and is deliberately coarser
  than the rule — it is path-based, so a new transcendental in a
  received-side file it does not yet list fails the lint. That is the door,
  not a bug: the allowlist entry you add carries the reason *and the
  condition under which the exemption ends* (`procgen/`'s voids the moment a
  peer generates its own map from the seed). Adding one is asserting that no
  peer re-derives this number and compares it to another peer's.
- **Bin aggregation must iterate in a stable, defined order.** Float addition is
  not associative, so summing the same modifiers in a different order gives
  different last bits. Godot 4 Dictionaries are insertion-ordered and insertion
  follows replicated command order, so this holds today — but it breaks silently
  the moment a bin is sorted by a float or moved into an unordered container.

`MeleeAttackPlan.resolve_against` is not a divergence risk:
`attack/melee/sim/blade_sim.gd` is a pure fixed-dt XPBD loop (no frame delta,
no RNG), `BladeHitScan` walks `trajectory.sample_dt`, and `ai_blade_rollout.gd`
runs `simulate()` on `WorkerThreadPool` because it is pure. A defensive spike pop
is decided per landing inside `BladeDamageInstance.land_on`, off
`BladePopResolver.LiveGate`, and rides the record as `h_pop` — **land-time**,
not resolve-stage. Order-dependence *inside* a deterministic function is not a
divergence source: given the same inputs every peer produces the same order and
set. The portability of the *inputs* is the separate problem — ground A of
[ADR 0002](../adr/0002-host-authoritative-sync-not-lockstep.md)'s lockstep
rejection, and the reason the blade is re-simulated only to draw it.

**Information decision: every client gets full world state; hiding is a UI
concern.** See [ADR 0015](../adr/0015-hidden-information-is-trusted-friends-until-a-competitive-release.md).

## The resync backstop

**Settled #521, built in #560 + #561. Additive under
[ADR 0002](../adr/0002-host-authoritative-sync-not-lockstep.md) — it reopens
nothing.** `AttackRecord` remains the only thing that mutates
a peer's live world during combat (`.claude/rules/attack-timeline.md`), and a
confirmed command remains the only thing that advances it. What the backstop
adds is a *repair*, for the one bug class the model above has no answer to at
all: the client's number crept wrong and nothing will ever notice.

**Two triggers, and there is deliberately no third.**

1. **Join.** A peer arriving mid-run receives the world rather than
   regenerating it — `GraphSnapshot` (#527) for the nodes, `EntitySnapshot`
   (#560) for the boards.
2. **A desync verdict.** `WorldSyncChannel._report_sync` finds the two fingerprints
   disagree, and the authority pushes the same pair as one `KIND_RESYNC`.

Both are one `WorldImage` (`network/world_image.gd`, ADR 0042): `capture` on the
authority, `apply` on the peer — which owns the apply order; the channel keeps only the wire flags.

**A green fingerprint is not a green join** (#715). The fold answers "do our two
worlds agree"; it can say YES for a client that decoded every node and never
takes a turn (its roster row still carries `LobbyScreen._PENDING_PEER_ID`, so no
hero is seated), and it covers neither tags nor effects. A join is proved by the
peer reaching its FIRST TURN — which is what
`MpHarness._announce_first_turn_for_rung_3` prints and what harness rung 3 reads
— never by the fingerprints matching at link-up.

The rejected third was a **periodic dirty-stat push** (#521 D2). A subscriber
across every board at 2000 nodes is the exact shape this repo has twice shipped
a quadratic of (`.claude/rules/graph.md`), and it buys a second,
constantly-firing repair path overlapping this one. It is parked on evidence —
a drift actually observed between resync points — not on principle, and it
wants a board-level batch rather than a per-stat subscriber if it ever lands.

**A verdict auto-resyncs AND shouts. Both halves are required** (#521 D3). The
repair runs so play continues; the verdict is still emitted on `sync_checked`,
still logged loudly through `logged`, and still a failure on the #529/#532
harness ladder. A silent auto-heal would retire the bug class **from the logs
rather than from the code**. The assertion that keeps this honest is the
negative one: *a green run never resyncs*.

**Only the authority sends state** (#521 D4). The verdict fires on whoever is
comparing, but a client that detects disagreement sends a `KIND_RESYNC_REQUEST`
and waits — it never reconstructs, because a peer repairing itself out of its
own wrong world is not a repair. The request is latched until the next boundary
agrees, so an unfixable divergence begs once, not once per command.

**A repair has no presentation semantics, and must never acquire any** (#521
D1). Nobody animates a repair: applying a resync submits no `Command`, so
nothing fires on `command_confirmed` (#525's camera director hangs off that one
and must not pan), no VFX plays and no `BeatClock` runs.

**It decodes into a POPULATED world, and that is the ordinary case** (#561 D6).
Every decoder reconciles rather than rebuilds: `GraphSnapshot.decode` updates a
node whose `stable_id` it already knows, mints only genuinely-new ids, removes
only genuinely-absent ones, and does the same edge by edge; `StatBoard.read_dict`
keeps an existing modifier whose wire form matches; `EntitySnapshot` skips a
grant already carried and moves each tag's refcount to the authority's. The
teardown-and-replay alternative was considered and **rejected**: freeing the
world would destroy a live entity's `initialize()` signal wiring, strand every
`EffectInstance` handle and `source_node`, and rebuild every navigator mirror —
all to repair a world that, in the overwhelming case, differs from the
authority's in one number. Reconciling is also what makes the no-animation
guarantee real, because a world that never drifted comes out untouched.

**Reconcile means removal too, and that is what join never needed.** A joining
peer decodes into an empty world, so every decoder only ever had to *add*. A
repair has to be able to subtract: a node, an edge, a modifier or an entity that
the authority does not have is drift, and it comes off. Entity removal here is
emphatically not `Entity.die()` — no `entity_dying`, no loot, no victory check.
The entity was never supposed to be there, so nothing about its leaving is an
event anyone should see. Tags reconcile to the authority's **refcount**, not
merely to its name set, for the same reason: a marker applied twice and removed
once is still active, and a repair that restored names only would be the thing
that broke it.

**An entity the payload names but the peer lacks is spawned by a callback.** A
row whose entity is absent asks the optional `spawner`
(`WorldSyncChannel.entity_spawner` → `EntityFactory.spawn_snapshot_entity`,
which refuses anything that is not a blocker): the client runs no procgen, and
procgen spawns ~120 entities the roster never names (one per removable blocker).
The `entity_id` is the AUTHORITY's, read off the row and stamped before the
entity enters `entities_container` (`Graph._mint_entity_id` assigns only where
the id is still `0`), so this is not a second minting path; it is the mirror of
`_prune_entities`. A callback rather than an `instantiate()` inside the
snapshot because a blocker's `EntityStatBoard` is assigned per tier in code and
refuses a stat it has no field for. See `EntitySnapshot._materialize`.

A materialized blocker's **spellbook crosses by value**. The host's is a
`SpellBook.duplicate_pruned` slice — a `SpellBook.new()` with no
`resource_path`, so the intern table has nothing to carry, and the client that
runs no procgen cannot re-derive which slice was kept. The row therefore also
carries the kept `SpellDef.id`s (`EntitySnapshot._encode_spell_ids`), `null` for
any book that does have a path, and `[]` distinct from `null` because the prune
chain may legitimately run to empty. This is the *received* side of the
determinism rule, not the recomputed one: ids resolve through
`SpellCatalog.by_id` and nothing is re-rolled.

The by-value list is what carries **every** spellbook, not only a pruned one:
`Entity._ready` deep-copies whatever book it was handed so no two entities share
the authored resource object, and a `duplicate` has no `resource_path` — so
`_R_SPELLBOOK`'s interned path has always been -1 for a live entity. The rebuilt
book holds the const defs `SpellCatalog.by_id` returns rather than copies of
them, which is what `SpellDef` identity comparisons (#511) need. The ids
themselves are interned into a `spells` table beside `res`, separate from it
because a `SpellDef.id` is a wire name and not a path `_load_interned` may
`load()`.

**The rebuild is a no-op when the membership already agrees**, and that guard is
the same trap as `_on_resync`'s: *a repeat decode must change nothing it has
already changed.* A rebuilt book carries no `SpellBook._sources`, which is right
for a blocker's loot pool and wrong for a hero on the second application — pass 2
does not put the sources back, because `_grant_effects` skips a `SpellGrant`
whose `EffectInstance` is already in the ledger, so the spell would sit in
`spells` with nothing behind it and the next `revoke_effects_from` would find no
source to drop. "Is this step idempotent?" is a standing question for anything added to either
decode pass: neither the fold nor a passing round-trip can see a step that
quietly did its work twice.

**A resync carries the turn cursor** (#756): `TurnManager.current_entity` (as an
`entity_id`, 0 for none), `TurnManager.turns_taken`, and each
`Entity.turns_taken`. It has to — a peer whose world was encoded *after* the host
opened its first turn heard none of the `turn_started` emits that produced it,
and cannot reproduce either number. The receiver `adopt_turn`s the cursor rather
than `start_turn`ing it: the payload already holds the results of that turn's
upkeep, so re-running it would apply it twice. It also **reconciles every
`EntityNavigator`** against the ownership the decode just wrote directly, which
is the one mirror `GraphSnapshot`'s bypass of `AllocationSystem` invalidates.

**What a resync does NOT carry** is the derived tier — `StatBoard` totals,
`Stat.bins`, aura contributions, vision. The receiver recomputes, exactly as
`GraphSnapshot`'s tier table says. A backstop that shipped derived state would
be asserting agreement on quantities the sync layer deliberately never
transmits.

## What crosses the wire, per action

| Action | Up (intent) | Down (confirmed) | Why |
|---|---|---|---|
| allocate / deallocate / deallocate_set / stake / extract / move_core | the command | the same command, nothing more | Fully deterministic, no RNG — every peer re-applies it identically |
| launch attack | the plan: mode, pivot + blade member `stable_id`s, or target + spell (`AttackPlan.to_dict`) | the same command **plus `AttackRecord`**, a post-apply record of what each landing actually did, stamped by `BattleSystem` during application (#511) | Resolution runs on a shadow, but the swing sim is order-dependent and crits roll. Clients reconstruct the recorded effects and replay VFX; they never re-simulate and never re-derive a number |
| loot pick / relic roll | the pick intent | the resolved result | The host rolls; the shuffles stay host-only |
| end turn | the command | the command | The host's `TurnManager` is the clock, so `_tick_until_ready`'s group-order tiebreak stops being a hazard |
| **start turn** (the run's first, and only the first) | — (the authority raises it) | `StartTurnCommand` — the actor, nothing else | The bookend to `end turn`, and it exists for the same reason (#756). Who the clock opens on is a host DECISION; until this command every peer opened on *its own* seated hero, and every later `end_turn` reproduced `_tick_until_ready` from a different cursor. Later turns are handed on by `end_turn` and never by this — the applier refuses one while `current_entity` is non-null |
| *(every action above, on a client)* | `KIND_INTENT` — the command dict, carrying the `intent_id` **the client minted** (#548) | nothing extra; the confirm is the ordinary `KIND_COMMAND` row above, echoing that same `intent_id` back verbatim | The client has to match a returning confirmation to the intent it sent, or `is_awaiting_confirmation` never closes. The host must **never re-mint**: a received intent goes through the same `submit()` as a local one, and `submit()` mints only when the id is absent |
| *(any of the above, refused by the host's gate)* | — | `KIND_REFUSAL` — `{intent_id, reason}`, `reason` a `StringName` code and never a UI string (#548) | A refused command never confirms, so nothing crosses on the ordinary leg — and a client waiting on a confirmation that will never arrive is the failure mode this channel most needs to not ship. Its own kind rather than an echoed command with a `refused` flag, so the fingerprint compare and the determinism probe keep one uncomplicated path. There is deliberately **no timeout, retry or heartbeat** for a confirm that is simply lost: ENet's reliable-ordered channel is the guarantee, and a LAN desync is a restart |

**Loot is rolled host-side and only the pick travels.** The candidate list is
already known to whoever received the request, so the pick command carries
`(entity_id, request_id, chosen_indices)` and nothing more (#509).

The roll itself stays host-side and is not reproduced anywhere, which is why the
loot and skill-dust `Array.shuffle()` calls need no seeded RNG —
[ADR 0013](../adr/0013-host-only-rolls-and-the-seed-is-a-procgen-input.md), which
supersedes the earlier reading that they were a per-client divergence hazard.

### The lobby roster, at the same model and a different scope (#714)

The roster replicates *before* a level exists, and it does it with the model
above rather than beside it. Two kinds, and they are the exact inverse of each
other:

| | Kind | Payload | Gate |
|---|---|---|---|
| Up | `KIND_LOBBY_PICK` | `{id, peer_id, …changed fields}` — one seat, only what moved, in `Participant.to_dict`'s encoding (a `Faction` / `CoreClass` as its `resource_path`, never a reference) | `Role.CLIENT` sends, `Role.HOST` receives |
| Down | `KIND_LOBBY` | `roster.to_dict()`, the **whole** authoritative roster | `Role.HOST` sends, `Role.CLIENT` applies |

Whole-roster rather than a delta: it is a handful of rows, and a delta protocol
would buy an ordering problem a lobby does not have.

**A refusal is not a message.** The host answers *every* pick with its roster,
accepted or not, so a client that asked for a colour somebody already holds
converges on the truth without a second leg. There is no local
pre-application — the same "no prediction" call #548 made for the world.

**One rule set, because a remote pick goes through the local writers.**
`LobbyScreen._on_remote_pick` validates the seat and then calls
`_on_color_picked` / `_on_core_class_picked` / `_on_camp_picked`, so colour
uniqueness (`LobbyScreen.taken_colors` — the same call that greys a chip out in
the picker) and the `LobbyPolicy` START veto apply to a client's pick without
either being restated for the wire.

**Why not `KIND_SETUP`.** That envelope carries a `RunConfig` too, and its
receiver hands both to `GameSession.apply_received`, which asserts the seed is
already resolved and **opens a run**. A lobby's seed is still the `0` sentinel
until START. Relaxing that assertion to save a constant would trade a
load-bearing gate for nothing; `KIND_LOBBY` touches `GameSession` not at all.

**START is where `KIND_SETUP` goes out, from the lobby.** A *pre-established*
link never fires `NetworkTransport.peer_joined` again, so setup cannot hang off
join (the level would wait out `SceneDirector.REVEAL_TIMEOUT_S`).
`LobbyScreen._on_run_started` broadcasts the
settled `RunConfig` + `ParticipantRoster` off `GameSession.run_started`: the
HOST reaches that signal because the shell called `GameSession.start` on what
START emitted (which is also what resolved the seed the sentinel gate above
demands), and the JOINER reaches it because `apply_received` re-emitted it. One
signal, both machines, and each releases its lobby link there before routing —
`Wire` admits exactly one bound `EnetTransport` facade (`Wire.claim_binder`),
because two would re-emit every packet and the world would silently drift.

**Who may edit what.** A human seat is editable by the machine it sits at
(`Participant.is_local`, #562's one home for "which of these is me"); an AI seat
belongs to whoever authors the roster, which is everyone except a client. The
rule is symmetric — the host does not dress the joiner's hero either — and it is
enforced twice on purpose: in the UI (`ParticipantRow.set_editable`) so a player
sees it, and on the host against the *roster* (`LobbyScreen.may_edit_remotely`)
so a payload cannot claim it.

**The lobby mounts its own `NetworkTransport` + `NetworkLink` pair (with a
`LobbyChannel`), and never opens the socket.** `meta_root._push_lobby` is the one place that decides a
route opens a link — the same file that already decides which `NetworkConfig` a
route leaves on `GameSession` — so a lobby with no live `Wire` behind it mounts
nothing and is byte-for-byte the offline lobby. The screen hands its link back
at START (`release_link`), leaving the socket up for the level to adopt (#713).

**Mass actions are one atomic command, never N.** `deallocate_set` and
mass-allocate paths serialize as a single command with a node list — splitting
them would let a peer observe an intermediate state that never legally existed.

---

### A seat handed to the AI, and why fog forced it onto the wire (#755)

A seated peer dropping mid-run is not a rejoinable state (#733, owner call), so
the host hands its hero to the AI — `SeatHandover.hand_seat_to_ai`. That used to be
entirely host-local. It is now split, and the split is the interesting part:

| | Who runs it | What |
|---|---|---|
| Shared | **every** peer, `SeatHandover._adopt` | `Participant.kind = AI`, `Entity.is_human_controlled = false`, emit `seat_handed_over` — the level re-runs `_apply_seat_vision()` and raises the banner |
| Authority | host only, `hand_seat_to_ai` | broadcast `KIND_SEAT_HANDOVER`, swap `PlayerController` → `AIController` (`ControllerFactory.replace_with_ai`), kick the turn if it is this hero's |

**The argument is fog, not the banner.** When this was settled,
`SeatPolicy.vision_group` was an *allied-humans* reveal keyed on
`Entity.is_human_controlled` (it is now camp-mates by `faction.id`, AI
included — `seat-policy.md`; the rule below still binds any per-machine view
fed by seat state). With the flip host-local, a coop ally on a **third** machine kept
revealing through a hero the host had already stopped revealing through — two
machines drawing different maps of the same authoritative world. No fingerprint
can see it: `is_human_controlled` is carried by neither `WorldFingerprint` nor
`EntitySnapshot`, which is also why the handover is a plain message and not a
`Command`. There is nothing to validate and nothing that may refuse it (the peer
is *already gone*), and a gate with no gate behind it is only a way for the
mirrors to disagree.

**The controller swap must stay host-only.** A mirror that grew an
`AIController` would be a second machine deciding actions for a hero it has no
authority over — this document's first rule, broken in one line. The mirror
leaves the now-inert `PlayerController` where it is.
`test_a_mirror_applies_the_handover_without_growing_a_controller` is that
regression.

**Ordering.** The broadcast goes out *before* `ai.take_turn()`. The wire is
reliable-ordered, so sequencing the handover ahead of the AI's first command is
what stops a mirror seeing an AI act on a seat it still believes a human holds.

**Deferred during a join** (`SeatHandover`'s `deferred_until_world`): it names a seat by
`Participant.id` and a peer mid-join has no entities to resolve one against.
Nothing is lost — the `KIND_SETUP` it is joining on carries the host's roster as
it stands *now*, seat already AI. Its banner drops with it, correctly: it
announces something that happened before that peer was in the room.

## Where each subsystem sits

**AI runs on the host only and emits commands into the same queue** (via
`AIController._submit_and_wait`). `turn_delay` is host-local pacing with no sync
meaning, and clients see an AI turn as an ordinary confirmed-command stream.

**Fog is a view concern**, computed per-client from state that client already
holds. The authority does not own fog. #459's camp-wide `VisionSystem.viewers`
becomes "my camp" on each client. Fog gains authority meaning only under the
deferred filtered-delta model, where the host uses it to decide what to send.

**The applier is `command/command_applier.gd` (#510).** One serial, **async**
queue: `submit(cmd)` enqueues, and drains only if no drain is running. Three
guards exist and are nested, answering different questions —
`BattleSystem.is_launching` ("an attack is in flight", owning the plan's
lifetime across mutation *and* VFX), `CommandApplier.is_applying` ("a command
is being applied", covering every verb), and since #541
`CommandApplier.is_awaiting_confirmation` ("something is submitted and the
authority has not decided", the phase *before* either of the others — the world
has not moved at all). `PlayerInputController.can_player_act()` reads **all
three**, off one refresh route. Outcomes come back as `command_applied(cmd, success)`, emitted
*inside* the guard so a fallback handler that submits — the deallocate →
cascade-offer path — queues rather than re-entering; `applying_changed` fires
*after* the flag clears, matching `is_launching`'s deliberate ordering.

**`command_confirmed(cmd)` is the mirror seam, and it is not `command_applied`.**
Application spans more than mutation: `BattleSystem._commit` keeps awaiting
`_vfx_finished` after the world has settled, because `is_launching` owns the
plan's lifetime through the swing. Mirroring off `command_applied` would
make a peer wait out the *host's animation* before starting its own. `_drain`
confirms at the flip point instead, and `CommandChannel` broadcasts off that.

**`_drain` is `validate → confirm → apply` for every verb without exception.**
`CommandApplier._validate` forwards to the same `can_*` queries the mutating
verbs ask themselves, so "validated" already means "will apply" and the host
never has to finish mutating before it can tell anyone. `LaunchAttackCommand`'s
`AttackRecord` is computed in `BattleSystem.prepare_launch_command()`, which
`_validate` calls — legal because resolution is shadow-only.

**One consequence worth naming: `_validate` is not side-effect-free.** For the
attack it *produces the payload it is gating on* — the gate is "resolve, then
check the attacker can afford what came out", and the resolution is the record.
Nothing real moves (a `CombatWorld.shadow()`), but read `_validate` as "the
command is final and legal, or it is refused", not as a pure query.

**The pending phase is zero-length locally for every verb, and that is not a
reason to delete it (#541).** `submit` drains synchronously down to `_validate`,
so on a peer that *decides*, `is_awaiting_confirmation` is true for a stack
frame; it becomes the round trip only once #463 routes a client's intent upward.
The attack's resolve happens inside the validate the flag closes on, so its
window is a stack frame too. It is derived —
"queued, or popped and not yet confirmed" — rather than assigned, because a
`command_applied` handler that submits opens a fresh window one line before the
outgoing command closes one. The flag is raised in `submit` *ahead of* the
`is_applying` bail, which is the one moment the third gate is the sole reason the
player cannot act, and is what `test_command_routing.gd` asserts against.

`confirm` is idempotent and only ever called for a command that is going ahead —
which is where "a refused command changed nothing, so mirror nothing" now lives.
Ordering across commands is untouched: the queue is serial, so a mid-apply
confirm still lands between its neighbours'.

Every `PlayerInputController` mutation, `battle_system.launch_attack` (builds a
`LaunchAttackCommand`, submits it, and parks on `applying_changed`, so every
caller awaits the whole action), loot (a `LootRoundCommand` per round of a
relic's claim, minted only once that round's outcome is known; see "The loot
round is the deliberate exception" below) and the AI (`_submit_and_wait`) go
through the applier.

`PickLootCommand` is answered against `LootPickRegistry`, which mints
`request_id` (a per-process counter would hand the same id to different requests
on two peers).

**Why loot's wire unit is the ROUND, not the pick.** Two of `SkillDustAddon`'s
grant paths never raise a pick — the single-cycle-safe-survivor auto-grant and
the NPC / headless auto-resolve. Recording the round covers all three uniformly;
the human pick is just the one with latency in the middle. The round also
carries the five distinct ways a relic's chain can END, as one `finished`
record, which is what frees the peer's relic.

**Loot candidates travel BY VALUE** — `{stat_id, operation, value, priority}`
plus a typed `formula` block, recursively for a `CompositeStatModifier`
(`StatModifierCodec`). Pointing at shared state with a locator was considered
and rejected: only `_node_grant_modifiers` is derivable from the shared seed —
`_core_modifiers` and `_innate_modifiers` read the VICTIM's own board, which a
peer holds partially, stale, or not at all, so an index into it is a silent
mis-grant rather than a loud failure. By-value also carries a `StatFormula`,
which #323 requires: stealing a level-scaler is the intended roguelite loop.
`LootSystem._draw_payload` already minted detached copies, so this is that same
operation with a different target.

**Identifiers.** `SkillNode.stable_id` and `Entity.entity_id` are the only
legal references on the wire. Both are minted by `Graph` — `entity_id` eagerly
on entry to `entities_container`, resolved with `Graph.get_by_entity_id` (#509).
Under host authority that means *the host's* `Graph` decides; if peers assign
their own, two clients disagree about which entity a command targets.

**Transport.** A `NetworkTransport` seam with `LoopbackTransport` (the default —
single-player and hot-seat) and `EnetTransport`. ENet is chosen because it is
built into Godot and zero-config on a LAN, **not** because it is the only
option: `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer`, and raw
`PacketPeerUDP` / `StreamPeerTCP` all exist. The transport choice is close to
free and reversible behind the seam. Lobby: type-an-IP.

**One command type, two states (#511).** `LaunchAttackCommand` is the only
asymmetric verb in the vocabulary, and that is deliberate. An EMPTY `record`
means *initiate*: nobody has computed this attack yet, so the authority stamps
the seed, resolves on a shadow, gates on affordability, and stamps the record it
produced onto the same object — all inside `_validate`, so `CommandChannel` (which
encodes on `command_confirmed`) broadcasts a complete record before anything
local has moved. A POPULATED `record` means *replay*: rebuild the plan (for the
animation only) and the recorded deltas (for the world), and land them through
the same `OutcomeApplier` on the same `BeatClock`. Two types would need the
receiver to know its own role to refuse the wrong one; one type whose payload
says which half of the work is already done needs no role at all — and a client's
intent IS this command with an empty record.

The authority *also* reaches the apply with a populated record — it replays its
own, exactly as a peer does — so `record.is_empty()` does not distinguish "did I
compute this". The transient `computed_here` field does, and
it is deliberately absent from the wire: a received command is by definition one
this machine did not compute.

**The loot round is the deliberate exception to "one type, two states" — and it
honours the same underlying invariant: the command must be complete before it
reaches the confirm flip point.** `LaunchAttackCommand` satisfies that by
computing *earlier, inside* the pipeline (`prepare_launch_command` resolves on a
shadow from within `_validate`). `LootRoundCommand` satisfies it by being minted
*later, outside* the pipeline: the offer/pick/roll sequence runs to completion
first, and the command's constructor takes the outcome, so one cannot exist
before it is decided. A round stamped inside `_apply` would broadcast an EMPTY
`resolved` (a peer reads that as an unstamped initiate and rolls its own
divergent loot), and the validate-lift is unavailable because a round with a
human collector can *await a pick* and would freeze the host's serial queue on a
remote click. The next verb with a human in the middle gets this treatment;
`Command.confirms_before_apply()` does not exist and is not coming back.

Two downward messages carry what one command would otherwise:

* A `LootPickOffer` — NOT a `Command` — carries "show this collector a pick
  screen, here is the draw" when a round needs a REMOTE human. It mutates
  nothing and never touches `CommandApplier._drain`; `LootOfferChannel` sends it
  off `LootPickRegistry.offer_parked` as its own additive wire kind
  (`KIND_LOOT_OFFER`), the shape of `KIND_SNAPSHOT` / `KIND_SETUP`.
* `LootRoundCommand` is ALWAYS a replay, on every peer including the authority:
  the grant lives in the shared apply/replay path
  (`LootRoundCommandHandler._land`), so the authority does not double-grant.
  `PickLootCommand` remains the upward intent, answering a `LootPickOffer`.

The offer/pick/roll sequence runs OUTSIDE the command queue, between rounds, so
`CommandApplier.is_applying` does not imply "a pick is outstanding";
`CommandApplier.has_outstanding_loot()` is the explicit gate (see
`PlayerInputController.can_player_act()`).

**A peer re-simulates to DRAW, never to derive.** Melee reforms a bit-identical
blade from the plan (`blade_sim.gd` is a pure fixed-dt XPBD loop, no frame
delta, no RNG) so the swing animates; the damage it shows comes off the record.
That is not the re-simulation this model forbids — nothing is mutated and no
number is computed. `docs/domain/attack-timeline.md`'s land-time re-read
contract is host-side only.

**Payload size.** Most commands are a few dozen bytes. **The attack record is
the outlier and magic is its worst case:** a propagating spell authors its own
hop budget and revisit allowance, and the tuned ones are generous enough that a
single cast can genuinely produce on the order of ~100 landings, each carrying a
post-mitigation amount plus its crit/gate flags. That is kilobytes, not
hundreds of bytes — still a trivial one-shot burst on a LAN, but it is why the
record encodes as **parallel arrays of scalars with the timeline holding
indices into the flat hit list**, not ~100 dictionaries with string keys. The
indices are required for correctness anyway (a `PropagationEvent`'s hits are
shared references into `AttackOutcome.hits`, never copies); the size just makes
the same encoding the obvious one.

---

## Explicitly out of scope

- Fog-filtered state deltas and any `StatBoard` wire format.
- Reconnect of a dropped seat: the host hands it to the AI (`SeatHandover`).
  Save/load and desync repair are the join image and the resync backstop above
  ([ADR 0042](../adr/0042-a-save-is-the-join-world-written-to-disk.md)).

---

## Traps

- **Never frame-order a mutation** — never let animation completion, a
  dropped frame, or wall-clock timing decide *when* the world changes. That
  is the bug this design exists to prevent. This is narrower than "never
  mutate inside an await": `OutcomeApplier.apply` awaits a fixed logical
  `BeatClock` between landings (#504, design B) and that's fine — the
  interval is authored, not animation-derived, and nothing else can act
  inside the window. VFX observes; it never mutates and never gates a
  mutation on its own progress. See docs/domain/presentation-clock.md.
- **Never put a `SkillNode` or `Entity` reference in a command.** `stable_id`
  and the entity id only. And read a node's id with `Graph.get_stable_id(node)`,
  never `node.stable_id` — node ids mint **lazily** (unlike `entity_id`), so a
  container-added or hand-authored node reads `0` until something forces a
  topology rebuild, and a command carrying `0` resolves to nothing, silently.
- **A command raised during another command's application queues, never
  re-enters.** This is the bug class that eats a week; the guard ships on day
  one, not as a hardening pass.
- **Combat reproducibility is the per-attack seed stamp, not a run-level
  stream.** `launch_attack` stamps `attack_plan.resolve_seed` before resolving
  and `outcome.resolve_seed` carries it back out ; that stamp rides
  down with the outcome. Loot rolls are
  **host-only** and need no determinism guarantee at all — their unseeded
  `Array.shuffle()` calls are not a hazard under this model.

  **The seed is a procgen input, not a cross-peer or combat contract**
  ([ADR 0013](../adr/0013-host-only-rolls-and-the-seed-is-a-procgen-input.md)).
  Only the host generates; a joining client receives the authority's serialized
  graph and never runs `GraphProcgen`. Where `.claude/rules/game-session.md`
  reads "the map is reproduced by each peer from the seed", read: **the map is
  SHIPPED** — which takes `procgen/`'s transcendentals off the cross-peer path.

- **Still never roll from a null RNG on anything a peer must reproduce.** The
  narrower rule that survives: if a result crosses the wire as something a peer
  re-derives rather than receives, it draws from the seed it was handed. What
  changed is the *scope* — host-only rolls (loot, relics) are exempt, because
  nothing re-derives them.
