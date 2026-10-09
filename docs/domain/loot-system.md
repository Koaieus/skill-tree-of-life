# Loot system (XP reward, tempo award, SkillDust)

`systems/loot_system.gd` is the authority for **killing-blow rewards**. It reacts
to `Events.entity_dying(victim)` and does three things:

1. **XP reward** — the killer gains XP for the **territory**
   the victim held at death (its core included). Never for its level. A
   per-node trickle rides `BattleSystem.cascade_started` alongside this (see
   below — it can't ride `Events.skill_node_depleted`).
2. **Tempo award (#888)** — a HOSTILE killing blow spends 1 `tempo` to refund
   1 `action_points`, once per turn, the pool's own cap acting as the latch.
   See "The tempo award" below.
3. **SkillDust drop** — the victim's former core node
   becomes a claimable relic carrying a `SkillDustAddon`, a **weighted draw
   over three provenance buckets** offered as N **rounds of pick-1-of-3**.

## Provenance buckets

Node modifiers are only *lent* by the graph (granted on allocation, released
back to neutral on death), so the loot pool never takes the live modifier: only
a `duplicate(true)`d COPY enters it, and the strip returns the original to the
graph untouched. The draw reads THREE source arrays, each a straight provenance
bucket — a rule of the game (board innate), part of how this build was assembled
(a grant), or a transient effect (never offered) — weighted by
`@export var weight_bucket_*` (equal by default, tuned in the inspector):

| bucket | source array |
|---|---|
| node grants | the victim's owned subgraph's `SkillNode.modifiers`, snapshotted pre-strip (core excluded — it's its own bucket) |
| class/register grants | `Entity.core_modifiers` — see below |
| board innates | `EntityStatBoard.intrinsic_modifiers` |

**Stealing a level-scaler is the point, not a hazard:** looting a piece of
another build's growth curve is the compounding channel that makes the loop work,
so no filter excludes level-reading formulas.

**Territory scale is rewarded as XP too** (the empire term): XP for the scale of
the kill, plus a richer node-grant bucket for the specific mods it was running.

### `Entity.core_modifiers` — the granted-atom register

Everything ever permanently granted onto an entity's core — original
class-template grants AND previously-looted grants alike — lives in one place:
`Entity.core_modifiers`, an **unflattened** ledger. `Entity.grant_core_modifier(m)`
is the ONLY path that writes to it (mirrors `m` onto `stat_board` too, same
shape as `EffectContext`'s handle-owned pattern); `CoreClass.apply()` and
`SkillDustAddon`'s claim flow both route through it. Two honest layers: the
register is what the loot draw reads (composites stay intact — a
`loots_as_unit` pack survives a loot round-trip as one atom, closing #185's
re-lootability gap); the board is the flattened, bound leaves stats compute
from. There is deliberately no separate "looted" bucket — a looted grant
re-enters the SAME register a class grant lands in, so it is exactly as
re-lootable.

## Killer attribution — resolved here, not on Entity or the bus

Death fires **synchronously** inside the attacker's turn: core-HP overflow
(`SkillNode.take_damage`) and the cascade's chip damage
(`BattleSystem._on_node_depleted`) both run in the attacker's `launch_attack`
call stack. So `turn_manager.current_entity` at `entity_died` **is** the killer.

LootSystem holds an injected `@export var turn_manager` (DI per
`.claude/rules/scene-composition.md`, wired in `game_root.tscn`) and resolves the
killer itself. LootSystem is the rewards authority, so attribution lives with the rewards, not
elsewhere:

- **Not on `Entity`** — it only *announces* death (`entity_died`, a 1-arg signal
  with no `killed_by`), it doesn't also attribute it.
- **Not in `BattleSystem`** — it owns *attacks*; folding reward attribution in
  would spread reward logic across two systems.

`_resolve_killer` self-guards (victim ≠ killer → non-attack death, no reward) and
null-guards a missing TurnManager (headless tests).

> **Thorns / counter-damage caveat:** those would deal a killing blow on the
> *defender's* turn, breaking the "turn holder == killer" assumption. They aren't
> implemented yet; when they land, attribution needs real source-threading
> (the `DamageInstance.source` is non-uniform today — plan / node / spell-state —
> so it can't carry the attacker cleanly without a dedicated pass).

## Ordering is by phase, not tree position

Death is a **two-phase** announcement (`Entity.die`), so consumers pick a phase
instead of racing on connection order:

```
Events.entity_dying  → LootSystem: draw core mods + attach SkillDust, award kill
                        XP (territory-scaled)  (corpse STILL owns its nodes,
                        its entity-hosted status rows still applied)
(Entity.die)         → release the entity-hosted status rows
Events.entity_died   → AllocationSystem: force-deallocate every owned node
                        (incl. core → neutral relic)
                     → GameRoot: player game-over / NPC despawn
```

`emit()` is synchronous, so **every `entity_dying` handler finishes before any
`entity_died` handler runs** — the phases sequence themselves, and LootSystem's
position in the scene tree is **irrelevant** (the editor is free to reorder
`Systems` children). LootSystem needs the pre-strip world for the **XP
payout**, which counts the territory the victim still owns
(`navigator.get_mirrored_nodes()`), gone once AllocationSystem strips it. The
dust *attach* is order-independent w.r.t. the strip — the addon survives it
(`force_deallocate` only pops `node.modifiers`, not addon children), and the
core-mod source comes off `core_class` + the core node.

Within the `entity_died` phase, AllocationSystem-before-GameRoot holds on the
child-before-parent ready order (GameRoot is the root, so its `_ready` connects
last and fires last) — not the fragile sibling order.

## The XP reward (`_award_kill_xp`)

XP is paid for **territory removed**, plus a flat bonus when the core itself
died. One rate, no multiplier, no rate-switching:

```
XP = xp_per_node_killed(5) × |nodes this attack removed, core included|
     + victim.stat_board.core_kill_xp.value           (only if the core died)
```

Every term is read through the `bounty` stat with its rate as an overlay
`base_add`: each node's `xp_per_node_killed` through the node's local read
(node + entity modifiers, `_node_payout`), the core bonus through the entity
board's read alone (`_entity_payout`). At zero `bounty` modifiers that is the
formula above; Greed's Avarice face plants `INCREASE` on it (+10% per stack).

The core node is simply one of the counted nodes — there is no folded-in "+1"
for it anywhere in the arithmetic (owner, 2026-09-07: "no more killing entity
that has many nodes makes those nodes count for more XP, it just muddies the
calculations"). The size-shaped reward for a fixed-size victim lives entirely in
`core_kill_xp` (`stats_system/defs/core_kill_xp.tres`), a per-board stat rather
than a multiplier on the whole payout — owner-tunable per entity and reachable by
a modifier like any other stat. Defaults: 60 on `default_entity_board.tres`
(players/NPCs), 20 / 40 / 60 on the small / medium / large blocker boards.

`_kill_xp_total(removed_node_count, kills_entity, victim)` is the one place
this formula is written — shared by `_award_kill_xp` (which builds the correct
SET before calling it) and `preview_kill_xp` (which passes a count straight
through). Never duplicate this arithmetic elsewhere.

**NO NETTING.** `_award_kill_xp` doesn't price the whole board and subtract
what the trickle already paid — it builds the SET of nodes not yet paid and
prices that set once:

- `removed_this_attack` — the **attack-scoped removal ledger**: every node the
  current attack has taken off this defender. Fed by BattleSystem's
  `cascade_started` (the depleted node **plus everything it islands**), cleared
  on every `attack_launched`.
- `held_at_death` — non-core nodes the victim still owns when it dies
  (`_held_nodes`, off the pre-strip navigator mirror).
- the core the victim died on — always counted, so a landless D-19 elite still
  pays its `core_kill_xp` bonus.

These three sources are **unioned**, then whatever the ledger already paid as
trickle (iff `award_xp_on_node_kill`) is excluded from that union before
pricing — a set difference, not an arithmetic correction. Both
`xp_per_node_killed` and `core_kill_xp` are `@export`/per-board stats.
Territory scale is paid **as XP, deliberately not as looted stats**.

**Node count is the honest axis, not victim level:** D-19 pins an enemy's level to its starting node count, so a level term would double-count territory.

### The ledger makes the payout order-independent

BattleSystem's cascade strips nodes one at a time and chips `dealloc_damage` off
the defender's core HP per node, so the core can die **anywhere inside that
loop** — and a payout that read only `held_at_death` would shrink the more of
the victim the attack destroyed. A forking spell has the same shape: once it
kills the core mid-propagation, every later hop lands on neutral nodes.

The ledger makes the payout a function of **what the attack removed** instead of
of loop ordering. The two sets **overlap** mid-cascade (the ledger is recorded
before the strip loop walks it), so they are **unioned, not summed** — and that
union is invariant: a node moves from one side to the other as the loop
progresses and the total doesn't move. Pinned by
`test/integration/systems/test_kill_xp_ledger.gd`.

**Scope is one attack, not one turn.** The bonus means "this blow". A node broken
in an earlier attack already collected its trickle and is not re-counted at bonus
rate later.

### Whittle vs. snipe — pay identically for territory

At defaults against a 20-node enemy on the default board (`core_kill_xp` 60):

| path | trickle | killing blow | total |
|---|---|---|---|
| kill in one attack (snipe, or cut the arm out from under it) | — | `20 · 5 + 60` | **160** |
| break 19 limbs over earlier attacks, then the core | `19 · 5` = 95 | `1 · 5 + 60` = 65 | **160** |

The union/NO NETTING rule makes this identical **by construction** — the
territory term is always `xp_per_node_killed × total nodes removed`, whichever
attack removed them, and `core_kill_xp` is added exactly once regardless of
path. What premium a fixed-size victim (a blocker) is worth comes entirely from
`core_kill_xp` being nonzero and size-shaped on its own board (20 / 40 / 60 for
small / medium / large) — not from a kill-order bonus.

### Why the trickle rides `cascade_started`

It can't ride `Events.skill_node_depleted`: that signal's own handler
(BattleSystem's cascade) clears `owned_by`, and connection order is tree order —
so a second consumer has no safe way to read whose node it was.
`BattleSystem.cascade_started(layers, defender)` fires **before** the strip,
carries the defender, and carries the *whole* removal set rather than just the
impact node. LootSystem takes an `@export var battle_system` NodePath for it
(DI per `.claude/rules/scene-composition.md`, wired in `game_root.tscn`).

The ledger is deliberately **plain state on LootSystem, not a payload on the
bus** — it's transient per-attack bookkeeping, not a domain fact anyone else
should be reading.

## The tempo award (`_award_kill_tempo`, #888)

A once-per-turn +1 AP reward for a killing blow, owner's proposal LAN-10:
*"get 1 AP on landing an entity-killing blow, max 1 of those per turn (killing
a Blocker would also count, making killing them more fun instead of tedious
and a drag)"*. Same gate as the XP reward — HOSTILE attitude
(`killer.attitude_to(victim)`), killer alive — plus one more: the pool itself.

Represented as a board stat, **`tempo`** (`stats_system/defs/tempo.tres`,
`PoolStat`, cap 1, `per_turn_mode = REFILL`), not a hardcoded rule or a
`CoreClass._on_killing_blow` hook — the same seam `ap_transfer_rate` already
uses, so a class or relic can raise or zero the cap with a plain modifier. A
reward does `tempo.deplete(1)` + `action_points.replenish(1)`:

- **The cap IS the once-per-turn latch.** `tempo.available() < 1` → no
  reward, so a chain-kill spell dropping two victims in one cast still nets
  exactly one refund. No separate bool, no per-attack ledger, unlike the XP
  trickle above.
- **Source-agnostic on purpose.** `tempo` is named for the budget, not for
  this one source — future tempo sources (#887, severance/consolidation)
  drain the same pool, so the cap stays the single latch. A relic raising the
  cap to 2 grants two rewards/turn; a modifier setting it to 0 opts an entity
  out entirely.
- **Blockers count with no special case.** They're faction-less, and
  `Entity.attitude_to` reads a null faction as HOSTILE, so a Blocker victim
  pays out exactly like a real entity.
- **The refund always fits under the `action_points` cap.** `_commit`
  deducts `ap_cost` before `_apply_outcome` runs the replay in which the
  death fires (see `.claude/rules/attack-timeline.md`), so the killer is at
  ≤ cap−1 `action_points` when `entity_dying` lands — this breaks only if an
  `ap_cost = 0` attack ever kills.
- **Rides the reveal clock during replay exactly as the XP reward does** — it
  fires off the same `Events.entity_dying(victim)` phase, so a peer reproduces
  it from the same `AttackRecord` rather than opening its own turn (see
  `.claude/rules/multiplayer-sync.md`).
- **Independent of `core_kill_xp`** (#774) — same event, different award; the
  two payouts don't interact.

`award_tempo_on_kill` is a per-side-effect kill-switch, same shape as
`award_xp_on_kill` / `award_xp_on_node_kill`, for a sandbox tab to neuter the
reward while keeping 1:1 wiring with the real system.

## The loot draw (`_draw_payload`) — the three-bucket weighted union

The candidate pool is the union of the three provenance buckets above, each
expanded via `_expand_for_loot` (a `loots_as_unit = false` pack splits into
per-leaf candidates; a `true` pack, or a plain modifier, stays one candidate).
Every candidate is `duplicate(true)`d, and each carries its bucket's weight
(index-aligned `weights` array) for the round-by-round weighted sample at claim
time — see below. `would_cycle` is **deliberately not checked here**: the
claimant isn't known until someone allocates the relic, so cycle-safety is a
claim-time concern.

`rounds` (the number of pick-1-of-3 **rounds**, not a flat count) is a
**constant**, `LootSystem.loot_rounds`, against the pool's **total** size across
all three buckets:

```
N = loot_rounds     clamped to [0, total supply], then to supply-1 whenever supply ≥ 2
```

Every kill offers the same `loot_rounds` (default 3) regardless of victim
tier — the reduced per-round *value* (below) is what a small blocker pays in,
not a shorter draw.

### Loot value scales with victim tier (#775)

Each drawn candidate's coefficient (`StatModifier.value`, or every leaf's
`value` inside a `loots_as_unit = true` composite that survives whole) is
multiplied by `LootSystem.loot_fraction_by_tier[clampi(victim.entity_tier - 1,
0, size - 1)]` — an exponential ladder, authored `[0.25, 0.5, 1.0, 2.0]` (owner,
2026-09-13: *"1: 0.25 2: 0.5 3: 1 (4: 2? Maybe reserved for bosses)"*). Players
and ordinary NPCs default to `entity_tier = 3` → the full 1.0 rate; removable
blockers author 1 / 2 / 3 for small / medium / large → 0.25 / 0.5 / 1.0. The
scale is applied to the **duplicate** entering the loot pool, in `_draw_payload`
— never to the victim's own modifier, which keeps computing at full strength
for as long as the victim is alive (a dormant core's intrinsics still "work" by
being lootable, per the owner: *"a dormant core DOES use its intrinsics — by
exposing them as loot"*).

An `INT`-typed target stat (`cast_range_hops`, `blade_size`, `xp_per_turn`) coerces
once, at the end of the pipeline — a lone 0.25 coefficient can read as **+0**
until a second copy stacks it past a whole number. Accepted as-is (owner,
2026-09-13): showing the player the effective value is #792's job, not this
system's.

**N is capped below the supply.** A keep-count that reaches the full supply
turns every round into a no-choice auto-grant and the picker never pops; the
supply-1 cap is the structural guarantee that a choice survives any retune of
the pool or of `loot_rounds`.

## SkillDust pickup — N rounds of pick-1-of-3

`SkillDustAddon extends SkillNodeAddon` sits on the neutralised relic core and
subscribes to `carrier.owner_changed`. When **any** entity allocates the relic
(owner goes non-null — the `owned_by == null` guard skips the death-strip so
only a real pickup fires), it runs one round per `rounds`, each as its own
`LootRoundCommand` (see "The round is the wire unit" below):

1. Filter the **remaining** pool by `collector.stat_board.would_cycle(m)` —
   against the collector's **current** board, which already reflects every
   grant an earlier round in this same relic made.
2. **Zero cycle-safe survivors** → stop; this relic grants no more.
3. **Exactly one** → no real choice, auto-grant it, skip the picker.
4. **2–3 survivors** → weighted-sample up to 3 ("roll a bucket by weight, then a
   member") and emit `Events.loot_pick_requested(LootPickRequest)` for a
   **pick-1** choice.
5. The chosen mod is granted **immediately**, via `Entity.absorb_core_modifier`
   (#775 — the merge verb; see below) — before the next round's `would_cycle`
   check runs. The un-picked offer members are NOT removed from the pool;
   they're eligible again in a later round's fresh sample ("single pick, then
   new draw, the next pick is always clean").

### The merge (#775) — equivalent grants add coefficients, not copies

`Entity.absorb_core_modifier(m)` is what `SkillDustAddon._grant_mod` calls
instead of `grant_core_modifier` directly. A `CompositeStatModifier` candidate
**always appends whole** (never merges — a bundle's identity is the point of
keeping it one atom). **Only a formula-bearing ADD_BASE / INCREASE / ADD_BONUS
candidate may fuse** (ADR 0043): `v₁·f + v₂·f = (v₁+v₂)·f` is lossless, a
formula MULTIPLY is not, and a SET has no composition — so a static modifier,
every MULTIPLY and every SET append as their own bound instance. A fusible
candidate is matched by
`StatModifierCodec.merge_key(m)` — its wire form (`to_dict()`) with `"value"`
erased, so "same stat, same op, same formula" without caring how much of it —
against, **in order**:

1. **`collector.stat_board.intrinsic_modifiers`** — the collector's own board
   rules. A file-backed match here (should never happen post-`duplicate(true)`,
   but guarded) is **skipped as a target**, not privatised — the search just
   continues into the next bucket.
2. **`collector.core_modifiers`** — previously-granted atoms, including
   class-template grants.

**No match** → the ordinary `grant_core_modifier` append. **A match whose
`resource_path` is non-empty** (a FILE-BACKED shared instance — a class-template
grant is the SAME `.tres` sub-resource on every entity of that class, per
`CoreClass.apply`'s no-duplication contract) is **privatised first**:
`StatBoard.privatize_register_entry` swaps the register slot for an unshared
`duplicate(true)`, rebinds it on the board, and the merge lands on the
duplicate — the shared original, and every other entity of that class, is
never touched. Otherwise the match is mutated in place: `target.value += m.value`
(the setter already `emit_changed()`s — no rebind, no dirty-marking). Either
way, exactly one `Events.stat_modifier_changed(collector, target, CORE, true)`
fires, carrying the **merged target** — never the just-absorbed copy — so a
display surface (#792) has one hook to refresh from regardless of merge vs.
append.

**A merged ratio rule is a line and reads as one (#891, ADR 0016).** The
`RatioFormula` contributes `value × source / divisor` with no floor; the INT
target floors its finished total once, so a `+1 XP / Turn per 5 WIS` intrinsic
merged with a t1 copy (`value 1.25`) hands out its next point at WIS 4 rather
than sitting inert until four copies stack. `StatModifier.format()` normalises
the merged coefficient back to a unit numerator — `value 4/3` over `/5` renders
`+1 XP / Turn per 3.75 WIS`, and once the step drops below one point of source
it flips to `+20 XP / Turn per WIS` (never `+1 per 0.05`). At `value 1` the
string is byte-identical to the unlooted rule, so nothing churns until a merge
actually happens.

**The merge key includes the formula dict, so a divisor mismatch silently
appends instead of merging.** A player's `blade_damage /20` and a board still
carrying `/10` for the same stat are different keys — pinned as visible
behaviour, not a bug: every future owner divisor pass (`.claude/rules/stats-system.md`'s
intrinsic table) must move all four boards (`default_entity_board.tres` +
the three `entity/blocker/blocker_*_board.tres`) in lockstep, or loot of that
rule quietly stops merging between them.

**Late-join:** `Stat._reconcile_modifiers` matches an incoming wire form
against a bound modifier's FULL `to_dict()` (value included), so a joiner
whose board still authors `1.0` for a rule the host merged to `1.25` would
otherwise fail to match, mint a fresh bound `1.25` instance, and leave the
stale `1.0` sitting in the register/intrinsics array unbound.
`StatBoard.read_dict` closes this by running `sync_register_from_wire` on
`intrinsic_modifiers` **before** the per-stat reconcile (privatising a
file-backed match the same way the merge does), and firing a `restoring(d)`
signal `Entity` uses to do the same for `core_modifiers` — so by the time the
reconcile runs, the register's own entry already carries the wire's value and
gets kept in place. The register entry IS the bound instance afterward; no
separate re-pointing step exists.

**Why per-round, not one up-front filter.** Two candidates can each be
individually cycle-safe yet jointly cyclic — a single filter checked once
against the board as it stood at draw time would let both through, and the
second `add_modifier` would land on the board's own last-resort rejection (a
silently smaller reward). Checking `would_cycle` again each round, against the
board as it now stands, catches that: once round 1 binds the first candidate,
round 2's check sees it and excludes the second before it's ever offered.

### The handshake (load-bearing, tri-state)

`emit()` is synchronous. `LootPickRequest.claim` is the pre-emption flag:

- **`LOCAL`** — **HudRoot** listens, filters `request.collector == _player`, sets
  it **synchronously** and shows `LootPicker` (a modal — it **pauses the tree**
  and runs at `process_mode = ALWAYS`, the `PauseMenu` idiom; a mouse-filter
  alone wouldn't stop the `D`-key deallocate, which rides `_unhandled_input`).
  On confirm it unpauses and calls `request.resolve(chosen)`, possibly real
  seconds later.
- **`REMOTE`** — a human on another peer owes the answer. The host must NOT
  auto-resolve: it parks the request in `LootPickRegistry` and waits for a
  `PickLootCommand`. Dormant today (nothing reports a remote collector — there
  is no upward channel and no peer roster; #463 owns both).
- **`UNCLAIMED`** — NPC relic, headless test, no HUD mounted, or an enemy
  scavenging a dead player's relic (nothing here gates by faction). The addon
  **auto-resolves a random 1-of-the-offer** right after emit returns.

That keeps NPCs, headless tests, and the no-HUD path all on the auto-resolve
branch — **the default the test suite exercises**. It stays a host-only roll and
is exempt from the seeding rule: a peer receives the result rather than
reproducing it.

Note what the NPC case is *not* keyed on: nothing anywhere asks "is this
collector AI-controlled". `UNCLAIMED` means nobody on this machine put their
hand up, and an NPC gets the auto-roll because HudRoot filters on
`request.collector == _player` and walks away. One consequence worth keeping in
mind before adding a second listener: any handler that claims a request without
that filter would hang an NPC's round on a picker nobody will ever answer.

`test/integration/entity/test_ai_claims_loot.gd` pins the whole chain from the NPC end
— an [AIController] decides the kill, claims the relic with its own
`AllocateCommand` through a real `CommandApplier`, and auto-resolves both stat
rounds and the terminal spell round inside its turn. Every other loot test
drives the claim by calling `AllocationSystem.allocate()` by hand, which skips
the host gate and the command chain entirely.

The claim is tri-state, not a bool, because a bool cannot say "somebody IS
picking, just not here": a remote human's request would read as unclaimed and be
random-picked before the answer could arrive.


`resolve()` is **idempotent**. The addon lingers on the relic until every round
has resolved (possibly across several real seconds if the player is picking),
then `queue_free`s.

### The round is the wire unit (#522)

Each round is a `LootRoundCommand`, submitted from the previous round's
application (the applier QUEUES rather than re-entering, by documented design).
Two states, one type, copying `LaunchAttackCommand`:

- **empty record — INITIATE.** The authority filters, samples, offers, awaits
  the pick, grants, and stamps what it did. That stamp is what `CommandChannel`
  broadcasts.
- **populated — REPLAY.** A peer grants exactly what is recorded. It does not
  roll, filter, raise a request, trim its pool, or advance the chain.

**Why the round and not the pick.** Steps 3 and 4's auto-paths above never raise
a `LootPickRequest` at all, so a `PickLootCommand`-shaped vocabulary would leave
every NPC relic claim diverging a peer while the human-pick case looked fine.
The round covers all three uniformly; the human pick is just the one with
latency in the middle. A final round carrying no grant and `finished = true` is
what frees the relic on every peer — one record for all five ways the chain can
end (collector dead, rounds exhausted, pool dry, no cycle-safe survivor, empty
sample).

**Host-gated, and driven by the handler (#1138).** A peer applies the confirmed
`AllocateCommand`, `owned_by` flips, and the relic's `SkillDustAddon.claimed`
fires *there too* — so without the gate the peer would open its own round and
roll its own offer. The one gate is `LootSystem._on_relic_claimed`
(`command_applier.is_authority`), reached for every relic `LootSystem` drops via
`adopt_relic`; a hand-attached relic claims nothing until adopted. The loop is
`LootRoundCommandHandler`, in two halves: the **resolve side** (`open_round` /
`resolve_next`, authority only, outside any `apply`) offers, awaits the pick and
submits the stamped round through the applier's queue; the **replay side**
(`apply` → `_land`, every peer) grants, frees on the final round and, on the
authority, fires the next resolve. The addon only offers (`offers_for`) and
lands (`grant_mod` / `grant_spell` / `finish`). A null applier (headless
fixture, editor) is a supported configuration meaning "no pipeline": `_settle`
self-replays the drawn instances straight through `_land`, which is why the
existing suite needs no applier.

**No ending the turn while picking** (owner call, 2026-08-22) needs no gate of
its own. The round awaits the pick *inside* the command's application, so
`CommandApplier.is_applying` stays true for the duration and
`PlayerInputController.can_player_act` already returns false — the End Turn
button greys out through `player_can_act_changed` rather than silently
no-opping.

## XP must route through the pool

`_award_kill_xp` calls `board.xp.replenish(amount)` — **not** a raw
`set_current`. The pool's `on_pool_filled` → `replenished` cascade
(`Entity._on_xp_replenished`) is what mints SP and bumps the level. Bypassing it
would silently skip the level-up. See `.claude/rules/stats-system.md` (pool
upkeep / GrowablePoolStatDef).

## Playground

The **Loot** live tab (`addons/sandbox_host/tabs/50_loot_tab.tscn`, embedding
`addons/loot_sandbox/loot_sandbox_panel.tscn`, #260) drives a real kill on
demand and shows the rewards land: the death cascade, a SkillDust relic
blooming on the victim's former core, and the killer's live XP/level. A phase
selector demonstrates the per-side-effect kill-switches
(`award_xp_on_kill` / `drop_skill_dust_on_death`) by toggling one reward off at
a time. Single attacker + victim, not a parallel grid — LootSystem /
AllocationSystem / BattleSystem are singletons (global `Events` bus) and killer
attribution reads `TurnManager.current_entity` at the synchronous death, so
kills must be one-at-a-time. The victim carries a real CoreClass
(`balanced_core.tres`) — the core-modifier bucket draws nothing without one. **▶ Kill
victim** calls `adopt_turn(killer, tm.turns_taken)` and never ticks the TurnManager
(auto-tick = played; explicit-step = live — see `sandbox-framework.md`);
**⟲ Reset** re-arms with muted teardown. No play step, no `godot --path` — the
tab runs live in the editor.
