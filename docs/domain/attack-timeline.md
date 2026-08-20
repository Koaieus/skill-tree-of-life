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
a lie and break the preview.

## Why: the fiction has to hold

The rule falls out of what an attack visibly *is*.

*Melee.* A blade swings into an arm of enemy nodes, kills the one closest to
the core, and the rest of the arm — now islanded — is force-deallocated. The
blade sweeps on across nodes that are already dead. Their `SpikeAddon`s do
nothing, because a severed arm does no work. You don't disarm someone and then
get shot by the gun falling to the floor.

*Magic.* A wizard lobs a bolt at a target. It lands, deals damage, and a
smaller bolt jumps from that node to each hostile neighbour. If the first
landing *killed* the target, the node is unallocated when the next wave picks
its neighbours — so a spell that only propagates to hostile nodes cannot bounce
back into the corpse it just made.

Both stories are the same rule: **kill state resolved at wave N is visible to
wave N+1.**

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
| Defender mitigation (`armor`, `min_damage_taken`) | **Land** | ✅ already live — `Mitigation.apply` runs inside `SkillNode.take_damage` |
| Cascade / dealloc / entity death | **Land** | ✅ already live and synchronous |

The old shape was **defence live, offence frozen**, which has no principle
behind it — it is simply where `Mitigation` happened to be called from. The
contract is **set frozen, all arithmetic live.**

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

## The substrate seam

The contract says application re-reads live state. AI scoring and previews must
not mutate. Both are satisfied by the same move:

> **Resolution and application run against a *substrate*.** For a real launch
> the substrate is the live world. For AI scoring and previews it is a shadow.

`resolve()` stays side-effect-free from the caller's perspective,
`AttackOutcome` stays a serializable wire payload, and `ai_blade_rollout.gd`'s
purity contract survives. This is not abandoning what motivated freezing the
candidate set — it is parameterizing *what world* the freeze happens against.

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

- per-node combat HP
- per-node ownership
- the affected entities' stat boards

with the effect hooks able to run against it. Far cheaper than a world clone —
no scene tree, no addons-as-children, no physics — but not free, and not a
ledger.

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
arrival_time_i = launch_time_i + flight_time_i
```

- **Nearest fires first and arrives first.** The volley rolls outward from the
  target. (Real bow infantry range in the same direction.)
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

**Open:** with a constant `PROJECTILE_SPEED`, `flight_time` grows with
distance, so the arrival span is `TOTAL_STAGGER + (flight_far - flight_near)` —
wider than the launch span. Making the two spans exactly equal requires a
constant `flight_time` (i.e. distant arrows fly faster). Arrival order is
monotone in distance either way, so the contract holds regardless; this is a
feel decision, unsettled.

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

- Constant projectile speed vs. constant flight time (see the ramp section).
- `draw_time` values, and the melee analogue of a preparatory phase.
- Whether the substrate is an explicit interface or a duck-typed pair of
  accessors. Build it against magic first — the smallest consumer — rather than
  designing it in the abstract.
- What a landing that fails its gate should *look* like. Silently vanishing is
  cheap; an arrow thunking into a dead node is more legible. Neither is
  decided.
