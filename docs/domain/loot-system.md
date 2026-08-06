# Loot system (#68 XP reward + #69/#173 SkillDust)

`systems/loot_system.gd` is the authority for **killing-blow rewards**. It reacts
to `Events.entity_dying(victim)` and does two things:

1. **XP reward (#68, #173, #182)** — the killer gains XP for the **territory**
   the victim held at death (its core included). Never for its level. A
   per-node trickle rides `Events.skill_node_destroyed` alongside this.
2. **SkillDust drop (#69/#173)** — the victim's former core node becomes a
   claimable relic carrying a `SkillDustAddon`, a **pick-N-from-M** choice over
   the victim's **core** modifiers.

## Why loot draws from the core ONLY (the #173 correction)

The original #69 slice also drew from the victim's **node** modifiers. That was a
**duplication bug**: node modifiers are only *lent* by the graph — granted when a
node is allocated, and released back to neutral when the entity dies. So a dead
entity's node mods are **still on the battlefield**, re-claimable by whoever
allocates those now-neutral nodes next. Copying them into loot mints a second
copy of something that already exists and is still available.

A **core** modifier (class identity + anything permanently accreted onto the
core, e.g. previously-looted mods) is the *only* thing genuinely lost when the
entity vanishes. So that — and only that — is the loot source. A consequence
that's also the *just* behaviour: killing a level-20 giant by **sniping its
core** vs. **whittling its limbs first** yields comparable loot, because both
just read the core, not the transient territory.

**Territory scale is rewarded as XP instead** (the empire term), so "you slew a
sprawling empire" still pays out — just not as duplicated stats.

This is the MVP slice of the design doc's *Killing Blow Resolution* /
*Loot Resolution* (`docs/design/combat_system.md`). The **pick-N-from-M picker**
now exists (#173, below). Deferred for now: STEAL/PROLIFERATE choice, node
staining (`last_owner`), proliferation, the DAP bonus, BLITZ. **Staining is
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
                      − the trickle already paid on the ledger      (the payout)
```

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

## The loot draw (`_draw_payload`, #173) — core-only

The candidate pool is the victim's **whole core modifier set** — `_core_modifiers`
= `core_class.modifiers` (class identity, e.g. BalancedCore +10 STR/DEX/INT) +
the core node's own `modifiers` (previously-looted mods, so the relic loop
closes). Node mods are **not** drawn (they return to the graph — see above).

Offered as **pick-N-from-M**: M = the full core supply, N (keep-count) scales
with victim level so a higher-level kill lets you keep more of their identity:

```
N = round(core_keep_base(1.0) + core_keep_per_level(0.1) · victim.level)
    clamped to [0, core supply], then to M-1 whenever M ≥ 2
```

At `per_level = 0.1` you keep +1 of the core per 10 levels, so you only walk off
with a near-whole core from a much higher-level victim. Both knobs are `@export`.

**Why N is capped at M-1.** `N ≥ M` is the addon's explicit *no-choice* branch:
it auto-grants everything and the picker never pops. That's correct for a
one-modifier core, but it also means a keep-count that merely *saturates* the
supply silently deletes the whole pick-N-from-M feature. It did: D-19 pins an
enemy's level to its starting node count (`enemy_territory_size`, 20), and the
old `per_level = 0.25` gave `1 + 0.25·20 = 6` against a 5-modifier core — so
**every** first_level kill auto-granted the full core at random and the loot
modal never appeared. The slope retune fixes the immediate numbers; the M-1 cap
is the structural guarantee that a choice survives any future retune.

> Open question: keep-count is still the only reward term scaling off
> `victim.level`, now that kill XP scales off node count instead (below). If
> level stops being a meaningful axis, this should follow.

The returned `{ candidates, pick_count }` is written straight onto the addon.
Every candidate is `duplicate(true)`d so the dust owns independent copies
(formula-mod binding-state safety — see `.claude/rules/stats-system.md`).

## SkillDust pickup + the pick-N-from-M picker (#173)

`SkillDustAddon extends SkillNodeAddon` sits on the neutralised relic core and
subscribes to `carrier.owner_changed`. When **any** entity allocates the relic
(owner goes non-null — the `owned_by == null` guard skips the death-strip so only
a real pickup fires), it routes the `candidates` through the pick-N-from-M flow;
the chosen mods land on the **collector's core** (`core.modifiers` append +
`board.add_modifier` — STEAL semantics: permanent, portable core modifiers):

- **no real choice** (empty, `pick_count ≤ 0`, or `candidates.size() ≤
  pick_count`) → auto-grant everything, `queue_free`. The picker never pops for a
  non-choice.
- **real choice** → emit `Events.loot_pick_requested(LootPickRequest)`.

### The handshake (load-bearing)

`emit()` is synchronous. `LootPickRequest.handled` is the pre-emption flag:

- **HudRoot** listens, filters `request.collector == _player`, sets
  `handled = true` **synchronously** and shows `LootPicker` (a modal — it
  **pauses the tree** and runs at `process_mode = ALWAYS`, the `PauseMenu`
  idiom; a mouse-filter alone wouldn't stop the `D`-key deallocate, which rides
  `_unhandled_input`). On confirm it unpauses and calls `request.resolve(chosen)`.
- **If nobody set `handled`** (NPC relic, headless test, no HUD mounted) the
  addon **auto-resolves a random N-of-M** right after emit returns.

That single rule keeps NPCs, headless tests, and the no-HUD path all on the
auto-resolve branch — **the default the test suite exercises**. Only the human
player's relic reaches the picker.

`resolve()` is **idempotent** and fires possibly seconds later (the player takes
time), so the resolver re-validates the collector (`is_instance_valid`) before
granting, then `queue_free`s. The addon lingers on the now-owned relic until
resolved.

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
