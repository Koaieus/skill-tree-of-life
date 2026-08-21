# The attack timeline contract

**Decided 2026-08-20**, out of the #488 discussion. This is what every attack
mode is being built *towards* — a single contract all three modes fulfil, so
that adding a fourth mode, or an on-hit effect, or an ammo type, is a matter of
satisfying a written spec rather than re-deriving what "when does this happen"
means from three different code paths.

The game-design side of attacks (damage formulas, the color triangle,
dismemberment) lives in `../design/combat_system.md`. The *code shape* of the
in-turn attack flow lives in `attack_plan_system.md`. **This doc covers only
the timing model**: which world state each part of an attack reads, and at
which clock.

Read this before changing `resolve()` on any `AttackPlan`, before touching
`OutcomeApplier`, and before adding anything that happens "during" an attack.

---

## The invariant

> **Resolution emits candidate landings in time order. One applier walks them
> in that order and re-evaluates each landing's gate against live state before
> applying it.**

Two halves, both load-bearing:

- **Resolution is still pure and still up-front.** It produces an
  `AttackOutcome` — a *plan of landings*, not a result. That is what makes it
  usable as a preview, as AI scoring input, and as #458's wire payload. This
  half is unchanged.
- **Application is staged and live.** Each landing's *gate* — "is this target
  still allocated? still hostile? is this blade vertex still alive?" — is
  re-checked at the moment the landing applies, not at the moment it was
  planned.

The gate is a **veto, not a re-plan.** A landing that fails its gate is
dropped. Application never *discovers new targets*; that would make resolution
a lie and break the preview. Re-aiming a wasted shot at some other live target
is explicitly out — it is the one shape of this feature that breaks the
contract.

### What a failed gate looks like — settled, and it differs per mode

The three modes do not share a visual answer, because they do not share a
failure *shape*:

- **Melee: ignore it, no visual at all.** Hit-scan has no concept of a dud —
  only "hit" or nothing. A blade sweeping over an already-dead node is
  indistinguishable from sweeping over ground that was never allocated, and
  should look that way.
- **Magic: it cannot happen.** The next wave's candidate list is built by
  querying ownership live at selection time, so a dead node is simply never a
  candidate. There is nothing to render.
- **Ranged: the arrow lands inert.** This is the only mode where the gate can
  fail *after* the visual has committed — the projectile is already in flight
  when the target dies. It arrives and plays a dud beat: desaturated, no bloom,
  no damage number. Same visual language as a spike-popped blade vertex
  dimming. Legible, and it shows the player their volley overkilled.

## Why: the fiction has to hold

The rule falls out of what an attack visibly *is*.

*Melee.* A blade swings into an arm of enemy nodes, kills the one closest to
the core, and the rest of the arm — now islanded — is force-deallocated. The
blade sweeps on across nodes that are already dead. Their `SpikeAddon`s do
nothing, because a severed arm does no work. You don't disarm someone and then
get shot by the gun falling to the floor.

*Magic.* A wizard lobs a bolt at a target. It lands, deals damage, and a
smaller bolt jumps from that node to each hostile neighbour. If the first
landing *killed* the target, that node is unallocated for the rest of the
cast — so a spell that only propagates to hostile nodes cannot bounce back into
the corpse it just made.

Mind the wave arithmetic: **wave 0** hits the seed, **wave 1** hits its
neighbours, and **wave 2** is the first expansion where the seed can be
selected again (it is `visited` during the 0→1 expansion, so wave 1 was never
the risk). A test for this needs `max_hops >= 2` and a `max_visits_per_node`
that permits a revisit, or it proves nothing.

Both stories are the same rule: **kill state resolved at wave N is visible to
every expansion from wave N onward.**

## The clocks

| Clock | When | What it is |
|---|---|---|
| **Plan** | while the player is arming | Live, continuously re-read. Highlighting, range rings, validity. Nothing is committed. |
| **Resolve** | `AttackPlan.resolve()`, once, at launch | Pure. Snapshots the *candidate set* and the attacker-side arithmetic. Emits `AttackOutcome`. |
| **Land** | per landing, in `arrival_time` order | Live. Gate re-check, then mitigation, then mutation, then any cascade — all synchronous within the beat. |

## What is read at which clock

The target state. Where this differs from what the code does today, the
"today" column says so — those gaps are the work.

| Input | Clock | Today |
|---|---|---|
| Candidate landing set (which nodes *could* be hit) | **Resolve** | ✅ all three modes |
| Ordering of landings | **Resolve** (authored into `arrival_time`) | ⚠️ ranged applies in append order, not arrival order; melee/magic don't set `arrival_time` at all |
| Landing gate (target still allocated / still hostile / vertex still alive) | **Land** | ❌ frozen at resolve in all three modes |
| Attacker offense (`ranged_damage`, blade vertex damage, spell damage) | **Land** | ❌ frozen at resolve in all three modes |
| Crit *decision* (`crit_chance` roll, `SpellDef.crit_conditions`) | **Resolve** | ✅ all three modes, one shared `CritRoll` (#507) — see below |
| Crit *multiplier* (`amount ×= crit_multiplier`) | **Land** | ✅ all three modes, in base `DamageInstance`/`HealInstance.land_on` |
| Defender mitigation (`armor`, `min_damage_taken`) | **Land** | ✅ already live — `Mitigation.apply` runs inside `SkillNode.take_damage` |
| Cascade / dealloc / entity death | **Land** | ✅ already live and synchronous |

The old shape was **defence live, offence frozen**, which has no principle
behind it — it is simply where `Mitigation` happened to be called from. The
contract is **set frozen, all arithmetic live.**

### The crit split — the one input that spans two clocks

Crit (#507) is the only row above that appears twice, and the reason is worth
recording because the obvious "just do it at land, like mitigation" is wrong
in a way that is invisible until you look at the VFX layer.

- **The decision cannot wait for land.** `MagicBounceCoordinator` stamps
  `Projectile.crit_tier` when it *spawns* a bolt, and `Projectile` fires
  `_on_crit` at flight start — both strictly before the applier lands that
  wave. Deciding at land makes every magic projectile read tier 0. Magic's
  `SpellDef.crit_conditions` are resolve-bound anyway: they read `CastSpell`
  propagation state (predecessor, incident count) that exists nowhere else.
- **The multiply cannot happen at resolve.** `RangedHitInstance.land_on`
  overwrites `amount` with a live `ranged_damage` read, so anything resolve
  multiplied in is discarded.

So the decision is frozen with the candidate set and the **arithmetic is
live**, which is exactly what the contract above asks for. The residual cost
is stated plainly: `crit_chance` / `crit_multiplier` are read at resolve, so a
mid-attack change to either is not seen by hits already in flight.

One further constraint falls out of a single seeded stream serving a whole
attack: **draws are consumed in `arrival_time` order.** `CritRoll.decide_all`
reuses `OutcomeApplier.in_arrival_order` rather than sorting again, so the two
cannot drift apart — and the symptom if they did would be crits that stop
reproducing under a replayed seed, not a visible break.

## Per-mode contract

Every mode must satisfy all four. The *mechanism* differs; the contract does
not.

1. **Emit candidates in time order**, each stamped with a real
   `HitInstance.arrival_time` in seconds from launch.
2. **Re-evaluate ownership and liveness at land time**, per landing.
3. **Read attacker offense at land time**, not resolve time.
4. **Resolve against a substrate** (below), so AI and preview never mutate the
   real world.

### Magic

The seam already exists. `SpellResolver`'s `while not wave.is_empty()` loop is
literally the wave model above. The change is to move application *inside* it:

```
reduce incidents  →  on-hit effects  →  APPLY  →  expand next wave
```

so `config.filter.allows` and `max_visits_per_node` see post-apply ownership.
This is the smallest of the three changes and it delivers the fireball story
directly.

`PropagationEvent.beat` × a per-wave interval is where magic's `arrival_time`
comes from.

### Melee

**Do not interleave application into `BladeHitScan.scan`.** Its
`PhysicsShapeQueryParameters2D.exclude` is built once, before the substep loop;
interleaving would mean rebuilding the exclude list every substep of a 1.2s
sim, and the scan's purity (`ai_blade_rollout.gd` runs it on
`WorkerThreadPool`) is worth more than that.

Instead, **move the ownership filter from query time to consumption time**:

- `MeleeAttackPlan.collect_target_excludes()` currently excludes
  `not sn.is_allocated()` from the physics query. Stop excluding on that
  basis — keep excluding only the attacker's own nodes and the blade members.
- The applier walks `BladeHitEvent`s in `t` order and re-checks
  `is_allocated()` / `owned_by` / spike-pop per event.

`BladePopResolver.resolve()` already gates on `node.is_allocated()` and
`node.owned_by == attacker`. **Those predicates are already written as
live-state checks** — they simply never get re-evaluated, because `resolve()`
completes before a single point of damage lands. This change is what makes them
do the job they were written for.

`BladeHitEvent.t` is melee's `arrival_time`.

### Ranged

The degenerate case: candidates sorted by `arrival_time`, gate re-checked per
landing. Plus the volley ramp, below.

---

## The substrate seam — for AI and previews only

**A real melee or ranged attack does not need a substrate. A real magic attack
does.** The original framing of #498 — substrate first, it gates everything —
was wrong; the correction that replaced it ("nothing needs a substrate") then
over-generalised from melee to all three modes. The truth is an asymmetry, and
it turns on **where each mode's gate lives**.

- **Melee and ranged gate at *consumption* time.** The applier walks landings in
  order and re-reads `is_allocated()` / `owned_by` per landing. That is an
  ordinary read of the live world at the right moment; nothing is copied, and
  both moves are unblocked today.
- **Magic gates in *candidate selection*, which lives inside
  `SpellResolver.resolve()`.** For wave N+1's filter to see wave N's kill,
  `resolve()` itself must mutate. Two things then break: `OutcomeApplier.apply`
  (called once, `systems/battle_system.gd:256`) lands every hit a **second**
  time on a real cast, and `resolve()`'s dozen preview callers — spell tooltip,
  spell playground, balance harness, tests — would mutate the live world just by
  being asked what a spell *would* do.

  A resolve-scoped ledger of "nodes this cast already killed", consulted ahead of
  real `owned_by`, is not an escape: that is a second implementation of
  ownership, and it is ruled out for the same reason as everything else here.

  So magic's wave-loop move is the first real consumer of `resolve_against(slice)`
  — live slice for the cast, shadow for the tooltip — and retiring BattleSystem's
  second apply for magic belongs to that same step. Found while executing #501;
  see its comment of 2026-08-20.

What the substrate is for is narrower:

> **AI scoring and previews must not mutate.** Today `resolve()` already gates
> (`BladePopResolver`, propagation filters) against live state at resolve time,
> for free, because nothing has mutated yet. Once gating moves to *apply* time,
> the AI loses that accuracy unless it can run the applier — and it cannot run
> the applier against the real world.

So the substrate is a **follow-on that restores AI/preview accuracy**, not a
prerequisite.

### How wrong is an un-simulated estimate? Badly, and non-uniformly

The tempting cheap answer is "the gate only ever *vetoes* landings, so an
ungated estimate is a strict upper bound — directional, bounded, discountable."
**It is not discountable.**

A propagating spell with escalating per-hop damage, seeded at a local degree
maximum, estimates `1 + 2 + 4 + … + 1024` while the real cast stops after ~20
damage, because the nodes it needed to bounce through are dead and no longer
valid candidates. The error scales with hop count and degree — *exactly where
the AI thinks the value is* — so it generates rank inversions rather than a
uniform offset. An AI using it reliably picks the worst spell target on the
board and scores it highest.

### The design: split state from notification

Split every mutation site into **state change** (moves to a plain `RefCounted`)
and **notification** (stays on the Node). Simulation runs the state half
against a throwaway copy. One implementation of the logic, so sim/real
agreement is a fact rather than a discipline.

```
SkillNode (Area2D)                    NodeCombat (RefCounted)
├── visuals, collision, addons        ├── board: NodeStatBoard   ← Resource, duplicated
├── signals, Events, presentation     ├── owner: EntityCombat
└── _combat ──────────────────────────┤ host: SkillNode  (null on a shadow)
                                      └── take_damage / heal / is_allocated
```

`SkillNode` *composes* its `NodeCombat` — it does not copy one, it owns the
live one. A shadow has `host == null`, so the notification branch does not
exist for it. **There is no "simulation in progress" mute flag**, and there
should not be: a flag is something you can fail to set; a null host is
something that cannot be reached.

Two facts make this small. `StatBoard` / `NodeStatBoard` already extend
`Resource` and are deep-duplicable — `_init_node_board()` does
`source.duplicate(true)` today — so the stat system does not move at all. And
`_node_board_ready` is lazy, driven from every write path rather than
`_ready()`, so a detached slice initialises correctly with no scene tree.

Full architecture, the `host` invariant, and the migration order are in #498.

### Why cloning SkillNodes was the wrong answer

Worth recording, because it is the obvious first idea. `duplicate()`-ing nodes
and running the real `take_damage` against the copies leaks through the global
broadcast surface: `Events.skill_node_damaged.emit(…)`, and
`owned_by.dispatch(…)` — a duplicated node's `owned_by` still points at the
**real** `Entity`. `AllocationSystem.force_deallocate` is the same, via
`_revoke_node_effects(node, previous)` and
`previous.navigator.mirror_remove(node)`.

Cloning the *Entity* as well closes the `owned_by` half. What it cannot close
is the bus: `LootSystem` connects to global `Events.entity_dying`
(`loot_system.gd:170`) and resolves the killer as
`turn_manager.current_entity`, so a simulated kill grants **real XP** and
spawns a real `SkillDustAddon` no matter whose clone died. Cloning entity
subtrees remains a viable cheaper fallback — bounded failure mode, a wrong
score rather than a broken world — but its cost is Node duplication per
rollout, which scales badly against exactly the many-rollout spell AI that
motivates the work.

This is also the honest answer to *"how do games like Monster Train do it?"* —
card battlers clone their battle state freely because that state is **plain
data with no engine objects and no global emit surface**. The reason cloning is
cheap there and not here is not object size; it is that their mutation path has
no reach outside the state object.

### `AttackOutcome` is the result, not a plan

Under this model `resolve()` becomes `resolve_against(slice)` — the live slice
for a real launch, a snapshot for AI and previews. Same function, same code
path.

- **`AttackPlan` holds the inputs.** Change one and the outcome is recomputable.
- **`AttackOutcome` is *the* deterministic result** of those inputs, computable
  at any time.

`HitInstance.effective_amount`'s *"0.0 until applied"* caveat disappears — it
is always filled, because resolving **is** applying, to a world you may throw
away. Totals, per-node damage, kill lists and the enemy/friendly healing split
are then accessors over `outcome.hits`, not new machinery. XP is the one
exception: it lives in `LootSystem`, which gains a pure `preview_kill_xp` query
that its own granting path also calls.

### What the shadow must copy

A revocation ledger is **not sufficient**, and this is the trap:

`AuraEffect._on_node_deallocated` calls `recompute(ctx)`, which does
`ctx.revoke_all()` and then **re-derives every modifier from the current
world** (`effects/aura_effect.gd:59-74`). It is a full rebuild, not a revoke.
The net effect during an attack is still monotone-shrinking in practice (nodes
only ever leave ownership mid-attack), but a ledger that only records
revocations cannot reproduce a rebuild, and any distance-scaled aura recomputes
its *values*, not merely its membership.

So the shadow is a real copy of:

- **every affected entity's complete owned subgraph** — HP and ownership per
  node
- those entities' stat boards
- **magic only:** unallocated nodes within the spell's hop reach, which exist
  purely as propagation conduits for spells whose filter admits them

with the effect hooks able to run against it. Far cheaper than a world clone —
no scene tree, no addons-as-children, no physics — but not free, and not a
ledger.

**Do not reach-bound the owned subgraph.** The obvious optimisation — copy only
nodes the attack can physically touch — computes the wrong cascade.
`BattleSystem._on_node_depleted` calls
`defender.navigator.nodes_islanded_by_removing(node, defender.core_location)`,
which walks the defender's *entire* territory to find what islands when a node
leaves. A node fifty hops from the impact can be part of the cascade. Unowned
nodes are the ones that can be skipped, and only because their sole gameplay
function is to be a spell conduit.

### The one thing a shadow cannot hold

Melee's hit detection is a **physics query against the real world**
(`space_state.intersect_shape`). A shadow cannot hold collision shapes.

This is fine, because **nothing moves nodes mid-attack**: scan once against the
real world for geometry, and shadow only the gate re-evaluation. If a future
mechanic ever displaces a node during a swing, this assumption breaks and the
melee substrate story needs revisiting.

---

## Ordering and `arrival_time`

### `arrival_time` is not optional

`HitInstance.arrival_time` is currently set **only** by
`RangedDamageFormula` — every melee and magic hit carries `0.0`, documented as
"0.0 for hit types that don't yet compute one."

That is a semantic lie (they do not land at t=0) and under a design where the
world mutates on the reveal clock it is worse than cosmetic: with
`arrival_time == 0`, every melee hit and every spell hop mutates
simultaneously, and the whole staged model degenerates to today's behaviour for
two of three modes. #488 lists stamping it uniformly as *"optional, last"*;
under this contract it is a **prerequisite**, not a nicety.

### The ranged volley ramp

Allocation order must never influence a combat outcome. Today it does: the
firing order is `GraphMirror._node_ids` insertion order, which is allocation
order. It is *deterministic across peers* (same command replay → same
allocation order), so it is not a desync — it is a design bug, and a worse one
than randomness, because a player could learn to exploit it.

**Author the schedule; derive nothing from iteration order.**

```
rank reaching leaves by euclidean distance to target, ascending
    tie-break: SkillNode.stable_id          # wire-legal, minted by Graph
launch_time_i  = draw_time + lerp(0, TOTAL_STAGGER, rank_i / (n - 1))
arrival_time_i = launch_time_i + FLIGHT_TIME       # constant, NOT distance/speed
```

**Flight time is a constant, not `distance / PROJECTILE_SPEED`.** Settled
2026-08-20. The fiction is the arc: a point-blank shot is lobbed nearly
straight up, a distant one goes nearly flat, and both take about the same time
to come down. Arrows are *aimed*, not fired on a rail.

Mechanically this is the stronger choice, which is why it wins:

- **The launch span and the arrival span are identical** (both `TOTAL_STAGGER`).
  With a constant projectile *speed* the arrival span would be
  `TOTAL_STAGGER + (flight_far - flight_near)` — always wider, and widening
  with the size of your territory, so a big empire's volleys would smear out
  while a small one's stayed crisp.
- **Arrival order == firing order == distance order**, unconditionally. No
  ratio between stagger and flight can invert it, so armor-reducing ammo has an
  order it can rely on without a caveat.
- **`RangedDamageFormula.PROJECTILE_SPEED` stops being the timing authority.**
  The animation still needs a speed — it is now *derived* per shot
  (`distance / FLIGHT_TIME`) rather than the input the schedule is built from.

- **Nearest fires first and arrives first.** Note ranged is single-target —
  every reaching leaf shoots the *same* node — so what ripples outward is the
  **firing**, across the attacker's territory from nearest leaf to furthest;
  the impacts all converge on one point, in that same order. (Real bow infantry
  range in the same direction.) The choice therefore sets *resolution* order at
  the target, which is what armor-reducing ammo needs, not a visual wave of
  impacts.
- **`TOTAL_STAGGER` is fixed**, so a 4-shot volley and a 100-shot volley take
  the same wall time. This is what makes the "blot out the sun" fantasy
  readable — a hundred arrows in the same window rather than a hundred×stagger
  crawl.
- **`draw_time`** is a windup phase before the first release — leaves visibly
  draw before loosing. **0.0 for now**, but it is authored in from the start so
  it can be turned on without re-deriving the schedule. Melee wants an
  analogous preparatory phase.
- **`t = 0` is the start of the draw**, not the first arrival. Every
  `arrival_time` is measured from the moment the action begins.

**Watch:** `ArrowVolleyCoordinator._flight_for` clamps to
`maxf(arrival_time - launch_delay, flight_time * MIN_FLIGHT_FRACTION)`.
Whatever `TOTAL_STAGGER` is chosen, verify the clamp does not bite — if it
does, the animation silently stops matching the authored ramp, which is exactly
the drift class #479/#481 cost five rounds of latches.

### Explicit firing list

`RangedAttackPlan` should produce `[(firing_node, target)]` explicitly, today,
with no firing-group UI. It costs nothing, removes a live-topology read from
the command path, makes the volley self-describing on the wire, and **subsumes
the ordering fix** — the order is authored into the list rather than emergent.

Firing groups (#495/#496's volley composer) are then a UI on top of a payload
that already exists.

---

## What this corrects

**`melee_attack_plan.gd:380-386` and `melee_preview.gd`'s `launch()` docstring**
argue that a post-cascade rescan "would exclude nodes the cascade just
deallocated, silently dropping hits/pops the pre-cascade `resolve()` correctly
saw." That is **valid for what it rejected and invalid as a principle.**

What it rejected: `MeleePreview` re-scanning to *animate an outcome that had
already fully landed*. Dropping hits there desyncs the animation from applied
damage — a real bug about replaying a finished mutation.

What it does not license: freezing the gate. Under this contract the deallocated
arm *should* drop out, because the damage has not landed yet when the gate is
checked. The comments need rewording when melee moves over, or the next agent
will read them as forbidding the thing we are building.

**`docs/domain/multiplayer-sync-model.md`** says
`MeleeAttackPlan.resolve()` "is not safely re-simulable" because
`BladePopResolver` resolves pops during the scan. #488's decision comment
establishes this is wrong — `BladeSim` is a pure fixed-dt loop and
order-dependence *inside* a deterministic function is not a divergence risk.
That doc needs the correction independently of this one.

## Open forks

- `TOTAL_STAGGER` and `FLIGHT_TIME` values — feel, needs the real game.
- `draw_time` values, and the melee analogue of a preparatory phase.
- Whether the combat slice (#498) is worth its size, or whether cloning entity
  subtrees is the cheaper answer for now. Leaning slice; nothing is blocked on
  it either way.
- **Where the notification half sends its presentation call.** Master runs
  design A (`RevealRecorder` live, `shown_hp`/`shown_owner` on `SkillNode`)
  while #488's decision comment specifies design B (the world mutates on the
  reveal clock, no view store). #494 owns resolving that. The state/notification
  split is **orthogonal** to it — under A the notification half calls
  `RevealRecorder`, under B it just emits — so #498 must not be written as
  though either has won.
