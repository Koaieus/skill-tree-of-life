# Status effects

A status is a stacked, ticking row on a node (or on the entity, once the row falls
through a cracked core) — damage-over-time, debuffs, vision penalties. It is **not**
an `Effect`: there is no grant ledger and no hook dispatch. Hooks, auras and modifier
plumbing are [effect-system.md](effect-system.md); the defensive axes the families
bypass are [defense-axes.md](defense-axes.md).

## The status slice

- **Definition.** `StatusDef` (`effects/status/status_def.gd`) is a `.tres`-authored
  resource: id, tags, `power_max`, a `decay` slot, `reapply` policy, `on_dealloc`,
  display identity. Subclasses override `_on_applied` / `_on_tick` / `_on_removed`
  and stay stateless.
- **Rows.** A `NodeStatus{power, key, camp_id, applier_id}` per `(def.id, key)`,
  held on the `StatusHost` slice `NodeCombat` composes beside `_tags`/`_board` —
  "on NodeCombat, like node HP" (owner). See
  [Status rows](#status-rows-group_by-keys-them-visible_if-gates-the-count-1343).
- **Application.** `ApplyStatusEffect : OnHitEffect` pushes a
  `StatusInstance : HitInstance`, landed via `NodeCombat.apply_status` / `land_on`
  on whichever `CombatWorld` the applier hands in — the same shadow/live split as
  every other hit.
- **Ticking.** An owned-set sweep in `Entity.resolve_turn_end`, its own step of
  `TurnManager.end_turn` after the cursor is nulled and before `finish_turn`
  (ADR 0040): the entity-host tick first, then the owned nodes over a snapshot of
  the owned set (skipping a node stripped mid-sweep), then one
  `StatusSpread.on_tick` sweep per def carried by an owned node whose `spread` slot
  is set (`FlatDiffusion` seeps 1 stack past a crowding threshold,
  `FractionDiffusion` a floored share of the gap, `SandpileSpread` topples every
  host at `T = masked degree + burn + keep` to its abelian fixed point and returns
  a `ToppleResult` of per-node net transfers plus each host's topple count and `T`
  from `stabilize`; its `on_tick` returns nothing, because the settle driver
  below owns every topple and the turn end's flush already ran it;
  senders are the owned set,
  landed through `SpreadApplier` on the live world; a null slot pays nothing).
  - It runs every played-out turn, the first included; never on `abandon_turn` (a
    death, the status sandbox's `disarm`) nor an adopted resync cursor.
  - A tick's damage suppresses the owner's next turn-start regen; a tick that kills
    the actor hits `abandon_turn` as a no-op and `end_turn` still hands on.
  - Peers reproduce it, since `EndTurnCommand` runs `end_turn` everywhere.
  - A **turnless host** (an in-scope entity with no `initiative` pool: a
    blocker, a dormant core) has no turn: it runs the same `resolve_turn_end` on
    the **world turn** (`TurnManager._end_world_turn`, one every N played turn
    ends, N = the living carriers; ADR 0055), in tree order, then the unowned
    `LINGER` rows tick once and the beat flushes. No upkeep, no regen.
- **Deallocation.** `CLEAR` rows release and spill
  (`NodeCombat.release_statuses(true)`, which hands back only the released rows);
  `LINGER` rows stay on the node, are never spilled, and while it is unowned tick
  once per world turn (`CombatWorld.tick_lingering`, ADR 0055). A death strip
  (`force_deallocate`, either branch of `EntityCombat.apply_cascade`) releases
  every row, `LINGER` included.
- **Spill.** One strip atom, `EntityCombat.strip_node(n, cause)`, is the only
  feeder: it notes the released rows on the world's removal collector before it
  clears ownership. `deallocate` strips with cause DEALLOC (`CLEAR` rows only);
  `force_deallocate` and both `apply_cascade` branches with cause DEATH (every
  row). Every strip spills — nothing strips quietly — and the flush is the
  enclosing beat's job, never the strip's. Live removals still pending when the
  actor hands off its turn are a bug: `TurnManager.end_turn` `push_error`s on
  `CombatWorld.has_pending_removals()`. A sandbox reset is a death of each
  entity (`deallocate_all_owned`) plus its own `flush_removals()`.
  `CombatWorld.flush_removals()` runs each def's `spread.on_removed` once per beat
  over the beat's whole removed union, so a node stripped in that beat never
  receives. A beat fed a rebuilt record (a live replay) lands the recorded
  transfers and computes nothing — spill is received, not reproduced. A beat is one
  `deallocate` / `deallocate_set`; one `schedule_index` group in
  `OutcomeApplier.apply`; one wave in `SpellResolver.resolve_against`; one turn-end
  tick step (flushed before its diffusion sweep); a gate-flip command flushes as its
  own beat; an entity death never flushes, it belongs to the beat that killed it.
  Curse and Bleeding are authored with `SpillSpread` (both triggers, 1.0, Mine);
  `SandpileSpread` spills
  nothing (a removed pile vanishes).
- **Sandpile settle** (corruption: `SandpileSpread`, burn 1, keep 0, Mine|Ally).
  `CombatWorld.settle_topples()` runs at the tail of every `flush_removals()`, so a
  pile pops inside whatever beat pushed it to `T` — a landing, a spell wave, a
  dealloc command, a gate toggle, the turn end. It drains a **worklist** of piles
  that may have become unstable (`CombatWorld._piles`, one per world — a shadow's
  dies in `free_shadow()`); it never walks owned nodes, so a beat with no sandpile
  movement visits nothing (`settle_visits` / `settle_rounds` count it, test-facing).
  Enqueued by: a row whose `StatusSpread.settles()` **rises** (`StatusHost._settle` →
  host contract `_on_pile_rose` → `note_pile`; landings, spread credits, `restore_row`);
  and a **degree event** on a holder that carries such a row (`note_pile_if_held`):
  a removal's neighbours (`note_removed`), a gate flip's endpoints
  (`AllocationSystem._note_gate_piles`), a core move's departed and arrival nodes
  and the entity's core pile (`move_core` flushes, so a pile the move made critical
  pops inside the command; an entry a replay beat leaves waits for the next
  computing beat). A degree event on a core node reaches its core pile too. Allocate is not an enqueue point: corruption
  is `CLEAR`, and a neighbour gaining an owner only raises `T`. A round takes the
  whole list; per sandpile row `(def.id, key)` one `SandpileSpread.stabilize` —
  itself a drain seeded with the popped live holders (`_settles`), resolving
  neighbours lazily through `_SettleField` — reaches the fixed point at the current
  degrees however deep the cascade; land the transfers through `SpreadApplier`
  (receivers re-enqueue via the hook and are found stable next round), then
  `StatusDef._on_burst` per toppled host (a normal hit: a depletion notes a removal).
  The flush loops spill → settle until a round topples nothing, so a burst kill's
  stacks vanish and the new degrees settle in the same beat; `burn ≥ 1` bounds it,
  and 32 rounds (`settle_round_cap`) / `max_topples` are `push_error` bug alarms
  only. **Two piles stand at a core** (#1568): the core node's rows topple like any
  node's; the entity's own rows (fallen through a cracked core) are a second holder,
  the `EntityCombat`, whose `T` is the core node's masked degree minus itself
  (a self-loop neither counts nor receives) + burn + keep, ownership read from the
  entity. It sends 1 down each of those edges, its burst lands on the entity pool
  (`DotTick.mint`), and no node lists it as a neighbour: it fills only by hits.
  Holders are the `StatusHost` duck type (untyped) across `StackField`,
  `SandpileSpread`, `StackTransfer`, `ToppleResult`, `SettleOp`. **Sync**: inside an attack the beat's first fresh
  landing records the settle on `HitInstance.settle` (`CombatWorld.SettleOp`s, in
  order, a later round's burst-kill spill included; wire columns `t_*` in
  `AttackRecord`, a core-pile holder riding as its core node + a `t_core` flag), and a non-empty `settle` marks a rebuilt hit recorded — the replay
  lands the ops and computes nothing. Every other beat (turn end, dealloc command)
  is reproduced. Known gap: a replayed burst kill takes `BattleSystem`'s derive
  branch for its cascade, like a turn-end DoT kill.
- **Sync.** `network/graph_snapshot.gd` carries `(status id, power)` rows in resync,
  and `WorldFingerprint` folds them.
- **Roster.** `effects/status/*.gd`: poison, corruption, curse, wither, bleeding,
  blindness, sunder, weakness, greed, mark, scout. `BlindnessStatus` (MULTIPLY on
  vision/sensor range), `SunderStatus` (MULTIPLY on armor) and `PoisonStatus`
  (unmitigated `DamageInstance.Type.TRUE` damage on `_on_tick`, flat or %-of-max-hp
  per `basis` — `HitInstance.AmountBasis`, resolved in `DamageInstance.land_on`; can
  kill through the ordinary `notify_depleted` cascade) are the reference shapes.
- **Not built.** General `EffectInstance`-hosted-on-a-node dispatch (an effect with
  its own `_on_*` hooks reacting to a node's lifecycle); the status slice is the
  purpose-built shape for that need.

## The DoT model

The status slice carries
five damage-over-time families, each named by the defensive axis it bypasses (the axes:
[defense-axes.md](defense-axes.md)). Each def authors its own decay
(`StatusDef.decay`, a `StatusDecay` strategy or `null`). The *why* — per-def
decay, uncapped stacks, no clamp, rows that differ in character rather than in
numbers — is
[ADR 0048](../adr/0048-status-decay-is-authored-per-def-rows-differ-in-character-not-numbers.md);
the row is an integer count
([ADR 0032](../adr/0032-status-stacks-are-integers-a-def-derives-any-fractional-effect-from-the-count.md));
the hosts (node, or the entity once the row falls through a cracked core) are
[ADR 0024](../adr/0024-status-effects-have-two-hosts-and-fall-through-a-cracked-core.md).
What could still come (contagion, the other families' arrows and spells)
is `docs/design/damage_over_time.md`.
A cure (`Cure`, `CureEffect`) reads and clears a spot's two holders: on a core
node the core's rows count toward the walk (`StatusFilter`) and the need, and
the dose clears them first, in cure-table order, then the node's
(`Cure.plan`'s `core_cleared`, `CureInstance.on_core`); the heal lands on the node.

| Family | Denomination | Answers | Weak against |
|---|---|---|---|
| **Poison** | flat HP per stack per tick, unmitigated | armor, a sub-zero `min_damage_taken` | bulk |
| **Corruption** | `T` × % of max HP per topple, unmitigated; nothing ticks | bulk (the CON stacker) | rarity and cure only |
| **Curse** | raises `min_damage_taken` by its stacks | armor: every hit lands again | deals nothing alone |
| **Wither** | multiplies `healing_received` down, below zero | the heal aura and regen | nodes nobody heals |
| **Bleeding** | ⌈stacks × `bleed_rate`⌉ flat HP per tick, unmitigated; the row ×`exert_growth` when its host exerts (`BleedingStatus`) | the kiting core and the node that keeps attacking | a host that rests: `RampDecay` closes the wound faster each still turn |

There is **no per-tick clamp**: every family is lethal in sufficient amount.

**Stacks.** A row is one whole count, `NodeStatus.power: int` (ADR 0032);
a fraction is rounded where it is minted — the landing fold, a decay, a spill —
never on the row. Each tick `_on_tick` spends the
pre-decay stacks, then the row decays by its def's shape (the table below); a
`FractionDecay` row floors each step and clears below 1. Stacks are uncapped.

**Landing.** `landed = fold(<family>_stacks_per_hit(attacker), base_add = per_hit)`
— `StatusDef.stacks_per_hit`: the per-hit amount authored on the applier (ammo
type, on-hit effect, blade vertex) is the `base_add` of the attacker's stacks
stat, whose INCREASE/MORE scale the total ([ADR 0029](../adr/0029-related-stats-compose-through-parents-folded-at-read-and-every-stat-takes-every-bin.md)
— no separate potency stat). Computed once at land on the landing world and rounded
half-up to a whole count (`StatusDef.round_half_up`: 1 × +49% lands 1, 1 × +50%
lands 2). Hit size never scales stacks. Poison, corruption, curse and wither's
stacks stats share one parent umbrella, `dot_stacks_per_hit`, which lands more
stacks and never scales damage; bleeding, blindness, greed, mark (`mark_stacks_per_hit`)
and weakness each carry a parentless `<id>_stacks_per_hit` and sit outside it.
Sunder and scout author no `StatusDef.stacks_stat_id()` (a flat landing count).

**Resistance** (`poison_resistance`, …, default 0, a fraction) is read on the
**host** and filters the accumulated row at effect time, never the incoming hit
([ADR 0031](../adr/0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md)):
each apply and each tick counts `row − cancelled`, with
`cancelled = ⌈row × res − ½⌉` capped at `row` — round half-down
(1·1% → 1, 1·50% → 1, 1·60% → 0, 10·25% → 8, 20·1% → 20). **Negative
resistance is vulnerability**: there is no floor, so below 0% `cancelled` goes
negative and more stacks act than the row holds, the half still falling the
attacker's way (4·−50% → 6, 1·−50% → 2, 10·−100% → 20); a vulnerable node's
DoTs tick harder too. The row itself decays from its unresisted size. At
**≥ 100%** stacks do not land (the authority resolves the hit to 0 and the record carries it); a standing row deals 0 and
still decays. `StatusDef.next_tick_damage` is the first term of the health-bar
projection, which walks the raw row down tick by tick, resisted then floored.

**The regen gate.** A DoT tick is damage and closes the node's regen gate
(`node-hp.md`). The one exception is wither: a heal inverted by
`healing_received < 0` is damage that leaves the gate open, so a withered node
left alone ramps its regen up and heals itself toward death, and the core aura
unheals its own neighbourhood — `NodeCombat._withered_heal`. It lasts only
while Wither holds `healing_received` below zero: as the stacks decay the
multiplier climbs back through zero, nulling healing, then restoring it.

**Decay shapes.** Falloff and duration are per def, never stats (#1060) — the
`StatusDef.decay` slot, one shared stateless `StatusDecay` per def:

| Status | Shape (`effects/status/*.tres`) |
|---|---|
| Poison, Curse, Sunder, Marked, Scouted | `FlatDecay`, `per_tick` 1 |
| Wither, Weakened | `FractionDecay`, `fraction` 0.25 removed |
| Blindness | `FractionDecay`, `fraction` 0.7 removed, ACCUMULATE — see [node-subtypes.md](node-subtypes.md) decision 20 |
| Bleeding | `RampDecay` — `start` 1, `step` 1 while resting; the ramp position is `NodeStatus.decay_step`, reset by exertion |
| Corruption, Greed | `null` — never decays |

Authoring gotcha: the `.tres` knob `FractionDecay.fraction` is the fraction
**removed**, so a row retaining *f* is authored as 1 − *f* (wither 0.25 keeps
0.75); blindness's 0.7 is the fraction removed (#1090). The shape law is
`test/unit/effects/test_status_decay_shapes.gd`.

## Status rows: `group_by` keys them, `visible_if` gates the count (#1343)

A status row's identity is `(def.id, key)`. The key comes from the def's
`group_by` — a GDScript `Expression` over the **applier**, parsed once and
cached (the `ExpressionFilter` precedent). `visible_if` is a second, boolean
expression a reader asks through `StatusDef.count_visible(row, viewer_camp_id,
viewer_id)`; nothing reads it with a viewer yet.

| Expression | Inputs | Empty means |
|---|---|---|
| `group_by` | `camp_id` (applier's `faction.id`, `&""` none), `applier_id` (`entity_id`, `0` none) | `true`: one shared row — every shipped def |
| `visible_if` | the row's `camp_id` / `applier_id` (its latest applier), `viewer_camp_id`, `viewer_id` | every viewer reads the count |

- A key is a bool, int or StringName, never an Object, so a row replays alike
  on every peer. `false` (independent rows) is **refused** with `push_error`
  and the apply is a no-op — it needs a deterministic application id first.
- `apply_status(def, power, camp_id, applier_id)` files the landing; the row
  records the latest applier. `adjust_power` / `get_status_power` take the
  key (default `true`); `remove_status(id)` drops every row of the def,
  `remove_row(id, key)` one. A spread credit that creates a row carries no
  applier (moving is not landing).
- Spread and spill run per row: a `StackField` reads one `(def, key)`, its
  rule stamps that key on each `StackTransfer`, `SpreadApplier` lands it there.
  A recorded spill does not carry its key on the wire yet (the `AttackRecord`
  spill columns): a replay lands under `true`, identical for every shared def.
- A save stores each row as `[def_idx, power, key, camp_id, applier_id, decay_step]`
  (`SaveFile.FORMAT_VERSION` 2) and restores the key verbatim (`restore_row`),
  never recomputed through the def.
- An `Expression` parses an unknown identifier fine, so `StatusDef.parse_error`
  also dry-runs it on neutral inputs; the setters warn with it and
  `test_status_grouping.gd` sweeps every authored `.tres`.
