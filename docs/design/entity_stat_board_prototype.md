# Prototype Stats Board — Skill Tree of Life

Canonical reference for stat IDs and default values in the combat prototype.
For stat architecture (StatDef resources, RuntimeStat classes, modifier pipeline), see `stat_system.md`.
For combat rules referencing these stats, see `combat_system.md`.
For class stat profiles, see `core_classes.md`.

---

## SP Accounting Model

Before the stat table — the formal model for how SP is earned, spent, and wounded.

**Core node is free.** It does not cost SP to maintain. It is the entity's self, not an allocation. Every *other* owned node costs 1 SP from `sp_max` (it is in-use).

```
sp_max          = N (starting bonus) + sp_from_levels + sp_from_other_sources
effective_sp_max = sp_max − sp_reservation
sp_current      ≤ effective_sp_max
sp_in_use       = count of non-core allocated nodes  (implicit — not stored separately)
```

**On level up:** `sp_max += 1`, `sp_current += 1` — plus a **modifier draft**: pick 1 permanent core modifier from a pool of (3 + `luck`) options. The chosen modifier attaches to the core and persists for the rest of the run.

**On allocate node:** `sp_current -= 1`

**On normal deallocation (player choice):** `sp_current += 1`

**On force-deallocation (node destroyed in combat):**
`sp_reservation += 1` — a wound. `sp_current` does NOT increase. The node was destroyed, not returned. Healed by `health_per_turn` at rate 1:1.

**On BLITZ receive (node transferred from enemy):**
`sp_max += 1` only. The node is already allocated to you — no current SP to spend. `sp_current` unchanged. Net: same free SP, one more node working for you.

**On node transferred away (enemy BLITZ takes your node, or Uprooting):**
`sp_max -= 1`. If `sp_current > new effective_sp_max`, clamp down. No wound — the node was transferred (still exists), not destroyed.

**Starting state for a new entity:**
- Core allocated (free, not counted in sp_max)
- `sp_max = N`, `sp_current = N`
- Default N = 3 (3 free SP to spend immediately on turn 1)
- 0 non-core nodes allocated

### The three-phase turn (SP model)

**One SP pool.** The turn splits by *action type*, not by temp/permanent flag — the old "battle-phase allocations are temporary, then promote/drop in consolidation" model was parked once the live code settled on a simpler split.

1. **CONTRACT** — deallocation only. Spend `deallocation_points` to free SP and reshape; refunds SP, gated by the no-island cut-vertex rule. Allocation is locked off.
2. **EXPAND** — allocation only. Spend SP. Deallocation is locked off — symmetric guard against misclicks the other way.
3. **BATTLE** — act (up to two actions, see combat_system.md). Allocation and deallocation are both locked.

**Wound mechanics:** forced deallocation by attack routes through `force_deallocate()` and `skill_points.wound(n)` — the freed SP land in the `wounded` bucket, not `current`. `Entity._on_turn_started` heals `wound_heal_per_turn` (default 1) wounded back to current each turn. Voluntary CONTRACT-phase deallocation uses `refund(1)` instead, which lands back in `current` immediately.

**Mid-turn level-up:** the +1 lands in the one pool, spendable under the current phase's rules (i.e. only consumed during EXPAND).

---

## Stat Table

| Stat ID | Type | Category | Default | Notes |
|---|---|---|---|---|
| `health` | INT | Pool — current | 10 | Entity aggregate HP |
| `health_max` | INT | Pool — max | 10 | Target of `+max health` modifiers |
| `health_per_turn` | INT | Scalar | 0 | HP regen per turn. Negative = DoT. Also removes 1 `sp_reservation` per point when positive. |
| `skill_points` | INT | Pool — current | 3¹ | Free (unspent) SP |
| `skill_points_max` | INT | Pool — max | 3¹ | Total SP capacity. Grows with level / other sources. |
| `sp_reservation` | INT | Pool modifier | 0 | Wounds from force-deallocation. Reduces effective_sp_max. Cleared 1:1 by healing. NOT incurred on node transfer. |
| `sp_per_turn` | INT | Scalar | 1 | SP income per turn (from White nodes, class bonuses, etc.) |
| `xp` | INT | Pool — current | 0 | XP toward next level |
| `xp_max` | INT | Pool — max | 100 | Grows on level-up via growth formula (TBD) |
| `xp_per_turn` | INT | Scalar | 0 | Passive XP income per turn. White nodes are the primary source. |
| `initiative` | INT | Scalar | 10 | Turn order |
| `movement_speed` | INT | Scalar (resets per turn) | 1 | Core hops per turn within owned territory |
| `deallocation_points` | INT | Pool (resets per turn) | 1 | Deallocations available per turn. Drives constellation reshaping. |
| `strength` | INT | Scalar | 0² | Melee (R). Scales blade size (`STR//10+1` nodes) **and** per-contact bite (`+STR//10`). Roughly quadratic in investment — see `combat_system.md` Melee. |
| `dexterity` | INT | Scalar | 0² | Ranged (G). Per firing leaf: `DEX//10` (target `1→2/leaf` across `0→10`). `base_ranged` counted once per volley. |
| `intelligence` | INT | Scalar | 0² | Magic (B). Per damage instance: `+INT//10`. Scales **potency, never reach** (reach is `bonus_hop_count`). |
| `constitution` | INT | Scalar | 0² | **CON (White).** Durability: scales node/core HP (replaces degree-defense). Adds weight to armor modifiers in affix generation. No attack mode. |
| `wisdom` | INT | Scalar | 0² | **WIS (Gold).** XP-gain rate (% multiplier). Carries the most valuable growth-oriented modifiers. The new economy attribute (was White's role). |
| `perception` | INT | Scalar | 0² | **PER (Purple).** Vision + sensor range. Gearing: `+1 sense_range / 10 PER` (hops) and `+2% vision_range / PER` (euclidean). Information as weapon. |
| `bonus_hop_count` | INT | Scalar | 0 | Magic reach. **Ultra-rare** — at most ~1–2 `+1` modifiers on the whole map. INT scales potency; this is the *only* way to buy spell reach. Prime (but rarity-throttled) proliferation target. |
| `coolness` | INT | Scalar | 0 | **Prestige only — does nothing mechanically.** Tallied at end credits. Non-core. The purest "all edge, no point" (see `lore.md`); winning a coolness build is the cardinal aesthetic heresy. Procgen-sprinkled. Gold×Purple exclusion does not apply to it. |
| `attack_range` | INT | Scalar | 4 | Euclidean units for ranged attacks. Magic spells use spell-native targeting, scaled by INT and spell parameters — not this stat. |
| `armor` | INT | Scalar | 0 | Flat damage reduction vs. all attack types. After armor and resists, damage is floored at `damage_floor`. |
| `resist_r` | INT | Scalar | 0 | Damage reduction vs. melee (Red). |
| `resist_g` | INT | Scalar | 0 | Damage reduction vs. ranged (Green). |
| `resist_b` | INT | Scalar | 0 | Damage reduction vs. magic (Blue). |
| `damage_floor` | INT | Scalar | 1 | Minimum damage taken per hit after all reductions. Global default: 1. Bulwark class starts at 3. Can be reduced to 0 (chip immunity) or below 0 (healing on hit) through class progression. Negative values are intentional for extreme builds. |
| `crit_chance` | INT | Scalar | 5 | Percent chance to crit. Global across all attack types. |
| `crit_mult` | FLOAT | Scalar | 2.0 | Crit damage multiplier. Only FLOAT on the stat board. |
| `pressure_capacity` | INT | Scalar | 2 | **Redefined.** Battle-phase reach budget: how many existing field nodes a buffer node can *temporarily* allocate per tap (reach a pivot forward, claim firing stubs, pad a casting hub's degree). No longer "melee charge count" — melee size is now `STR//10+1` (the phantom blade). See `skill_node_addons.md` Buffer + the three-phase turn. |
| `aura_range` | INT | Scalar | 0 | Hops the core aura reaches outward. 0 = no aura. |
| `aura_strength` | INT | Scalar | 0 | Magnitude of core aura buff (before falloff). |
| `shell_distance` | INT | Scalar | 0 | **Halo class only.** Hop distance at which the Halo's shell aura is centered. 0 = inactive (non-Halo entities). Modifiable through class upgrades. |
| `core_charge_capacity` | INT | Scalar | 3 | Cap on extraction charges. +1 per enemy core killed. |
| `sense_range` | INT | Scalar | 3 | **Hop-based.** Detection radius from any owned node. Silhouette only: position known, no type/HP/modifiers. |
| `vision_range` | INT | Scalar | ~4³ | **Euclidean ("range").** Full-detail sight radius from any owned node. Reveals node type, HP, visible modifiers. |
| `range` | INT | Scalar | 300 | **Euclidean firing distance.** Read **per leaf** via `LocalStat`, so node-level modifiers (sniper posts, scopes) can extend a specific firing leaf without bumping the global value. Scales `+1% / DEX` (LinearFormula scale=1, INCREASE op) — at DEX 10 → 330; at DEX 30 → 390. |
| `proliferation_power` | INT | Scalar | 3 | **Reframed.** The **N** copies minted when you PROLIFERATE (remove a core-held modifier, spread N tainted copies across a cluster you must hold). Rarity-scaled: rarer modifiers yield fewer copies. Not an RNG radius. See `combat_system.md` Proliferation. |
| `node_health` | INT | Pool — current (per node) | 2 | HP per individual node. At 0, node is severed and island check fires immediately. **Resets to max at the owner's turn start** (focus-soak gate — see `combat_system.md` Node HP). The core node's `node_health` is instead a **recharging shield** over the `health` pool (never severs the core). |
| `node_health_max` | INT | Pool — max (per node) | 2 | Max HP per node. Seeded from entity totals + addons + CON. |
| `health` | INT | Pool | — | Entity-aggregate **persistent** pool — the death clock (depletion = death). Depleted by arm-loss + core-shield overflow. **`core_health` folds in here** as a class-upgradable base/bonus. |
| ~~`core_health`~~ | — | — | — | **Folded into `health`** (no longer a separate pool). Death condition reframed from "core node loss" to "`health` depletion." Kept only as a class-upgradable bonus to `health`. See `combat_system.md` Core-on-node health. |

---

## System Constants

Fixed per attack type. Live in the combat system, not on the stat board. Do not scale directly with entity progression.

| Constant | Prototype Value | Notes |
|---|---|---|
| `base_ranged` | 2 | Per **volley** (counted once): `outgoing = base_ranged + DEX//10 × (firing leaves)`. |
| `base_melee` | TBD | Per **contact** (edge/spike/face): each deals `base_melee + STR//10`; summed per target. |
| `base_magic` | TBD | Per **damage instance** (initial + hops + loop returns): `base_magic + INT//10` (or spell-specific). |

> **The //10 scaling spine** (see `combat_system.md`): `outgoing = base (once) + attribute//10 × instances`, defense applied **once per target node**. The `//10` is a deliberate gear ratio decoupling the modifier economy (chunky `+5 STR` loot) from the damage economy (single digits). Floors per-attribute → breakpoints, surfaced in UI on hover.

---

## Damage Resolution (updated)

```
per instance:  outgoing  = base[attack_type] + attribute//10     ← base counted once per attack
               taken     = max(damage_floor, outgoing − armor − resist[attack_color])   ← once per target
```

`damage_floor` replaces the hardcoded `max(1, ...)` from earlier versions. Default behavior is identical (floor = 1). The Bulwark class starts with floor = 3; it can reduce this to 0 (chip immunity) or negative (healing on hit). For all other classes at default, behavior is unchanged.

---

## Allround Prototype — Starting State

```
STR = 5, DEX = 5, INT = 5         ← +5 each from allround starting modifiers
CON = 5, WIS = 5, PER = 5         ← utility attributes (White/Gold/Purple)
armor = 0
resist_r = 0, resist_g = 0, resist_b = 0
damage_floor = 1                   ← global default
node_health = 2  (max = 2)          ← scaled by CON, not degree; resets to max at owner turn start (focus-soak)
health = 5  (max = 5)               ← persistent death-clock pool; core_health folds in as a class bonus
core_health → (folded into health) ← core node's node_health is a recharging shield over this pool
attack_range = 4                   ← euclidean, ranged only
bonus_hop_count = 0                 ← ultra-rare magic reach stat
sense_range = 3                    ← hops; scaled by PER
vision_range = ~4                  ← euclidean; scaled by PER; calibrate to editor node spacing
skill_points = 3 / 3              ← starting state (N=3, no nodes allocated yet)
sp_reservation = 0
deallocation_points = 1 / turn
movement_speed = 1
aura_range = 0, aura_strength = 0
shell_distance = 0                 ← not a Halo class
crit_chance = 5, crit_mult = 2.0
pressure_capacity = 2              ← battle-phase reach budget (buffer taps), not melee charge count
core_charge_capacity = 3
proliferation_power = 3            ← N tainted copies on PROLIFERATE
coolness = 0                       ← prestige only
```

**Combat prototype starting state** (pre-loaded for testing, not from gameplay):
```
skill_points = 0 / 5              ← 5 nodes allocated, all SP in use
```

---

## Class Stat Variations (summary)

| Stat | Allround | Predator | Bulwark | Ninja |
|---|---|---|---|---|
| `xp_per_turn` base | +1 (bonus) | ×0.5 (nerf) | normal | normal |
| `damage_floor` | 1 | 1 | **3** | 1 |
| `deallocation_points` | 1 | 2 | 0–1 (slow) | **3+** |
| `skill_points_max` cap | none | none | none | **low cap** |
| `aura_range` default | moderate | short | short | very short |
| BLITZ | no | **yes (class only)** | no | no |
| `shell_distance` | 0 | 0 | 0 | 0 |

Halo class: `shell_distance > 0`, aura is shell-type (not linear/falloff).
Serpent class: dual-metric aura (hop-buff × euclid-penalty) — no single `aura_range` value; separate coefficients.
Hive class: aura is per-pod (each Lifelink radiates to its sub-graph) or absent entirely.

---

## Tutorial Enemy

```
STR = 0, DEX = 0, INT = 0
armor = 0, all resists = 0, damage_floor = 1
node_health = 1 (resets each turn), health = 2 (core_health folds into this pool)
skill_points = 0 / 5, sp_reservation = 0
movement_speed = 0, deallocation_points = 0, health_per_turn = 0
```

Topology: two triangles connected by a bridge node (articulation point). 6 nodes + core.

---

## Open Design Questions

1. **`damage_floor` minimum:** Is there a floor on the floor? Can it go to -∞? Propose a soft cap (e.g. -5) for gameplay sanity; deeper reduction gives diminishing returns.
2. **`proliferation_power` as range stat:** Fixed INT count vs. min-max draw? Range adds variance as a build axis.
3. **`attack_range` split:** Should ranged range (euclidean) and magic range (hops) be explicitly separate stats? Currently `attack_range` is ranged-only; magic targeting is spell-native.
4. **`crit_mult` as FLOAT:** Keep FLOAT, or express crit as INT percentage damage bonus for uniformity?
5. **`sp_per_turn` source tracking:** If `sp_per_turn` comes from White nodes specifically, should the stat track that origin? Or is the aggregate fine?
6. **`shell_distance` modification cost:** When a Halo shifts its ring distance, what does it cost and how long does it take?
7. **Serpent aura coefficients:** `hop_buff_coeff` and `euclid_penalty_coeff` — these need to be on the stat board eventually. Are they a single stat or two?

---

¹ Applies to a freshly created entity. The combat prototype pre-loads 5 nodes for testing, giving sp = 0/5.
² Allround prototype adds +5 to each via starting modifiers. Base value before modifiers is 0.
³ Euclidean units. In player-facing UI, called "range" to contrast with "hops." Exact value depends on editor node spacing — verify before treating as canonical.
