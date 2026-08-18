# Loot system (#68 XP reward + #69/#173 SkillDust)

`systems/loot_system.gd` is the authority for **killing-blow rewards**. It reacts
to `Events.entity_dying(victim)` and does two things:

1. **XP reward (#68, #173, #182)** — the killer gains XP for the **territory**
   the victim held at death (its core included). Never for its level. A
   per-node trickle rides `BattleSystem.cascade_started` alongside this (see
   below — it can't ride `Events.skill_node_depleted`).
2. **SkillDust drop (#69/#173, re-cut #323)** — the victim's former core node
   becomes a claimable relic carrying a `SkillDustAddon`, a **weighted draw
   over three provenance buckets** offered as N **rounds of pick-1-of-3**.

## Provenance, not "core-only" (the #323 re-cut)

The original #173 correction drew from the victim's **core** modifiers only,
excluding node grants outright — node modifiers are only *lent* by the graph
(granted on allocation, released back to neutral on death), so looting the
*live* modifier would have duplicated something still on the battlefield and
re-claimable. That objection is still true, but it argued against looting the
node's actual modifier — not against a **copy** of it ever being offered as
loot. #323 re-cuts the axis: the meaningful question isn't "does this vanish on
death" (the #173 test), it's **provenance** — is this modifier a rule of the
game (board innate), part of how this build was assembled (a grant), or a
transient effect (never offered)? The draw now reads THREE source arrays, each
a straight provenance bucket, weighted by `@export var weight_bucket_*` (equal
by default — tune in the inspector):

| bucket | source array |
|---|---|
| node grants | the victim's owned subgraph's `SkillNode.modifiers`, snapshotted pre-strip (core excluded — it's its own bucket) |
| class/register grants | `Entity.core_modifiers` — see below |
| board innates | `EntityStatBoard.intrinsic_modifiers` |

Node modifiers themselves are **still untouched by looting** — the strip still
returns them to the graph exactly as before; only a `duplicate(true)`d COPY
enters the loot pool, so nothing is duplicated on the battlefield.

**Stealing a level-scaler is now the point, not a hazard.** The old
`_is_lootable` filter excluded any modifier whose formula read `level`, reasoning
that a looted copy would "silently rebind to the looter's level and grant a
scaling relic nobody designed." That filter is **deleted** (#323) — for a
roguelite built around tuning your way into being OP, looting a piece of another
build's growth curve is the compounding channel that makes the loop work, not a
bug to filter out.

**Territory scale is still rewarded as XP too** (the empire term) — "you slew a
sprawling empire" pays out both ways now: XP for the scale of the kill, plus a
richer node-grant bucket for the specific mods it was running.

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

This is the MVP slice of the design doc's *Killing Blow Resolution* /
*Loot Resolution* (`docs/design/combat_system.md`). Deferred for now:
STEAL/PROLIFERATE choice, node staining (`last_owner`), proliferation, the DAP
bonus, BLITZ, provenance legibility in the tooltip (`"+1 STR per level (stolen
from a Serpent)"`), and the enemy-scaling contract that makes the stolen-curve
loop have teeth — all filed as follow-ups, not this issue's scope. **Staining is
shelved indefinitely** — "find something better" before reviving it.

## Killer attribution — resolved here, not on Entity or the bus

Death fires **synchronously** inside the attacker's turn: core-HP overflow
(`SkillNode.take_damage`) and the cascade's chip damage
(`BattleSystem._on_node_depleted`) both run in the attacker's `launch_attack`
call stack. So `turn_manager.current_entity` at `entity_died` **is** the killer.

LootSystem holds an injected `@export var turn_manager` (DI per
`.claude/rules/scene-composition.md`, wired in `game_root.tscn`) and resolves the
killer itself. This was a deliberate choice over two alternatives:

- **Not on `Entity`** — keeps `Entity` dumb; it already only *announces* death
  (`entity_died`), it shouldn't also attribute it. (`Events.entity_died` stays a
  1-arg signal — no `killed_by` param, no churn across its other consumers.)
- **Not in `BattleSystem`** — BattleSystem owns *attacks*; folding reward
  attribution into it spreads reward logic across two systems. LootSystem is the
  rewards authority, so attribution lives with the rewards.

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
                        XP (territory-scaled)  (corpse STILL owns its nodes)
Events.entity_died   → AllocationSystem: force-deallocate every owned node
                        (incl. core → neutral relic)
                     → GameRoot: player game-over / NPC despawn
```

`emit()` is synchronous, so **every `entity_dying` handler finishes before any
`entity_died` handler runs** — the phases sequence themselves. LootSystem needs
the pre-strip world for the **XP payout**, which counts the territory the
victim still owns (`navigator.get_mirrored_nodes()`), gone once AllocationSystem
strips it. (The loot draw itself reads only `core_class` + the core node, which
survive the strip — but sharing the `entity_dying` phase keeps both reads in one
place.) Subscribing to `entity_dying` makes the guarantee explicit; LootSystem's
position in the scene tree is **irrelevant** (this is why the two-phase split
exists — the editor is free to reorder `Systems` children).

Within the `entity_died` phase, AllocationSystem-before-GameRoot still holds, but
on the *stronger* child-before-parent ready order (GameRoot is the root, so its
`_ready` connects last and fires last) — not the fragile sibling order.

The XP grant and the dust *attach* are order-independent w.r.t. the strip anyway
— the addon survives it (`force_deallocate` only pops `node.modifiers`, not addon
children), and the core-mod source comes off `core_class` + the core node, not
the wider live subgraph. What DOES need the pre-strip world is the XP
**payout**, which counts the territory still owned at death.

## The XP reward (`_award_kill_xp`)

XP is paid for **territory removed**, and for nothing else. One axis, two
payment points:

```
per node removed    = xp_per_node_killed(5)                        (the trickle)
entity killing blow = xp_per_node_killed(5)
                      · (|removed_this_attack ∪ held_at_death| + 1)
                      · entity_kill_bonus(2)
                      − the trickle already paid on the ledger
                      + tier_xp_base(10) · tier²                   (the payout)
```

The **tier bonus** (`tier_xp_base × entity_tier²`, #300) is a flat size-shaped
reward on top of the territory term — one knob so a fixed-size victim (a
removable blocker) is worth a predictable, tunable amount regardless of how
much territory it held: +10 / +40 / +90 for tier 1 / 2 / 3 at the default
`tier_xp_base` 10. Players and NPCs keep the default tier 3, so ordinary kills
just gain a flat +90 on top of the territory term. It is paid once per kill,
not per node, and rides the same HOSTILE gate as the territory term.

- `removed_this_attack` — the **attack-scoped removal ledger**: every node the
  current attack has taken off this defender. Fed by BattleSystem's
  `cascade_started` (the depleted node **plus everything it islands**), cleared
  on every `attack_launched`.
- `held_at_death` — non-core nodes the victim still owns when it dies
  (`_held_nodes`, off the pre-strip navigator mirror).
- `+ 1` — the core it died on, so a landless D-19 elite isn't worth zero.

Both knobs are `@export`. Territory scale is paid **as XP, deliberately not as
looted stats** (see the #173 correction above).

**Why `level` is gone.** The old base term was `xp_per_victim_level · victim.level`.
D-19 pins an enemy's level to its starting node count — so "level" and
"territory" were already the same fact, and the two terms double-counted it.
Node count is the honest axis: it's what the player actually had to fight
through.

### Why the ledger exists — the ordering bug it fixes

The payout originally read **only** `held_at_death`. BattleSystem's cascade
strips nodes one at a time and chips `dealloc_damage` off the defender's core HP
per node, so the core can die **anywhere inside that loop** — and everything
already stripped had vanished from the count. Measured on a 5-node victim, same
attack, differing only in the defender's starting health:

| core dies… | old payout |
|---|---|
| early in the cascade (2 nodes still unstripped) | **35** |
| on the last cascade node (0 unstripped) | **15** |

It paid you *less the more of the victim you actually destroyed*, decided by
chip-damage arithmetic no player can see. The magic path had the same defect from
the other end: once a forking spell kills the core mid-propagation,
`entity_died` strips the corpse and every later hop lands on neutral nodes where
`take_damage` returns early on `owned_by == null` — so a 6-hop spell that killed
on hop 2 paid less than the same spell killing on hop 6.

The ledger makes the payout a function of **what the attack removed** instead of
of loop ordering. The two sets **overlap** mid-cascade (the ledger is recorded
before the strip loop walks it), so they are **unioned, not summed** — and that
union is invariant: a node moves from one side to the other as the loop
progresses and the total doesn't move. Pinned by
`test/unit/systems/test_kill_xp_ledger.gd`.

**Scope is one attack, not one turn.** The bonus means "this blow". A node broken
in an earlier attack already collected its trickle and is not re-counted at bonus
rate later.

### Whittle vs. snipe — still ~2×, now for a legible reason

At defaults against a 20-node enemy:

| path | trickle | killing blow | total |
|---|---|---|---|
| kill in one attack (snipe, or cut the arm out from under it) | — | `20 · 5 · 2` | **200** |
| break 19 limbs over earlier attacks, then the core | `19 · 5` = 95 | `1 · 5 · 2` = 10 | **105** |

The gap **is** `entity_kill_bonus`: only what *this* attack removes earns the
multiplier. Whether ~2× is the right premium is a balance question (#248) — lower
`entity_kill_bonus` toward 1.0 to close it, raise it to push harder toward
decapitation. What the shape guarantees is that neither path pays nothing, the
two are one knob apart, and nothing in between is ambiguous.

> Alternative not taken: paying off the victim's **high-water** node count, which
> would make whittle and snipe pay identically. Rejected — it erases the tactical
> distinction the bonus exists to create.

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

## The loot draw (`_draw_payload`, #323) — the three-bucket weighted union

The candidate pool is the union of the three provenance buckets above, each
expanded via `_expand_for_loot` (a `loots_as_unit = false` pack splits into
per-leaf candidates; a `true` pack, or a plain modifier, stays one candidate).
Every candidate is `duplicate(true)`d, and each carries its bucket's weight
(index-aligned `weights` array) for the round-by-round weighted sample at claim
time — see below. `would_cycle` is **deliberately not checked here**: the
claimant isn't known until someone allocates the relic, so cycle-safety is a
claim-time concern.

`pick_count` (N — the number of pick-1-of-3 **rounds**, not "N of a flat M"
since #323) is the victim's **tier** (`Entity.entity_tier`, #300), against the
pool's **total** size across all three buckets:

```
N = victim.entity_tier     clamped to [0, total supply], then to supply-1 whenever supply ≥ 2
```

Players and NPCs keep the default `entity_tier` 3, so an ordinary kill offers 3
rounds; removable blockers author 1 / 2 / 3 for small / medium / large. This
replaces the old level-scaled `core_keep_base + core_keep_per_level · level`
formula — level was a stale axis for loot (see the kill-XP "why `level` is
gone" note above), and tier gives blockers a fixed, authored keep-count without
a per-entity formula.

**Why N is capped below the supply.** A keep-count that reaches the full supply
turns every round into a no-choice auto-grant and the picker never pops. It did
under the old core-only draw: D-19 pins an enemy's level to its starting node
count (`enemy_territory_size`, 20), and the old `per_level = 0.25` gave
`1 + 0.25·20 = 6` against a 5-modifier core — so **every** first_level kill
auto-granted the full core at random and the loot modal never appeared. The
supply-1 cap is the structural guarantee that a choice survives any future
retune, now over the larger three-bucket pool.

## SkillDust pickup — N rounds of pick-1-of-3 (#173, re-cut #323)

`SkillDustAddon extends SkillNodeAddon` sits on the neutralised relic core and
subscribes to `carrier.owner_changed`. When **any** entity allocates the relic
(owner goes non-null — the `owned_by == null` guard skips the death-strip so
only a real pickup fires), it runs `_advance_round` up to `pick_count` times:

1. Filter the **remaining** pool by `collector.stat_board.would_cycle(m)` —
   against the collector's **current** board, which already reflects every
   grant an earlier round in this same relic made.
2. **Zero cycle-safe survivors** → stop; this relic grants no more.
3. **Exactly one** → no real choice, auto-grant it, skip the picker.
4. **2–3 survivors** → weighted-sample up to 3 ("roll a bucket by weight, then a
   member") and emit `Events.loot_pick_requested(LootPickRequest)` for a
   **pick-1** choice.
5. The chosen mod is granted **immediately**, via `Entity.grant_core_modifier`
   (so it lands in the collector's register too — re-lootable later) — before
   the next round's `would_cycle` check runs. The un-picked offer members are
   NOT removed from the pool; they're eligible again in a later round's fresh
   sample ("single pick, then new draw, the next pick is always clean").

**Why per-round, not one up-front filter.** Two candidates can each be
individually cycle-safe yet jointly cyclic — a single filter checked once
against the board as it stood at draw time would let both through, and the
second `add_modifier` would land on the board's own last-resort rejection (a
silently smaller reward). Checking `would_cycle` again each round, against the
board as it now stands, catches that: once round 1 binds the first candidate,
round 2's check sees it and excludes the second before it's ever offered.

### The handshake (load-bearing, unchanged from #173)

`emit()` is synchronous. `LootPickRequest.handled` is the pre-emption flag, now
per-round (`pick_count` on each round's request is always 1):

- **HudRoot** listens, filters `request.collector == _player`, sets
  `handled = true` **synchronously** and shows `LootPicker` (a modal — it
  **pauses the tree** and runs at `process_mode = ALWAYS`, the `PauseMenu`
  idiom; a mouse-filter alone wouldn't stop the `D`-key deallocate, which rides
  `_unhandled_input`). On confirm it unpauses and calls `request.resolve(chosen)`
  — which drives the NEXT round's `_advance_round`, possibly real seconds later.
- **If nobody set `handled`** (NPC relic, headless test, no HUD mounted, or an
  enemy scavenging a dead player's relic — nothing here gates by faction) the
  addon **auto-resolves a random 1-of-the-offer** right after emit returns, and
  the round chain runs fully synchronously to completion.

That single rule keeps NPCs, headless tests, and the no-HUD path all on the
auto-resolve branch — **the default the test suite exercises**. Only the human
player's relic reaches the picker.

`resolve()` is **idempotent**. The addon lingers on the relic until every round
has resolved (possibly across several real seconds if the player is picking),
then `queue_free`s.

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
(`balanced_core.tres`) — the #173 core-only draw no-ops without one. **▶ Kill
victim** writes `current_entity` directly and never ticks the TurnManager
(auto-tick = played; explicit-step = live — see `sandbox-framework.md`);
**⟲ Reset** re-arms with muted teardown. No play step, no `godot --path` — the
tab runs live in the editor.
