# The multiplayer sync model

**Decided 2026-08-18 in #473. Re-opened by the owner 2026-08-22, measured by
#529, and re-decided unchanged on 2026-08-24** — the conclusion held, every
argument for it was replaced. See `### Rejected: lockstep on the shared seed`
before re-arguing this: three of the grounds that section used to rest on are
dead, and picking one up is how this gets re-litigated for a fourth time.

This is the architecture every networked and hot-seat feature hangs off. It
also rewrites what #458 (`CommandBus`) and #463 (versus) are for. Read this before touching input routing, `BattleSystem`'s
launch path, or the AI controller.

The game-design side of what a player is *allowed to know* lives in
[../design/info_gating.md](../design/info_gating.md); this doc covers the code
shape.

---

## The decision

**Host-authoritative, intent-up / confirmed-command-down.**

One peer — the host — is the only thing that decides anything. A client sends an
*intent*. The host validates it, broadcasts the *confirmed command* plus a
resolved payload for anything the client cannot recompute, and **then** applies
it. Every peer, the host included, applies world changes through one applier —
and since #540 through the same *post-confirmation* half of it, so the authority
is not structurally a mutation window ahead of everyone it is telling (#534).

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
exception — that is #540, finished by #545. `validate → apply → broadcast` is
what this diagram used to say and is the shape #534 was filed to delete: it put
the host a full mutation window ahead of everyone it was telling.

---

## Why, and why not the alternatives

### Four facts about this codebase that decided it

1. **The mutation surface is ~9 verbs, not 863 lines.** `PlayerInputController`
   is mostly *local plan-building* — the armed-mode stack, hover, pin, the
   core-drag ghost, blade member toggling. None of that crosses a wire. What
   actually mutates the world is `allocate`, `deallocate`, `deallocate_set`,
   `stake`, `extract`, `move_core`, `launch_attack`,
   `apply_armed_temp_upgrade_to`, `end_turn`, plus loot picks. Every
   `AllocationSystem` entry point is synchronous, gated, `-> bool`, and takes
   `(node, entity)` — already wire-shaped once `SkillNode` becomes `stable_id`.

2. **Mutation used to be entangled with animation; #504 fixed that
   specifically, and the fix is required under *every* model.** Before design
   B, `BattleSystem.launch_attack` resolved a pure `AttackOutcome` but landed
   damage *inside* `await attack_vfx.play(...)` / `await melee_preview.launch(...)`,
   so the authoritative world change happened at animation time, ordered by
   frames — exactly what lockstep, host authority, and state diff all forbid.
   As of #504 the VFX call is un-awaited and mutation runs on its own
   `OutcomeApplier`/`BeatClock` loop, paced by authored `arrival_time`, not by
   animation completion — see docs/domain/presentation-clock.md. VFX is now a
   pure observer in fact, not just in intent, which is what this section's
   architecture assumed all along. `BattleSystem.is_launching` is already the
   reentrancy guard #458 asked for.

3. **Combat is nearly RNG-free — but not entirely.** Initiative, allocation
   gating, mitigation, blade hit-scan and AI scoring are pure arithmetic. Three
   real exceptions:
   - `attack/spell/propagation/propagation_context.gd:47-55` — crit RNG falls
     back to `crit_rng.randomize()` when none is injected.
   - `systems/loot_system.gd:335,449,461` and
     `skill_node/addons/skill_dust_addon.gd:173` — global unseeded
     `Array.shuffle()`. **Not a hazard under the chosen model** (owner call
     2026-08-21, below): the roll is host-only and its *result* is what crosses
     the wire, so there is nothing for a peer to reproduce. It was a hazard
     under lockstep, which is why it is listed here — see the rejection below.
   - `attack/spell/propagation/step/random_pick_step.gd:24-26` — same null-RNG
     fallback.

4. **AI is frame-shaped and calls systems directly.**
   `entity/controller/ai_controller.gd:70,85,124` awaits
   `create_timer(turn_delay)` between decisions, then calls
   `allocation_system.allocate()` / `battle_system.launch_attack()` straight.
   Its *decisions* are deterministic; its *timing* is not.

### Rejected: lockstep on the shared seed

**Re-opened by the owner 2026-08-22, measured by #529, and rejected again
2026-08-24 — on entirely different grounds.** The conclusion did not move; every
premise did. If you are about to re-litigate this, read which arguments are dead
before picking one up.

> **Owner call 2026-08-24:** *"getting that whole list of things cross platform
> deterministic would take more time than i'd now want to spend on that, this
> game doesn't do that much crazy stuff, nor a lot of commands (1 at a time with
> massive margins before and after mostly)"* — and, on a mixed lobby being
> likely: *"Yes — Windows/Linux mix likely."*

#### The three original grounds are all retired. Do not re-use them.

1. **"There is no authority at all."** Aimed at *pure P2P* lockstep. What was
   actually proposed on 2026-08-22 was **lockstep + snapshot recovery with the
   host still refereeing**, so an authority survives. Dead.
2. **The unseeded `Array.shuffle()` calls.** Host-only rolls are exempt and the
   pick travels as a result (owner call 2026-08-21, above). Dead.
3. **Hidden information / fog.** **Withdrawn by the owner**, on the record, in
   #463's 2026-08-24 decision comment: the fog vision withholds *derived*
   state, which is compatible with full replication of tiers 1-2. Dead **as
   stated** — but see ground B below, which is a different claim aimed at a
   different layer, not this one coming back.

#### What #529 actually measured, and what it did not

Two clean sweeps (773 commands, then 478 at `bc24e31`), zero divergences. That
is real, and it is **narrower than it reads**:

- The **RESOLVE** column answers "is the plan+seed resolution reproducible" —
  the half a confirmed record was never needed for.
- The **LAND** column (added 2026-08-24) answers the half lockstep would stand
  on: post-mitigation damage, HP bars, `h_hpm`, the gated bit, forced-dealloc
  cascades. It also came back clean — 30 ok, 0 diverged, 84 landings.
- **Both were taken on one machine, one binary, one libm.** They measure
  *pipeline order*, not floating-point portability. The question that decides
  this model cannot be asked on a single machine, which is why a clean probe
  did not carry the decision.

#### The live grounds

**A. Cross-platform libm, and it is unfixable by discipline.**
IEEE 754 specifies `+ - * / sqrt` to be correctly rounded. It specifies
**nothing** about `sin` / `cos` / `tan` / `exp` / `log` / `pow` — every
platform's libm ships its own approximation and they disagree in the last bits.
`attack/melee/sim/blade_arc_driver.gd` uses both (`Vector2.from_angle` at :38,
`cos` at :42), the XPBD sim integrates those positions over dozens of substeps,
and the hitscan sorts by the result. A 1-ulp difference flips two hits' order.

Under record-down that is **cosmetic**: a peer re-simulates the blade only to
*draw* it, and every damage number and the hit set itself come off the
`AttackRecord`. Under lockstep the same ulp decides **who gets hit**. Same code,
same rounding, one is invisible and the other is a desync — and no amount of
care in gameplay code prevents it. Only fixed-point or deleting the trig would,
and neither is worth a LAN date.

**B. Lockstep is contradictory with partial information — not merely awkward.**
This is *not* ground 3 returning. Ground 3 was about replicating tiers 1-2 and
was correctly withdrawn. This is about **inputs**.

Lockstep's defining property is that every peer derives the same result from the
same inputs. Deny a peer an input and it cannot derive. The owner's own
health-bar case is the proof:

> **Owner, 2026-08-24:** *"health bars of damaged nodes which are persistently
> shown and have a current + max ... max is a derivation of the entity stats x
> node-local stats, which **is information you might not have** yet these should
> not be question marks but real and correct values"*

That asks for an **output** while denying its **inputs**. There is exactly one
way that works: someone else computes it and hands you the number. That is
record-down's normal case and lockstep's impossibility.

The smell inverts too. Under record-down the received value **is** the model on
that peer — there is no locally-computed truth for it to disagree with, so no
`shown_health` beside `health`. You only get that second variable if you go
lockstep and then bolt fog on top.

**C. Lockstep's two claimed benefits were already harvested here.**
The 2026-08-22 pitch offered "the VFX-duration lag disappears outright" and
"total host/client code symmetry". Both landed **inside this model** the next
day: #540 moved the confirm to the validate->apply flip point and `CommandLink`
broadcasts off `command_confirmed`; #536 collapsed `BattleSystem` and #545 made
the authority replay its own record exactly as a peer does. What remains on
lockstep's side of the ledger is **wire size** — kilobytes, on a LAN.

It is also **slower for the acting client**, which inverts the usual intuition.
The host must resolve under both models (affordability gating needs
`outcome.ap_cost`, which comes out of the resolve), so lockstep does not save
the crunch — it duplicates it, once per peer, serially from the client's point
of view. Record-down replaces the client's re-resolve with a deserialize of a
few packed arrays: microseconds against milliseconds.

**D. It enlarges the determinism surface from one subsystem to everything.**
See the section below — this is the ground most likely to be forgotten, because
it is about the code that has not been written yet.

### The determinism obligation that survives — both models owed it

**Record-down does not buy freedom from determinism; it bounds it.** Derived
stats are recomputed **locally on every peer** under this model — nothing about
`max_hp`, mana regen, or any board total rides a record. So the stat pipeline
must produce identical results on every machine, and that obligation is real
today.

| model | what must be cross-platform deterministic |
|---|---|
| lockstep | stat pipeline **+** combat resolution **+** the XPBD blade sim + hitscan order **+** every crit roll **+** every future gameplay formula |
| **record-down (chosen)** | the stat pipeline |

The chosen model keeps the obligation inside one subsystem that can be audited
with a grep. As of 2026-08-24 that audit returns exactly one live hit: **#547**,
`floor(log(INT)/log(10.0))` in `entity/default_entity_board.tres:179`, which is
already wrong at INT 1000 on glibc (returns 2, should be 3) and libm-dependent
at every power of ten.

Two rules follow, and they are the stat-pipeline analogue of #530's stable
hitscan sort:

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
  drawing. (Narrowed 2026-09-03, #706: the old wording said "gameplay code
  path", which was broader than its own rationale — Cyclone's angular sort
  keeps its cross-product pseudo-angle because it is *cheaper* than `atan2`,
  not because a rule forbids the alternative.)

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

`MeleeAttackPlan.resolve()` itself is **not** the blocker it looks like, and
this was true under either model. `attack/melee/sim/blade_sim.gd:28-31` is a
pure fixed-dt XPBD loop (`steps = ceil(duration/dt)`, `t = float(step)*dt`) with
no frame delta and no RNG; `blade_hit_scan.gd:35` walks
`trajectory.sample_dt`; every call site passes constants; `ai_blade_rollout.gd:37`
already documents `simulate()` as pure so it can run on `WorkerThreadPool`.
The pop question is no longer part of the scan at all: since #536 a defensive
spike is decided per landing inside `BladeDamageInstance.land_on`, off
`BladePopResolver.LiveGate`, and rides the record as `h_pop`. It is therefore
**land-time**, not resolve-stage, and #529's LAND column is where it is measured.
(The old batch `BladePopResolver.resolve` answered it in one call during the
scan; text describing that arrangement is stale.) Either way, order-dependence
*inside* a deterministic function was never the divergence risk it was written up
as — given the same inputs every peer produces the same order and the same set. The portability of the *inputs*
(ground A) is the separate problem, and it is the one that bites.

**Current information decision: every client gets full world state; hiding
is a UI concern.** No fog gating exists anywhere in planning today, so this
matches what the code already assumes, and it's acceptable on a LAN. If that
ever needs to change, it's a payload swap (ship less than full state) on top
of this model, not a rewrite of it — `RevealEvent`'s `from_value`/`to_value`
in the parked `presentation/` classes is already the shape a fog-gated or
authoritative-reveal payload would want; see `presentation/README.md`.

### Rejected: full state replication / snapshots

The largest model change on the table. No `StatBoard` wire format exists;
`Stat._modifiers` is memory-only; `EffectInstance` grant-ledgers carry no
provenance for revocation; addons are dynamically-spawned children. And it is
2000 nodes × boards × addons per sync.

Its one genuine upside is that the serializer *is* save/load (#23) — but that is
a separate, parked feature, and buying it here to get versus is backwards.

### Deferred, not rejected: fog-filtered state deltas

The only model where hidden information is *technically* enforced: the host
sends each client only what its `InfoLevel` permits. This is the correct
destination and it is where this design is aimed. It is deferred because it
needs the same `StatBoard` wire format that state replication needs.

The owner's call was **"socially real now, structured so this is reachable"** —
every peer holds the full world and the UI declines to draw what your fog does
not cover. Because the host already owns every decision and clients never mutate
directly, moving here later swaps *what gets broadcast* (confirmed command →
filtered delta) behind one seam, without touching input, AI, or the systems.

### The resync backstop

**Settled #521 (2026-08-24), built in #560 + #561. Additive under the decision
above — it reopens nothing.** `AttackRecord` remains the only thing that mutates
a peer's live world during combat (`.claude/rules/attack-timeline.md`), and a
confirmed command remains the only thing that advances it. What the backstop
adds is a *repair*, for the one bug class the model above has no answer to at
all: the client's number crept wrong and nothing will ever notice.

**Two triggers, and there is deliberately no third.**

1. **Join.** A peer arriving mid-run receives the world rather than
   regenerating it — `GraphSnapshot` (#527) for the nodes, `EntitySnapshot`
   (#560) for the boards.
2. **A desync verdict.** `CommandLink._report_sync` finds the two fingerprints
   disagree, and the authority pushes the same pair as one `KIND_RESYNC`.

**A green fingerprint is not a green join** (#715). The fold answers "do our two
worlds agree", and it answered YES on a join where the client had decoded the
host's 800 nodes perfectly and then sat there forever without ever taking a turn
— its roster row still carried `LobbyScreen._PENDING_PEER_ID`, so no hero was
seated and nothing drove the turn. That is the second time on this path that
fingerprint agreement was not evidence of correctness; the first is the
applied-once guard, where the fold covers neither tags nor effects. So a join is
proved by the peer reaching its FIRST TURN — which is what
`GameRoot._announce_first_turn_for_rung_3` prints and what harness rung 3 reads
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

**#560 D7 — "`EntitySnapshot` DECORATES; it never spawns and never mints an
`entity_id`" — is superseded by #715 because the client no longer runs procgen
(agent decision, 2026-09-02).** D7 was settled by the owner in #560's
"Decisions (settled, do not re-open)" list, and its premise was stated there:
"#528 and #553 both shipped, so a joining client's entities exist by the time
state arrives" — i.e. the roster spawns exactly the named set. That held only
while both peers ran procgen. Since #715 the client runs none, and procgen
spawns ~120 entities the roster never names (one per removable blocker, #477);
without them the client decodes their nodes as unowned and the ownership fold
disagrees on the first compare. So a row whose entity is absent now asks an
optional `spawner` callback (`CommandLink.entity_spawner` →
`GameRoot.spawn_snapshot_entity`, which refuses anything that is not a blocker)
before it is skipped. **The prohibition D7 was really protecting still holds:**
this is not a second minting path, because the `entity_id` is the AUTHORITY's,
read off the row and stamped before the entity enters `entities_container`
(`Graph._mint_entity_id` assigns only where the id is still `0`). It is the
exact mirror of `_prune_entities`, which already removes an entity the payload
does not name — the payload is the authority's entity SET, and both directions
of that set now cross. A **callback** rather than an `instantiate()` inside the
snapshot: a blocker's `EntityStatBoard` is assigned per tier in code, and
`EntityStatBoard` refuses to mint a stat it has no field for, so a bare
instantiate yields a blocker with no health. See `EntitySnapshot._materialize`.

A materialized blocker's **spellbook crosses by value** (#726). The host's is a
#586 `SpellBook.duplicate_pruned` slice — a `SpellBook.new()` with no
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
them, which is what `SpellDef` identity comparisons (#511) need.

**What a resync does NOT carry** is the derived tier — `StatBoard` totals,
`Stat.bins`, aura contributions, vision. The receiver recomputes, exactly as
`GraphSnapshot`'s tier table says. A backstop that shipped derived state would
be asserting agreement on quantities the sync layer deliberately never
transmits.

### Not a separate option: event sourcing

Effectively the chosen model plus persistence. If a run log is ever wanted, the
confirmed-command stream **is** the event log. Nothing extra to design.

---

## What crosses the wire, per action

| Action | Up (intent) | Down (confirmed) | Why |
|---|---|---|---|
| allocate / deallocate / deallocate_set / stake / extract / move_core | the command | the same command, nothing more | Fully deterministic, no RNG — every peer re-applies it identically |
| launch attack | the plan: mode, pivot + blade member `stable_id`s, or target + spell (`AttackPlan.to_dict`) | the same command **plus `AttackRecord`**, a post-apply record of what each landing actually did, stamped by `BattleSystem` during application (#511) | `resolve()` is already pure and side-effect free, but the swing sim is order-dependent and crits roll. Clients reconstruct the recorded effects and replay VFX; they never re-simulate and never re-derive a number |
| loot pick / relic roll | the pick intent | the resolved result | The host rolls; the shuffles stay host-only |
| end turn | the command | the command | The host's `TurnManager` is the clock, so `_tick_until_ready`'s group-order tiebreak stops being a hazard |
| *(every action above, on a client)* | `KIND_INTENT` — the command dict, carrying the `intent_id` **the client minted** (#548) | nothing extra; the confirm is the ordinary `KIND_COMMAND` row above, echoing that same `intent_id` back verbatim | The client has to match a returning confirmation to the intent it sent, or `is_awaiting_confirmation` never closes. The host must **never re-mint**: a received intent goes through the same `submit()` as a local one, and `submit()` mints only when the id is absent |
| *(any of the above, refused by the host's gate)* | — | `KIND_REFUSAL` — `{intent_id, reason}`, `reason` a `StringName` code and never a UI string (#548) | A refused command never confirms, so nothing crosses on the ordinary leg — and a client waiting on a confirmation that will never arrive is the failure mode this channel most needs to not ship. Its own kind rather than an echoed command with a `refused` flag, so the fingerprint compare and the determinism probe keep one uncomplicated path. There is deliberately **no timeout, retry or heartbeat** for a confirm that is simply lost: ENet's reliable-ordered channel is the guarantee, and a LAN desync is a restart |

**Loot is rolled host-side and only the pick travels.** The candidate list is
already known to whoever received the request, so the pick command carries
`(entity_id, request_id, chosen_indices)` and nothing more (#509).

> **Owner call 2026-08-21:** *"loot picks are just 'hey i picked <this
> statmodifier>', users cannot distinguish a same-seed roll from a random roll
> given that looting is done by 1 player and invisible to others -- the
> resulting pick however needs to be communicated back to host so they can
> broadcast or whatever if needed"*

This supersedes the earlier reading — carried in §"Four facts" fact 3 and in the
lockstep rejection — that the loot/skill-dust `Array.shuffle()` calls were a
per-client divergence hazard needing a seeded RNG.

### The lobby roster, at the same model and a different scope (#714)

The roster replicates *before* a level exists, and it does it with the model
above rather than beside it. Two kinds, and they are the exact inverse of each
other:

| | Kind | Payload | Gate |
|---|---|---|---|
| Up | `KIND_LOBBY_PICK` | `{id, peer_id, …changed fields}` — one seat, only what moved, in `Participant.to_dict`'s encoding (a `Faction` / `CoreClass` as its `resource_path`, never a reference) | `Mode.MIRROR` sends, `Mode.BROADCAST` receives |
| Down | `KIND_LOBBY` | `roster.to_dict()`, the **whole** authoritative roster | `Mode.BROADCAST` sends, `Mode.MIRROR` applies |

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

**START is where `KIND_SETUP` finally goes out (#715), from the lobby.** It used
to be pushed on JOIN, by `GameRoot._on_peer_joined`, off a
`NetworkTransport.peer_joined` — which a *pre-established* link never fires
again. Once #713/#714 let the socket outlive the menu, a level built on an
adopted link would have waited out `SceneDirector.REVEAL_TIMEOUT_S` for a
message nobody would send. So `LobbyScreen._on_run_started` broadcasts the
settled `RunConfig` + `ParticipantRoster` off `GameSession.run_started`: the
HOST reaches that signal because the shell called `GameSession.start` on what
START emitted (which is also what resolved the seed the sentinel gate above
demands), and the JOINER reaches it because `apply_received` re-emitted it. One
signal, both machines, and each releases its lobby link there before routing —
`Wire` admits exactly one bound `EnetTransport` facade (`Wire.claim_binder`),
because two would re-emit every packet and the world would silently drift.
`GameRoot.await_host_run` is deleted, not deprecated.

**Who may edit what.** A human seat is editable by the machine it sits at
(`Participant.is_local`, #562's one home for "which of these is me"); an AI seat
belongs to whoever authors the roster, which is everyone except a client. The
rule is symmetric — the host does not dress the joiner's hero either — and it is
enforced twice on purpose: in the UI (`ParticipantRow.set_editable`) so a player
sees it, and on the host against the *roster* (`LobbyScreen.may_edit_remotely`)
so a payload cannot claim it.

**The lobby mounts its own `NetworkTransport` + `CommandLink` pair, and never
opens the socket.** `meta_root._push_lobby` is the one place that decides a
route opens a link — the same file that already decides which `NetworkConfig` a
route leaves on `GameSession` — so a lobby with no live `Wire` behind it mounts
nothing and is byte-for-byte the offline lobby. The screen hands its link back
at START (`_release_link`), leaving the socket up for the level to adopt (#713).

**Mass actions are one atomic command, never N.** `deallocate_set` and
mass-allocate paths serialize as a single command with a node list — splitting
them would let a peer observe an intermediate state that never legally existed.

---

## Where each subsystem sits

**AI runs on the host only and emits commands into the same queue.** That
deletes the frame-shaped problem outright: `turn_delay` becomes host-local
pacing with no sync meaning, and clients see an AI turn as an ordinary
confirmed-command stream. `ai_controller.gd` must stop calling
`allocation_system` / `battle_system` directly.

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
plan's lifetime through the swing (#406). Mirroring off `command_applied`
therefore made a peer wait out the *host's animation* before it could start its
own — lag proportional to spell length, for a payload that was final much
earlier. `_drain` confirms at the flip point instead, and `CommandLink`
broadcasts off that. (Until #545 the attack called `applier.confirm(cmd)` itself,
at its own mid-apply settle point; the signal outlived that arrangement because
the animation tail it exists for is still there.)

**#540 flipped when the drain confirms, and #545 made it universal.** `_drain`
is `validate → confirm → apply` for every verb without exception:
`CommandApplier._validate` forwards to the same `can_*` queries the mutating
verbs ask themselves, so "validated" already means "will apply" and the host
never has to finish mutating before it can tell anyone.

`LaunchAttackCommand` was the last hold-out, behind a
`Command.confirms_before_apply()` opt-out hook, because its `AttackRecord` was
computed *inside* the apply and confirming first would have broadcast an empty
record that a peer reads as an initiate it cannot run. #545 moved that compute up
into `BattleSystem.prepare_launch_command()`, which `_validate` calls — legal
since #536 made resolution shadow-only, and free of consequence since #540
decision 4 stopped the confirm being a fingerprint sampling point. The hook is
deleted rather than left standing with no callers.

**One consequence worth naming: `_validate` is not side-effect-free.** For the
attack it *produces the payload it is gating on* — the gate is "resolve, then
check the attacker can afford what came out", and the resolution is the record.
Nothing real moves (a `CombatWorld.shadow()`), but read `_validate` as "the
command is final and legal, or it is refused", not as a pure query.

**The pending phase is zero-length locally for every verb, and that is not a
reason to delete it (#541).** `submit` drains synchronously down to `_validate`,
so on a peer that *decides*, `is_awaiting_confirmation` is true for a stack
frame; it becomes the round trip only once #463 routes a client's intent upward.
The attack used to be the exception and the long one — it confirmed late, so the
flag spanned its whole apply — but since #545 its resolve happens inside the
validate the flag closes on, so its window is a stack frame too. It is derived —
"queued, or popped and not yet confirmed" — rather than assigned, because a
`command_applied` handler that submits opens a fresh window one line before the
outgoing command closes one. The flag is raised in `submit` *ahead of* the
`is_applying` bail, which is the one moment the third gate is the sole reason the
player cannot act, and is what `test_command_routing.gd` asserts against.

`confirm` is idempotent and only ever called for a command that is going ahead —
which is where "a refused command changed nothing, so mirror nothing" now lives.
Ordering across commands is untouched: the queue is serial, so a mid-apply
confirm still lands between its neighbours'.

Routed so far: every `PlayerInputController` mutation (#510),
`battle_system.launch_attack` (#511 — it builds a `LaunchAttackCommand`,
submits it, and parks on `applying_changed`, so every existing caller still
awaits the whole action), and loot (#522, reshaped by #646 — a
`LootRoundCommand` per round of a relic's claim, minted only once that round's
outcome is known; see "The loot round is the deliberate exception" below).
Still direct, by plan: `ai_controller` (child D).

`PickLootCommand` is now answered for real, against `LootPickRegistry` — which
also took over minting `request_id`, replacing the per-process static counter
that would have handed the same id to different requests on two peers. It stays
dormant only because nothing sends upward yet (#463).

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
single-player and hot-seat) and `ENetTransport`. ENet is chosen because it is
built into Godot and zero-config on a LAN, **not** because it is the only
option: `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer`, and raw
`PacketPeerUDP` / `StreamPeerTCP` all exist. The transport choice is close to
free and reversible behind the seam. Lobby: type-an-IP.

**One command type, two states (#511).** `LaunchAttackCommand` is the only
asymmetric verb in the vocabulary, and that is deliberate. An EMPTY `record`
means *initiate*: nobody has computed this attack yet, so the authority stamps
the seed, resolves on a shadow, gates on affordability, and stamps the record it
produced onto the same object — all inside `_validate`, so `CommandLink` (which
encodes on `command_confirmed`) broadcasts a complete record before anything
local has moved. A POPULATED `record` means *replay*: rebuild the plan (for the
animation only) and the recorded deltas (for the world), and land them through
the same `OutcomeApplier` on the same `BeatClock`. Two types would need the
receiver to know its own role to refuse the wrong one; one type whose payload
says which half of the work is already done needs no role at all — and when #463
adds the intent channel upward, a client's intent IS this command with an empty
record.

Since #545 the authority *also* reaches the apply with a populated record — it
replays its own, exactly as a peer does — so `record.is_empty()` no longer
distinguishes "did I compute this". The transient `computed_here` field does, and
it is deliberately absent from the wire: a received command is by definition one
this machine did not compute.

**The loot round is the deliberate exception to "one type, two states" (#646)
— and it still honours the same underlying invariant.** The rule #545 actually
establishes is not "compute in `_validate`"; it is **the command must be
complete before it reaches the confirm flip point**. #545 satisfies that by
computing *earlier, inside* the pipeline (`BattleSystem.prepare_launch_command`
resolves on a shadow world from within `_validate`). #646 satisfies the SAME
invariant by minting the command *later, outside* the pipeline — the
offer/pick/roll sequence runs to completion first, and `LootRoundCommand` is
constructed only once it has. Two routes to one rule, not an exception to it.

The validate-lift route was tried first and does not transfer. `LootRoundCommand`
had the same empty/populated pun as `LaunchAttackCommand` until #646, and broke
the same way: `_drain` confirms before it applies, so a round whose outcome was
stamped *inside* `_apply` (deep in `SkillDustAddon`'s `_run_round` chain)
broadcast an EMPTY `resolved` — a peer read that as an unstamped INITIATE and
rolled its own divergent loot, empirically confirmed (host granted a modifier,
client granted none). Unlike the attack, though, a loot round with a human
collector can *await a pick* — resolving it inside `_validate`,
`LaunchAttackCommand`-style, would freeze the host's whole serial command queue
on a remote player's click, unacceptable on a LAN where a relic's claim can run
several rounds deep. So neither of the two prior fixes was available here: not
the `confirms_before_apply()` hook (#545 deleted it, and issue #646's
acceptance 4 forbids reintroducing it), not the validate-lift (blocked by the
human in the loop). The offer/pick/roll split is the third route to the same
invariant, achieved by construction rather than by exemption — which is the
answer for the next verb that reaches for "one type, two states" with a human
in the middle of it: check whether the validate-lift can actually apply before
assuming it can.

So #646 split the two things one `LootRoundCommand` used to carry into two
downward messages instead of two states of one type:

* A `LootPickOffer` — NOT a `Command` — carries "show this collector a pick
  screen, here is the draw" when a round needs a REMOTE human. It mutates
  nothing and never touches `CommandApplier._drain`; `CommandLink` sends it off
  `LootPickRegistry.offer_parked` as its own additive, opt-in wire kind
  (`KIND_LOOT_OFFER`), the same shape as `KIND_SNAPSHOT` / `KIND_SETUP`.
* `LootRoundCommand` is minted only once a round's outcome is fully known — its
  constructor takes the outcome, so there is no way to construct one before
  deciding it. It is therefore ALWAYS a replay, on every peer including the
  authority: `_drain` needs no opt-out, because by construction there is
  nothing left to compute by the time one exists. The grant itself moves out of
  resolution and into the shared apply/replay path (`SkillDustAddon._land_outcome`),
  so the authority does not double-grant (once resolving, once applying).

The explicit cost, accepted rather than hidden: this gives up the symmetry
`LaunchAttackCommand` has. The loot round arguably never fit that shape in the
first place — it is the one verb with a human in the middle, and the
empty/populated state pun is exactly what produced the #646 bug. `PickLootCommand`
is untouched by any of this; it remains the upward intent, now answering a
`LootPickOffer` instead of a bare invitation to guess that one exists.

One consequence: the offer/pick/roll sequence now runs entirely OUTSIDE the
command queue, between rounds, so `CommandApplier.is_applying` no longer
implies "a pick is outstanding" the way it used to (the whole chain used to run
inside one command's `_apply`). `CommandApplier.has_outstanding_loot()` is the
explicit gate that replaces what `is_applying` used to give for free — see
`PlayerInputController.can_player_act()`.

**A peer re-simulates to DRAW, never to derive.** Melee reforms a bit-identical
blade from the plan (`blade_sim.gd` is a pure fixed-dt XPBD loop, no frame
delta, no RNG) so the swing animates; the damage it shows comes off the record.
That is not the re-simulation this model forbids — nothing is mutated and no
number is computed. `docs/domain/attack-timeline.md`'s land-time re-read
contract is host-side only, and now says so.

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
- Save/load (#23).
- Reconnect and desync recovery. LAN, one room: a desync is a restart.

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
  and `outcome.resolve_seed` carries it back out (`8dc6f77`); that stamp rides
  down with the outcome so a peer can verify by re-resolving. Loot rolls are
  **host-only** and need no determinism guarantee at all — their unseeded
  `Array.shuffle()` calls are not a hazard under this model.

  This supersedes what this section said before 2026-08-21 — *"`Array.shuffle()`
  with no argument is a desync. Every gameplay-affecting roll draws from a
  `GameSession` sub-stream."*

  > **Owner call 2026-08-21:** *"we don't care about that seed beyond the
  > procgen using it, for now. possibly forever."*

  Consequence, and it is deliberate: **the same seed reproduces the same map,
  not the same fights.** #457's `GameSession` seed is a procgen input; it is not
  a determinism contract over combat or loot.

  **And since #715 it is not a CROSS-PEER contract at all.** The seed reproduces
  a map *on one machine* — a replay input, so a run can be re-rolled from what
  was recorded. It is no longer how a second machine gets the same world: only
  the host generates, and a joining client receives the authority's serialized
  graph and never runs `GraphProcgen`. Anywhere this document, or
  `.claude/rules/game-session.md`, reads *"the map is reproduced by each peer
  from the seed"*, read instead: **the map is SHIPPED**. That is what takes
  `procgen/`'s transcendentals (#547, #689, #706 — `pow()` in the seeded draw,
  whose last bit is not portable across two platforms' libm) off the LAN
  critical path entirely: nothing on the joining side re-derives them, so
  nothing about them can desync.

- **Still never roll from a null RNG on anything a peer must reproduce.** The
  narrower rule that survives: if a result crosses the wire as something a peer
  re-derives rather than receives, it draws from the seed it was handed. What
  changed is the *scope* — host-only rolls (loot, relics) are exempt, because
  nothing re-derives them.
