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
  `FractionDiffusion` a floored share of the gap; senders are the owned set,
  landed through `SpreadApplier` on the live world; a null slot pays nothing).
  - It runs every played-out turn, the first included; never on `abandon_turn` (a
    death, the status sandbox's `disarm`) nor an adopted resync cursor.
  - A tick's damage suppresses the owner's next turn-start regen; a tick that kills
    the actor hits `abandon_turn` as a no-op and `end_turn` still hands on.
  - Peers reproduce it, since `EndTurnCommand` runs `end_turn` everywhere.
- **Deallocation.** `CLEAR` rows release and spill
  (`NodeCombat.release_statuses(true)`, which hands back only the released rows);
  `LINGER` rows stay on the node, are never spilled, and while it is unowned tick
  on every entity's turn end (`CombatWorld.tick_lingering`). A combat or death
  strip (`EntityCombat.apply_cascade`) releases every row. A bare
  `force_deallocate` outside a cascade releases `CLEAR` rows without spilling.
- **Spill.** Exactly two feeders note released rows on the world's removal
  collector before the strip: `EntityCombat.apply_cascade`'s per-node body (cause
  DEATH, both worlds; every forced removal, entity death included) and
  `AllocationSystem._deallocate_unchecked` (cause DEALLOC).
  `CombatWorld.flush_removals()` runs each def's `spread.on_removed` once per beat
  over the beat's whole removed union, so a node stripped in that beat never
  receives. A beat fed a rebuilt record (a live replay) lands the recorded
  transfers and computes nothing — spill is received, not reproduced. A beat is one
  `deallocate` / `deallocate_set`; one `schedule_index` group in
  `OutcomeApplier.apply`; one wave in `SpellResolver.resolve_against`; one turn-end
  tick step (flushed before its diffusion sweep); a gate-flip command flushes as its
  own beat; an entity death never flushes, it belongs to the beat that killed it.
  Curse is authored with `SpillSpread` (both triggers, 1.0, Mine).
- **Sync.** `network/graph_snapshot.gd` carries `(status id, power)` rows in resync,
  and `WorldFingerprint` folds them.
- **Roster.** `effects/status/*.gd`: poison, corruption, curse, wither, bleeding,
  blindness, armor break, weakness, greed, hex, scout. `BlindnessStatus` (MULTIPLY on
  vision/sensor range), `ArmorBreakStatus` (MULTIPLY on armor) and `PoisonStatus`
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
What could still come (cures, contagion, the other families' arrows and spells)
is `docs/design/damage_over_time.md`.

| Family | Denomination | Answers | Weak against |
|---|---|---|---|
| **Poison** | flat HP per stack per tick, unmitigated | armor, a sub-zero `min_damage_taken` | bulk |
| **Corruption** | % of max HP per stack per tick, unmitigated | bulk (the CON stacker) | rarity and cure only |
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
stacks and never scales damage; bleeding, blindness, greed, hex (`hex_stacks_per_hit`)
and weakness each carry a parentless `<id>_stacks_per_hit` and sit outside it.
Armor break and scout author no `StatusDef.stacks_stat_id` (a flat landing count).

**Resistance** (`poison_resistance`, …, default 0, a fraction) is read on the
**host** and filters the accumulated row at effect time, never the incoming hit
([ADR 0031](../adr/0031-status-resistance-filters-the-accumulated-row-at-effect-time-on-the-host.md)):
each apply and each tick counts `row − cancelled`, with
`cancelled = ⌈row × res − ½⌉` clamped to `[0, row]` — round half-down
(1·1% → 1, 1·50% → 1, 1·60% → 0, 10·25% → 8, 20·1% → 20). The row itself decays
from its unresisted size. At **≥ 100%** stacks do not land (the authority
resolves the hit to 0 and the record carries it); a standing row deals 0 and
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
| Poison, Curse, Armor break, Hexed, Scouted | `FlatDecay`, `per_tick` 1 |
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
