# Loot system (#68 XP reward + #69/#173 SkillDust)

`systems/loot_system.gd` is the authority for **killing-blow rewards**. It reacts
to `Events.entity_dying(victim)` and does two things:

1. **XP reward (#68, extended #173)** — the killer gains XP for the victim's
   **level** *plus* the **territory** it held at death (the "empire term").
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
                        XP (base + empire)   (corpse STILL owns its nodes)
Events.entity_died   → AllocationSystem: force-deallocate every owned node
                        (incl. core → neutral relic)
                     → GameRoot: player game-over / NPC despawn
```

`emit()` is synchronous, so **every `entity_dying` handler finishes before any
`entity_died` handler runs** — the phases sequence themselves. LootSystem needs
the pre-strip world for the **XP empire term**, which counts the territory the
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
the wider live subgraph. What DOES need the pre-strip world is the XP **empire
term**, which counts the territory still owned at death.

## The XP reward (`_award_kill_xp`)

Two summed components:

```
base   = xp_per_victim_level(5) · victim.level               (killing the core)
empire = xp_per_held_node(1) · held_count ^ held_node_xp_power(1)   (its empire)
```

`held_count` = non-core nodes the victim still owned at death (`_held_node_count`,
read off the pre-strip navigator mirror). The empire term is where territory
scale is paid out — **as XP, deliberately not as looted stats** (see the #173
correction above). `held_node_xp_power > 1` makes big empires super-linearly
juicy; leave it at 1 for linear. All three are `@export` knobs.

> The complementary half — a small XP trickle for **each node destroyed** on the
> way in (so a whittling kill totals near a snipe kill) — is **#182**; it needs a
> node-destruction hook with killer attribution, broader than this file.

## The loot draw (`_draw_payload`, #173) — core-only

The candidate pool is the victim's **whole core modifier set** — `_core_modifiers`
= `core_class.modifiers` (class identity, e.g. BalancedCore +10 STR/DEX/INT) +
the core node's own `modifiers` (previously-looted mods, so the relic loop
closes). Node mods are **not** drawn (they return to the graph — see above).

Offered as **pick-N-from-M**: M = the full core supply, N (keep-count) scales
with victim level so a higher-level kill lets you keep more of their identity:

```
N = round(core_keep_base(1.0) + core_keep_per_level(0.25) · victim.level)
    clamped to [0, core supply]        (N ≥ M ⇒ no real choice, auto-grant all)
```

At `per_level = 0.25` you keep +1 of the core per 4 levels, so you only walk off
with a whole core from a much higher-level victim. Both knobs are `@export`.

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

`scenes/dev/loot_showcase.tscn` runs a real kill on a loop and shows the rewards
land: the death cascade, a SkillDust relic blooming on the victim's former core,
and the killer's live XP/level. Three sequential phases demonstrate the
per-side-effect kill-switches (`award_xp_on_kill` / `drop_skill_dust_on_death`)
by toggling one reward off at a time. Single attacker + victim, not a parallel
grid — LootSystem/AllocationSystem/BattleSystem are singletons (global `Events`
bus) and killer attribution reads `TurnManager.current_entity` at the
synchronous death, so kills must be one-at-a-time. See
`docs/domain/sandbox-framework.md` for the broader sandbox plan.

```
godot --path . scenes/dev/loot_showcase.tscn
```
