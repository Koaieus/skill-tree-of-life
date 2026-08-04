# MVP design decisions log

Authoritative current state for design decisions that gate MVP work. Where this doc disagrees with older docs (`combat_system.md`, `spells.md`, etc.), **this doc wins** — the older docs predate implementation choices and may contain superseded sketches.

Each decision lists: the question, the resolution, the rationale, and the implementation status.

---

## D-1 — Melee damage source

**Question:** edges vs blade-nodes vs both deal damage? Cycle/face bonus?

**Resolution:** **Blade-nodes deal damage; edges become inert.** No face/cycle bonus for MVP — door is left open for post-MVP.

**Rationale:** Visual weight already lives in the nodes; edges are spaghetti between them. Building triangulated/rigid blades still rewards the player because rigidity affects whether the swing actually contacts enemy nodes (a floppy blade may not sweep through), even without an explicit damage bonus. Other damage levers are richer: stat scaling, blade velocity, damage envelope, swing direction, easing of the drive.

**Impl status:** `attack/melee/skill_blade.gd` currently emits damage for both edges and nodes. MVP issues:
- Make edges inert (no `EDGE_DAMAGE` emission).
- Add **STR//10** scaling to blade-node hit damage.
- Add **CW/CCW toggle** for swing direction (small UX win — exposed per attack-plan or per-entity stat).

**Deferred (post-MVP):**
- Face/cycle bonus model (see `combat_system.md` §Melee for the design sketch).
- Drive-easing variations (different pivot-driven motion curves).

---

## D-2 — Magic cast range scaling

**Question:** does cast range scale with source-node degree, INT, or stay flat?

**Resolution:** **INT-scaling, not degree-scaling.** Introduce a new stat `spell_range` (scalar) that INT contributes to via an intrinsic modifier. Per-spell base range becomes `base × (1 + spell_range_pct)` via `LocalStat`. **Degree gating remains the sole degree-axis effect on spells.**

**Rationale:** Single scaling axis keeps balance tractable. Degree already gates *which* spells are available; making it also scale *how far they reach* compounds non-linearly. INT-scaling rewards build investment and aligns with stats-system idioms.

**Open follow-ups (post-MVP):**
- "Overqualified casting" bonuses: when source-node degree exceeds `min_degree`, grant *something other than range* (extra damage tick? extra fork? penetration?). To be designed; not MVP.
- A 1-degree spell cast from a 5-degree hub should NOT outclass a 5-degree spell cast there — verify via balance pass.

**Procgen tie-ins (post-MVP):**
- Add `spell_range` to procgen modifier pool, weighted toward INT-archetype nodes.
- Self-loop generation: ✅ **Resolved by [#42](https://github.com/Koaieus/skill-tree-of-life/issues/42)** — the 4-tier floor-guaranteed staged self-loop draw (four `self_loop_tierN_rate` knobs) makes rare doubles/triples/quads real at every map scale, replacing the naive per-node RNG roll.

**Impl status:** Cast range is flat per-spell today (`HopRangeFinder.max_hops`, `EuclideanRangeFinder.max_distance`). MVP issue: add `spell_range` stat + intrinsic INT contribution + RangeFinder consumption.

---

## D-3 — Addon application model

**Question:** per-unit vs per-node chance, unique vs stackable, ratio tunability.

**Resolution:** **Current architecture is correct, keep it.** Per-node procgen application via `AddonPolicy.slot_count_weights`, `weight_profiles`, and `pool`. `SkillNodeAddon.unique` flag enforces "at most one of this addon per carrier" — kept. Stacking up to slot-count (default 3) — kept.

**Rationale:** Aligned with design intent and implementation; no architectural change needed.

**MVP work:** Balance pass — **tune procgen ratios/spread** so addons feel meaningful and not overwhelming. This is empirical: roll a few procgen runs, eyeball distribution, adjust `slot_count_weights` and per-pool weights. Carve as a balance issue (not architecture).

**Deferred (post-MVP):** Specializations (Corrupted / Crystallized / Anchor / Doubled) per `skill_node_specializations.md` — separate system from addons, not yet implemented.

---

## D-4 — Spell gating: degree definition

**Question:** true graph degree vs allocated-degree?

**Resolution:** **Allocated-degree** — count only edges to friendly allocated neighbors via `EntityNavigator.get_degree()`. Already implemented and matches design intent.

**Rationale:** Allocated-degree is meaningful (it's the player's *committed* topology), creates real gameplay tension around what to allocate, and is already wired correctly.

**Impl status:** ✅ Done. `SpellBook._node_meets_source_requirements()` uses `attacker.navigator.get_degree(source)`. No further action.

---

## D-5 — Damage type taxonomy

**Question:** R/G/B color triangle (per design doc) vs PHYSICAL/MAGIC/TRUE (current impl) vs hybrid?

**Resolution:** **Defer entirely. MVP ships with single `armor` stat only.** Damage taxonomy is post-MVP.

**Rationale:** Scope discipline. The current `Mitigation` (flat `max(min_damage, raw - armor)` + TRUE bypass) is sufficient for MVP combat to feel meaningful. Building out R/G/B colors AND per-type resists AND procgen affixes for those resists is a milestone in itself.

**Post-MVP:** Re-open as part of "Content depth" milestone. The R/G/B design from `combat_system.md` is the leading proposal but will need a fresh look at that time.

**Impl status:** No change. `DamageInstance.Type` enum (PHYSICAL/MAGIC/TRUE) stays as-is; `armor` is the only defensive stat.

---

## D-6 — Battle-mode UI

**Question:** keep 3-button radio toggle vs world-context fan-out on node click?

**Resolution:** **Contextual action bar (SC2-style).** Click an own-node → 3 action buttons (Melee / Ranged / Magic) appear in the bottom-center action bar. Clicking one transitions to per-action context:
- **Magic** → bottom bar morphs into spell-list bar; click a spell to arm.
- **Melee** → clicked node becomes the pivot; standard blade-build flow follows.
- **Ranged** → enters target-selection mode; existing leaf-firing plan logic applies.

**Ranged + non-leaf source node:** the Ranged button is **grayed out with a tooltip** ("only leaf nodes can fire") when the clicked node isn't a leaf. Teaches the mechanic without removing the button.

**Rationale:** Better real-estate usage (bottom bar serves multiple purposes), shortcuts the click-mode-then-click-source flow, and aligns with familiar RTS unit-selection idioms. Not as game-world-native as floating action buttons around the node, but achievable with much less UX churn and remains scalable to future per-node abilities.

**Impl status:** New work. `ui/attack_mode_bar/` becomes a contextual action bar (or is replaced); selection routed through clicked-node state; spell picker bar consolidates into the same bar.

**MVP must-haves alongside:**
- Launch-attack as a FAB over the central viewport.
- Dim battle UI when AP = 0 (with tooltip).
- Spell tooltip becomes a scene (not multi-line text).
- Spells in the bar: castable first, uncastable dimmed with reason tooltip.

---

## D-7 — NPC factions

**Question:** single-faction (all NPCs hostile to player) vs multi-faction?

**Resolution:** **Single faction for MVP, with one future-proofing change:** add `Entity.faction: StringName = &"npc"` (player gets `&"player"`). All hostility checks today (`owned_by != attacker`) keep working; multi-faction is a one-line filter swap later (`other.faction != self.faction`).

**Rationale:** Zero behavior change today, trivial code addition, removes the future refactor risk of NPCs accidentally fighting each other when multi-faction lands.

**Impl status:** Tiny code change. New field on `Entity`, default per type, no consumers wired yet. Carve as small `core` issue.

---

## D-8 — Announcer toaster stale-drop policy

**Question:** when player rapidly end-turns, queued toasts lag and announce phases already past. Rule?

**Resolution:** **Drop-stale on dequeue.** When `BannerLayer` pops the next pending banner, check it against the current entity + phase: if the banner's announced phase has already been exited (or the announced entity's turn has ended), drop the banner instead of playing it. Plus: **dedup adjacent identical entries** (e.g. two `TURN_STARTED` for the same entity).

**Rationale:** Banners exist to tell the player what's happening NOW. A banner for a phase already over is noise. Drop-on-dequeue (not drop-on-enqueue) ensures we don't drop a banner that becomes relevant by the time we get to it. Dedup catches the most common spam shape.

**Impl status:** `ui/banner_layer/banner_layer.gd` — add `_should_skip(req)` check before play, plus a `BannerRequest.context` field carrying `{entity, phase}` for the check. Carve as `ui` issue.

---

## D-9 — Node attrition model

**Question:** owned nodes snap to full HP at every turn start (`entity/entity.gd`). Where does a `node_healing` stat fit on top of that? (#248)

**Resolution:** **Turn-start refill-to-full is removed.** Damage persists across turns; nodes recover through a gated, ramping regen. Per owned node, at that entity's turn start:

- took damage since its last turn start → `regen_stacks = 0`, no heal
- else if HP < max → heal `node_healing + regen_stacks × node_healing_ramp`, then `regen_stacks += 1`
- else (at full) → `regen_stacks = 0`

`regen_stacks` is runtime state on `SkillNode` (like node HP — see `docs/domain/node-hp.md`), **not** a stat. `node_healing` and `node_healing_ramp` are node-local stats. No cap stat: the ramp self-limits because it stops at max HP and resets. `SkillNode.refill()` survives, but only for the allocation path.

**Rationale:** Layering a regen stat onto refill-to-full is meaningless — the stat would never be observable. Removing refill makes whittling a real strategy: chip damage accumulates, and disengaging to recover becomes a genuine tactical choice. The ramp specifically rewards *sustained* disengagement rather than a one-turn step-back, and gives frontline vs. rear territory materially different economics. `node_healing_ramp` is the designed lever for CoreClass differentiation — a class that zeroes the ramp (in exchange for something else) is a real, legible identity.

**Consequence to watch:** TTK stops meaning "within one turn" and starts meaning "across turns." Every balance readout in #248 must be reframed accordingly.

**Known and accepted — the dealloc/realloc refill:** `SkillNode.refill()` still fires on allocation, so a 1-HP node can be deallocated and reallocated to come back full. **This is accepted, not patched.** It costs 1 DP, requires topology that permits the dealloc without islanding, and costs 2 MP more if the core sits on the node — a real turn-budget price for healing exactly one node. We are *aware* of it and may revisit much later; if the cost turns out to be genuinely real, it isn't an exploit but a situational playstyle, and it can be made less attractive with tweaks rather than a rule. **Do not "fix" this without a decision here first.**

**Impl status:** Not built. `node_healing` / `node_healing_ramp` / `regen_stacks` all net-new. Child issue under #248.

---

## D-10 — CoreClass healing aura semantics

**Question:** aura healing emanating from the core's node — flat or % of max HP? Does it respect the D-9 damage gate? Does it feed the ramp? Where do its parameters live? (#248)

**Resolution:** **Flat HP per turn, linear per-hop falloff, parameters authored on the concrete `AuraEffect` definition resource. Heals through combat, but grants no ramp. Additive, outside the ramp term.**

**Shape:** `value_at_hop(h) = base × (1 − h / range)`, clamped at 0. **`base` and `range` are both authored**; the per-hop step falls out as `base / range`. So `base 10 / range 3` → 10, 7, 3, 0.

Authoring range explicitly (rather than deriving it from a per-hop step) is load-bearing: with a fixed step of 1, range *equals* base, so scaling the payload scales the radius with it — a base-10 aura would reach 10 hops, which on a spatial graph is easily 100+ nodes, and the number of covered nodes grows roughly quadratically in the radius. Two independent knobs mean an aura can be made stronger without being made wider.

Hop distance is measured over the **owned subgraph** (`entity.navigator`), per the hard rule in `.claude/rules/graph.md` — never the global navigator, or an aura would reach through enemy territory. Use `RangeFinder.gather`, never `in_range` in a loop.

**The aura is a channel, not a payload.** Healing is one thing a class can push through it; `armor` and damage buffs are equally valid and were what the early authored classes reached for, purely because healing did not exist yet. Which stat a class radiates *is* the class.

**Magnitude:** at the core's own node the heal is **≈ 0.5 × node max HP** — half a bar per turn. Not a full reset: `X = Y` would exempt the single most important node on the board from the D-9 attrition model entirely, forcing attackers to burst it within one turn or make literally no progress. Half still halves an attacker's rate (an enormous positional advantage) while leaving the core killable by sustained pressure.

**Scaling:** the aura base scales with CON **sub-linearly** (e.g. `∝ √CON`) while `node_health` scales linearly (D-14). Mechanically: the resource authors a *coefficient*, and the effect computes `base = coefficient × f(CON)` at apply-time in effect code — **not** a board StatFormula, and not derived from `node_health` (that would be linear, which is the thing being avoided). The `≈ 0.5 × node max HP` figure above is the **anchor at a named reference level**, not a live formula. *Deferred to a follow-up: it needs CON (#269) to exist and #268 to make the curve tunable — see the NOTES on #270.* A flat base would decay into irrelevance as `Y` grows; matching linearly would keep the fortress dominant forever. Sub-linear means the aura is **decisive early and a thumb on the scale late** — which is the right curve, because a 100-node entity's aura covers a small fraction of its territory anyway, and late-game combat shouldn't be decided by core proximity.

**Parameters live on the AuraEffect resource, not the stat board.** Putting `aura_heal_base` / `aura_heal_falloff` on the board would mean canonicalising core healing as board stats — and it isn't clear that's the right shape (it would also need a node-local meaning it doesn't obviously have). Authoring them per-effect keeps each aura self-describing and lets future authored auras implement whatever logic they want without first negotiating a stat vocabulary.

Total per-turn heal = `(node_healing + regen_stacks × node_healing_ramp) + aura_flat`, where the `regen_stacks` term is subject to the D-9 gate and `aura_flat` is not. Taking damage still resets `regen_stacks` to 0 — so a node under sustained fire inside the aura receives a small constant trickle and never reaches the ramp payoff.

**Rationale:** Flat (not %) deliberately avoids compounding with `node_health` investment — it makes healing relatively stronger on cheap nodes and weaker on beefy ones, which is the healthier balance direction and costs no fractional-accumulation UI. Healing through combat is what gives the core's neighbourhood a fortress identity and makes aura *range* a load-bearing class decision. Denying the ramp under fire caps how fast regen *grows* under sustained pressure. Keeping the aura outside the ramp term keeps two independent, tooltip-readable numbers instead of one compounding one. Linear falloff gives the "gradient of safety" a flat radius can't.

**⚠ The sanctuary bubble — bounded by `range`, still must be watched.** Denying the ramp does *not* stop a besieged node out-healing its attacker: the aura term ignores the gate, and near the core it exceeds baseline incoming damage by design. Nodes well inside the aura are genuinely hard to chip down. **That is intended** — the core's neighbourhood should be a fortress, and taking one should demand focus-fire, burst, or TRUE damage rather than chip.

What must stay bounded is *how much of an entity's territory* enjoys it. That is what `range` is for. If the aura covers most of a 50–150 node entity, it out-heals the chip damage that drives the forced-dealloc cascade (see below) and the core's death clock stops ticking entirely. **The guard is `range ≪ territory radius`,** not the ramp denial. Tracked as a named invariant in #268.

**Why the aura does not need to bribe the core forward.** An earlier framing had the aura carrying the anti-camping burden — reward core proximity so players don't hide it. Unnecessary: the **forced-dealloc cascade already punishes camping structurally.** Every depleted node costs 1 unmitigable core HP, every node islanded by that loss costs another, and the entity sheds whatever stats those nodes granted. So an entity camping its core in a defensible corner still dies on a clock as its periphery is chipped away, and its "well-defended" core degrades as the territory supporting it falls off. (`dealloc_damage` defaults to 1 and is a natural hook for CoreClass debuffs, or later Hexes/Curses that raise it on an active target.)

Verified in `systems/battle_system.gd` — the cascade set is seeded with the **depleted node itself** and then extended with the islanded set, and *every* member costs 1 wounded SP + `dealloc_damage` HP. So the cost is per depleted-or-islanded node, not islanded-only; this argument is load-bearing for D-10 and rests on that. Structural pressure beats an incentive gradient — so the aura is free to be a pure reward, and `range` exists to bound coverage, not to force position.

**Follow-up (noted, not scoped):** a **NodeAddon that provides a healing aura** — small, but better than nothing — is a prime candidate once the AuraEffect parameterisation lands. It gives non-core territory a way to buy local regen.

**Impl status:** Not built. Depends on D-9. Same child issue.

---

## D-11 — CON as the fifth attribute

**Question:** is `CON` real, and what does it own? (#248)

**Resolution:** **Full fifth attribute**, alongside STR/DEX/INT/WIS: `constitution.tres`, on the default entity board, with its own procgen pool and archetype. It owns the defensive axis — but not uniformly:

| Stat | Scaling from CON | Shape |
|---|---|---|
| `node_health` | yes | **linear** |
| `armor` | **no** | — |
| `min_damage_taken` | **no** | — |

**CON drives `node_health` and nothing else.** Both **`armor` and `min_damage_taken` stay battlefield-found** — board draws, or an innate core-class grant. You do not level into mitigation; you have to go and get it, or accept being chipped down fast.

**Rationale.** CON is a *bulk* stat: it buys you a bigger bucket, which is the one defensive quality it makes sense to grow simply by surviving. Mitigation is different in kind — it changes the *shape* of every incoming hit, not its budget, so it stays scarce and positional. Keeping both mitigation stats off the level curve also produces the damage profile we want: since damage instances rise well above any `min_damage_taken` a player realistically holds, **small chips still land for the floor** (they always do *something*) while **big hits stay fully effective** (they're never absorbed away). Mitigation compresses the middle of the range, which is exactly where it should bite.

**Why the floor specifically must stay rare:** a point of `armor` is worth one damage against one hit; a point off the floor is worth one damage against *every* hit, forever, including hits armor can't reach. It is also the counter to flood-style attacks — spells that hit every enemy node for 1 live or die on the defender's floor.

**On the infinite-armor / negative-floor build:** accepted, and already answerable. `mitigation.gd` gives **TRUE-typed damage a bypass of both `armor` and `min_damage_taken`** — the escape hatch exists today. An entity that stacks that hard has spent its whole budget on defence and will have no offensive capability to speak of; that's a legitimate way to play, not a balance failure.

**Impl status:** Not built — no `constitution.tres`, not on the board, not referenced in code. CON currently exists only as prose in `docs/design/` and `docs/GDD.md`. Child issue under #248. Follow the `manage-stats` skill checklist.

---

## D-12 — Cross-archetype procgen rolls

**Question:** when defensive modifiers get a CON home, do they leave the STR/DEX/INT pools? (#248)

**Resolution:** ~~Neither migrate nor duplicate — pools stay cross-rollable.~~ **Revised away by #321 (procgen v4)** — the off-archetype phase is removed entirely. See "Impl status" below.

**Rationale (historical):** A hard migration would make defensive draws CON-gated and starve every other archetype of survivability. Straight duplication muddies where a stat "lives." Softening the off-archetype penalty specifically for defence kept armor and health available as the common filler/pity draw #248 wanted, while still making CON nodes the concentrated source.

**Impl status: REMOVED by #321 (v4).** `Procgen v4` deletes `StatPack.off_phase_op_weights`, the off-attribute cost cap, and the `&"off"` phase entirely. All budget now goes to the node's primary archetype; **universal** pools (`archetype_stat == &""` — armor, node_health, movement_points, deallocation_points, the intelligence debuff) are the shared defensive/mobility content, drawn by every node regardless of primary. `Role.DEFENSIVE` / `Role.RARE` and `flatten_for_phase` are gone; `test_constitution.gd`'s cross-rollable sections (the old D-12 acceptance) were removed with the phase. The forward-pointer proposal below landed.

**Forward-pointer — D-12 revised away (was a proposal, now done).** #321 rejected off-archetype rolling entirely, on the grounds that D-12's whole rationale ("a hard migration would starve every other archetype of survivability") only held while defensive modifiers had no natural home — and CON + the universal pool axis are now that home. `off_phase_op_weights`, the off-attribute cost cap and the `&"off"` phase are all deleted; this decision is superseded. See `docs/domain/procgen-v4.md`.

---

## D-14 — Durability scales with level, through CON

**Question:** `min_damage_taken` (3) exceeds baseline `blade_damage` (2 at STR 10) while `node_health` is 10 — so early hits are *buffed* by the mitigation floor, `armor` is inert below STR ~30, and every node dies in 4 hits regardless of build. Lower the floor, or raise health? (#248)

**Resolution:** **Raise durability, and make it scale with level — via CON.** Levelling grants CON; CON grants `node_health` and `armor` linearly (D-11). The floor stays at 3.

Target shape: a level 20 entity's nodes sit around ~30 HP rather than 10. At 3 damage per hit that's 10 hits to drop a node instead of 3⅓ — and such an entity has most likely also picked up a `−1 min damage taken` draw by then, which is exactly when armor starts mattering. Healing (D-9/D-10) deliberately does **not** scale as fast, so attrition stays real and nodes and entities stay killable.

**Rationale:** Lowering the floor to 1 would have made armor matter immediately but tripled baseline TTK and demoted the floor from a real mechanic to an anti-zero guard. Scaling durability up instead keeps 3 a meaningful number *and* fixes the asymmetry — offense already scales with STR/DEX/INT, so defence needed a growth channel or high-level combat would collapse into one-shots. Routing it through CON rather than a direct `node_health`-per-level modifier means one channel carries the whole defensive axis, and `armor` grows with it for free.

**Watch — CON as level proxy:** CON growing automatically with level makes it partly a level proxy, so *invested* CON competes against a number that rises for free. If CON investment stops feeling meaningful, the per-level grant is the dial to turn down — measure it via #268 before adjusting.

**Resolved — armor does not ride the level curve.** An earlier draft had CON drive `armor` linearly too, which would have made mitigation scale *free* with level while offense scaled only with investment: a level-100 defender at ~100 armor takes `max(3, 2 − 100)` = 3 from any uninvested attacker, forever — a dead zone where TRUE damage is the only answer. **D-11 was corrected in response:** CON drives `node_health` only, and `armor` is battlefield-found. Only the *bucket* grows with level; mitigation stays scarce. The high-level matched fixture in #268 still exists to confirm no equivalent shape re-forms via node_health alone.

**The per-level CON grant has a home:** D-15 puts it on `BalancedCore` alongside STR/DEX/INT (`+1 each per level`, WIS excluded). Before that it was stated intent with nowhere to live — `balanced_core.tres` carried per-level modifiers for three attributes only.

**Impl status:** Not built. Depends on D-11. The per-level CON rate and the CON→`node_health`/`armor` rates are **tuning values** pending #268.

---

## D-13 — How #248 balancing gets done

**Question:** how do we balance anything without either guessing or drowning in a parameter space with a dozen dimensions? (#248)

**Resolution:** **A harness that evaluates pinned points and reports deltas — it never searches the space and never renders a verdict.** Four rules:

- **Scenario fixtures**, ~6–10 named, each pinning *every* dimension. No sweeps.
- **Ratio invariants**, not absolute numbers — `melee_dpa / ranged_dpa`, `hits_to_drop_node`, `sp_income(level)`. Pinned once by feel, then enforced coldly forever. This is what collapses N dimensions to something a human can hold.
- **Sensitivity mode** is the isolation tool: hold one scenario fixed, vary one stat, print the column. A 1-D slice through a pinned point.
- **Tripwire, not judge.** Output is a committed snapshot table. It reports *what changed* and *what crossed a named threshold*. The human supplies "this plays nice."

Thresholds are **human-supplied**; the harness ships with `TBD` placeholders and an implementing agent must never invent balance ranges.

**Rationale:** The dimensionality objection is correct and fatal to any sweep-based approach. It dissolves once the harness stops trying to *find* good values and only *checks* proposed ones. Feel stays a human judgement; the arithmetic organising it does not.

**Impl status:** #268 (`Ready`). Runs at entity/scene level (real fixtures), not raw formulas, because `SkillNode.take_damage` bypasses `attack/formulas/mitigation.gd` today — a formula-level harness would report balance that doesn't match play.

---

## D-15 — The XP economy: level cost, income channels, and the stall

**Question:** levelling is 5×–50× slower than the "+1 level/turn early" the #248 body asks for, and nothing makes it taper. Change the cost curve, the income, or both? (#248)

**Resolution:** **The cost curve does not change. Income does.** `xp.tres` keeps `base 5, growth_flat 5, growth_factor 1.0` — level *L* costs `5L`. The whole economy reduces to one identity:

```
turns_per_level = 5L / income        and with income = WIS/2:

turns_per_level = 10 × level / WIS
```

So **WIS ≈ 10 × level is one level per turn; WIS ≈ level is ten turns per level.** Pace is governed by the *ratio* `WIS / level`, not by either number alone. That ratio is the progression invariant #268 watches.

**The four pinned changes:**

| | Was | Is |
|---|---|---|
| `xp_per_turn` intrinsic | `floor(log10(WIS))` | **`WIS // 2`** (integer division) |
| BalancedCore base | +10 STR/DEX/INT | **+10 to all five** (STR/DEX/INT/CON/WIS) |
| BalancedCore per level | +1 STR/DEX/INT | **+1 STR/DEX/INT/CON — WIS excluded** |
| Level cost curve | `5L` | **unchanged** |

**The taper is positional, not mathematical.** Because WIS is excluded from the per-level grant, baseline income is a **constant 10/turn forever**, so a player who never expands their economy sits at `turns_per_level = L/2` — 5 turns at level 10, 10 at level 20, 25 at level 50. That is the stall, and the only cure is to go out and occupy WIS-bearing territory. `growth_factor` stays 1.0 precisely because the curve doesn't need to bend: **stagnation is punished by the map, not by the maths.**

Including WIS in the per-level grant was the rejected alternative. It makes income self-grow, so pace degrades gently (0.5 → 8.5 turns/level across 100 levels) and never bites. That's a softer game and it undermines the loop — a free economy is exactly the thing that lets you skip the expansion the design is built around.

**Rationale — why the income side, and why divisor 2.** `floor(log10(WIS))` is a step function: WIS 10 and WIS 99 both yield 1, so ninety points of investment buy literally nothing, and no other attribute behaves that way (`blade_damage` is `STR/10`, linear). Divisor 2 is what makes the run playable. Against the *stagnant* baseline (constant income, no WIS acquired at all), cumulative turns to level 100 is **2475 at divisor 2 versus 12,375 at divisor 10** — both are "I refused to expand" numbers, and WIS acquisition is what escapes them; the point is that divisor 10 makes even a well-played run unaffordable. It also lets `xp_per_turn` recede as a procgen concern — with WIS itself worth half an XP each, procgen can distribute **WIS** and largely stop distributing `xp_per_turn` directly, collapsing two channels into one.

**Why not the cost side.** A cost-curve fix (cheap base, or `growth_factor > 1`) was considered and rejected once the territory coupling was traced: income scales with WIS-bearing nodes, nodes scale with level (D-16), so cost and income share an exponent and any cost-curve taper is cancelled by an economy build anyway. Only *flat* baseline income produces a real stall — which is what excluding WIS from the per-level grant delivers, at zero curve complexity.

**Impl status:** Not built. `entity/default_entity_board.tres` carries the `log10` formula; `entity/core/balanced_core.tres` carries the three-attribute grants. Child issue under #248, **sequenced after #269/#270** — all three edit `default_entity_board.tres`.

---

## D-16 — SP gain scales with level; territory is the real axis

**Question:** starting SP, starting allocated nodes, and whether level-up mints more than 1 SP. (#248)

**Resolution:** **Start with the core node only and more than 1 spendable SP; mint more than 1 SP per level, through a stat.**

- **Starting nodes: 1** (the core). Pre-allocated starting nodes are *not* an economy knob — they move starting HP, territory and degree at once. Held as a possible CoreClass trait, not the baseline.
- **Starting SP: a default > 1** (exact value TBD, #268). At 1 SP / 1 node the early game is **agency-free**, not merely slow: the mass-dealloc-for-refund → reallocate-to-bridge maneuver this design leans on needs ~4–5 invested SP to be *possible at all*, so turn 1 has no decision in it. CoreClass may deviate from the default.
- **`sp_gain_on_levelup`: a new stat, default 2**, replacing the hardcoded `grant(1)` in `Entity._on_xp_replenished`. Plus a **milestone bonus: +1 extra every 5th level.**

**Territory is the balance axis, and it is now decoupled from level.** Allocation costs exactly 1 SP always (`allocation_system.gd:139`), SP is minted only by level-up and `force_allocate`'s claim, and **no procgen pool grants `skill_points`** — so:

```
owned_nodes = starting_SP + sp_gain × (level − 1) + milestones − wounded − staked
```

At `sp_gain = 2` plus the milestone: level 20 ≈ 42 nodes, **level 50 ≈ 108 nodes**, level 100 ≈ 218. That is the point of the change — **100–150 node entities should arrive around level 50, not level 100–150.** Tall entities are where the game gets serious: topology, (de)allocation choices, and matching attack mode against enemy stats start mattering enormously, and that shouldn't be gated behind triple the levelling.

**Why a stat rather than a constant.** A CoreClass needs to deviate from it — plausibly sooner for AI enemies than for the player. Making it a board stat means a core class, a keystone, or a node modifier can all move it through the normal pipeline instead of special-casing the level-up path.

**Consequence for #268:** this **redefines every matrix axis.** "Level 20" now means ~42 nodes, "level 50" ~108. It also feeds back into D-15 — more nodes means room for more WIS-bearing territory, which is what lets WIS reach the 100–200 mid-game band. And it enlarges the D-9/D-14 surfaces in both directions at once: a bigger total HP bucket, but also more chip surface and a larger forced-dealloc cascade to island.

**Impl status:** Not built. `Entity._on_turn_started` / `_on_xp_replenished` hardcodes `grant(1)`; `sp_gain_on_levelup.tres` is net-new; starting SP lives on `skill_points.tres` / the board. Same child issue as D-15 (they collide on `default_entity_board.tres`).

---

## D-17 — Attribute numeric bands, and what procgen ops may do to them

**Question:** with `xp_per_turn = WIS // 2`, what magnitude should WIS reach, and what should procgen roll to get it there? (#248)

**Resolution:** **WIS keeps all three operations (ADD / INCREASE / MULTIPLY), rescaled hard so the band holds but the tail survives.**

- **Target band: 100–200 WIS is a mid-game achievement.** Not an end state, a milestone.
- **INCREASE rolls drop to a few percent**, ~10% for the most expensive roll.
- **MULTIPLY rolls drop to 1.05–1.10**, with **×1.5 as the mythic-rarest** draw.
- Exact tier values TBD — a #268 concern, not a design one.

**Rationale:** the current `procgen/pools/wisdom.tres` is authored for a world where WIS barely mattered — an additive **tier 5 grants +150–250 WIS from a single node**, INCREASE reaches +60%, MULTIPLY reaches ×1.7. At divisor 2 one such node is +75–125 XP/turn, which is the entire economy in one draw. Keeping all three ops preserves build variety on the economy axis; the rescale is what keeps most runs inside the band. **Things can still get wildly out of hand — that's the fun,** it just has to be a rare tail rather than the median outcome.

**Purpose:** these are the settings that make a *properly thought-out* playtest possible. Until the bands are pinned, playtest feedback measures the authoring accident rather than the design.

**Open — a numeric personality per attribute.** The idea that **INT is the deliberately multiplicative, runaway attribute** (players ending up with thousands of it) while WIS stays linear and bounded is floated but **not pinned.** If taken, each attribute gets a distinct numeric character and the balance surface becomes much easier to reason about. Needs its own pass.

**Consequence — the gauges can't draw this.** `ui/gauges/axis_spec.gd` carries only `label` and `color`; `AttributeRadar` has **no scale concept at all**. One attribute in the hundreds next to others in the tens already skews the plot, and any runaway-INT decision makes it unreadable. Log scale — as the default, an option, or dynamically chosen — is a real UI decision. **Its own issue; it must not ride the balance work.**

**Impl status:** Not built. `procgen/pools/wisdom.tres` only — file-disjoint from the D-15/D-16 child, so it may run in parallel.

---

## D-18 — INT is the runaway attribute: utility compresses, damage does not

**Question:** D-17 floated "INT is the deliberately multiplicative runaway (thousands of it) while WIS stays linear and bounded" but left it unpinned. Take it? (#248)

**Resolution:** **Taken. INT runs to the thousands — and that forces a shape on everything INT drives.**

The pin is not "INT gets big." It is a **three-part package that cannot be split:**

1. **INT's band is multiplicative and unbounded.** Thousands is a real outcome, not an accident. (WIS stays linear and bounded at 100–200 per D-17.)
2. **Everything INT drives for *utility* is compressed or hard-capped.** Reach, mana — none may ride the runaway linearly.
3. **Spell damage is the linear payoff.** This is what makes the thousands *mean* something. Without it the runaway is cosmetic and no player would chase it.

**The finding that forced the package.** `spell_range` is a **percent** stat (`spell_range.tres`, default 0%) driven by a `LinearFormula` on INT whose modifier `value` defaults to 1.0 — so `spell_range% = INT`, exactly. That is fine at INT 20 (+20%) and catastrophic at INT 1000 (**+1000% → 11× reach**): a 3-hop spell reaches 33 hops, which on any real graph is the entire map. Combined with the linear damage payoff, board impact would run ~11× damage × ~121× area ≈ **1300× baseline**. Under the capped curve below it is ~11× × ~4× ≈ **44×** — still a runaway, and survivable.

This is D-10's lesson at entity scale. D-10 already separated aura `base` from aura `range` precisely because covered nodes grow roughly quadratically in radius, so payload and radius must be independent knobs and **radius must be bounded.** Reach is the dangerous axis; damage is the safe one. Same reasoning, same conclusion.

**Pinned — `spell_range`: a hard cap at ×2.**

**Mind the stat's semantics:** `spell_range` is a **0-based percent *bonus***, and `RangeFinder.spell_range_multiplier()` computes `1.0 + spell_range/100.0` (`attack/range_finder/range_finder.gd:81`). So the *stat* must be clamped to `[0, 100]`, not `[100, 200]`:

```
spell_range        = clamp(INT/10, 0, 100)          # the stat: a percent BONUS
→ reach multiplier = 1.0 + spell_range/100.0        # ×1.0 at INT 0, ×2.0 at INT 1000
```

×1.0 at INT 0, **×2.0 at INT 1000, and never beyond.** The formula shape is the same `INT/10` already used by mana, `blade_damage` and `ranged_damage` — **the clamp is the whole innovation**, no new formula vocabulary. The cap applies to **both** hop-based and euclidean reach: one stat, one curve, one cap, one tooltip.

Note `spell_range_multiplier` reads `source.get_local_value(&"spell_range")` — the **cast-from node**, the same caster-side read D-20 pins for `spell_damage`. Consistent by construction; keep it that way.

*Noted, not pinned — the dumb-caster nerf:* a later variant could start the curve at 50% and reach 100% only at INT 100, so low-INT casters are actively penalised rather than merely unrewarded. Deferred; the flat 100% floor ships first.

**Pinned — hops do not auto-scale beyond that cap.** Extra hops are **battlefield-found**: a rare procgen roll or a core-class specialty, never a level-curve derivative. This is D-11's treatment of `armor` / `min_damage_taken`, applied to reach — *you do not level into hops, you go and get them.* And `bonus_hops` is genuinely a **bonus: it adds after the multiplier, not into the base.**

```
effective_hops = round(base_hops × spell_range_multiplier) + bonus_hops
```

So a rare +1 hop is worth exactly +1 hop, never amplified by INT into +2. The ADD_BASE reading was rejected for exactly that compounding.

**Open — `mana`.** Currently `floor(INT/10)`, which at INT 1000 gives a 100-point pool. That may already be adequate: `mana_per_turn` is `log10(INT)` ≈ 3/turn at the same INT, so *throughput* is compressed even though the *pool* is not — a big burst reservoir that refills slowly is a legitimate shape. **The compression principle is pinned; the mana curve is a #268 tuning value, not a design pin.** Do not invent one.

**Consequence — the radar cannot draw this (#273).** With INT in the thousands, WIS in the hundreds and STR/DEX/CON in the tens, `AttributeRadar` spans **three orders of magnitude**. That settles the *substance* of #273 — a linear plot is unreadable, so log scale is forced. It does **not** close the issue: static-log vs. per-entity-dynamic remains a genuine UX fork.

**Impl status:** Not built. `entity/default_entity_board.tres` (the `spell_range` formula + clamp), `stats_system/defs/` (a `bonus_hops` def), the range finders + `spell_tooltip.gd` (bonus applied post-multiplier).

---

## D-19 — Enemies are levelled but landless, and they carry the clock

**Question:** procgen takes no level or depth input. What is the level dial, and where does it live? (#248)

**Resolution:** **Level is an *entity* property, not a map property.** The player always starts at level 1. An enemy's level is set by the territory it spawns holding:

```
enemy_level = starting_nodes        (the /1 reading)
```

Under D-16 a player at level *L* owns ≈ 2.2*L* nodes, so `/1` means an enemy holds **roughly half the territory a player of its level would** — it carries level-appropriate attributes from the BalancedCore-style per-level grant (+10 base, +1/level to STR/DEX/INT/CON) on half the land. A 40-node enemy is level 40 with ~49 in each of four attributes, where a 40-node *player* would be level ~18 with ~28. It hits far harder per node and is faster to kill: fewer nodes to chip, a smaller cascade buffer, and less terrain-sourced stat. **A glass elite** — a legible archetype, deliberately chosen over the `/2` "statistically identical to a player" reading because an on-curve enemy is just a mirror match.

**Enemies get elevated WIS, and that is the difficulty dial.** A landless enemy *cannot* source WIS from territory (D-15: income comes from WIS-bearing nodes it doesn't own), so the grant must be non-territorial — it lives on the **enemy CoreClass**, alongside the rest of its identity, reusing the existing `entity/core/` pipeline. Difficulty becomes "which class did you spawn it with."

**Why this matters: the player is on a clock.** With `xp_per_turn = WIS//2` and level *L* costing `5L` (D-15), a stagnant entity's cumulative turns to level *L* is `5L²/W`. Setting both to the same turn count *T*:

```
level_ratio(enemy : stagnant player) = √(W_enemy / W_player)      W_player = 20
```

So enemy WIS 80 → the enemy runs **2× the player's level**; WIS 180 → 3×. One number, one square root, the whole difficulty curve.

**⚠ This ratio is a spawn-time handicap, not a standing invariant.** It holds only while *both* sides are stagnant — and D-15's entire thesis is that neither is. The player escapes by occupying WIS-bearing territory; a competent AI does the same. So `√(W/20)` is **the head start the player must out-expand**, and enemy WIS is the *target* the player's economy has to reach. That is the loop, expressed as a number: camp and the enemy outgrows you; expand and you close the gap. Do not quote this ratio as a steady-state property of play.

**Watch — the landless identity decays.** An enemy that levels up mints SP like anyone else (`sp_gain_on_levelup`, D-16), so it drifts from the `/1` line back toward the `/2` curve the longer the game runs. The archetype is a *starting condition*, not a permanent state.

**Impl status:** Territory seeding **already exists** — `ProcgenPlaySandbox._expand()` (`scenes/procgen_play_sandbox.gd`) random-walks `force_allocate` outward from each core. Two problems: it is a private method on one sandbox subclass rather than an injectable strategy (per `.claude/rules/scene-composition.md` it should be a DI'd Resource), and **it expands the player too** (`expansion_steps = 6`), which directly contradicts D-16's pinned "starting nodes: 1 (the core)". Child issue under #248.

---

## D-20 — Spell damage scales with INT: board stat × per-spell coefficient, evaluated at seed

**Question:** no INT scaling on spell damage exists anywhere in code. Where does it live? (#248)

**Resolution:** **Both halves — a board stat carries the global INT multiplier, a per-`SpellDef` coefficient tunes or opts out.**

- **Board stat `spell_damage`**, driven by an intrinsic INT formula, mirroring `STR → blade_damage` and `DEX → ranged_damage`. Being a board stat means node-local addons, auras and keystones reach it through the normal pipeline. **Linear in INT** — this is D-18's payoff, the thing that makes the runaway worth chasing. Follow the `manage-stats` checklist.
- **`SpellDef.int_scaling: float = 1.0`** — a plain multiplier. `0.0` is a pure flat spell that opts out of INT entirely; `2.0` is a hyper-scaling glass spell.
- **`SpellDef.damage_formula: StatFormula = null`** — optional escape hatch reusing the existing `stats_system/formulas/` vocabulary, for a signature spell needing real math over multiple stats. Null = the standard path.

**Read the *caster's* node, not the target's — this is the trap.** `SkillNode.get_local_value()` merges the node's own board with **`owned_by`'s** board (`skill_node/skill_node.gd:412`). Reading `spell_damage` off `state.current_node` would therefore read the **defender's** board and let an enemy's territory buff the spell landing on it. The correct read is the **cast-from node**, `state.source` — exactly the pattern `RangedDamageFormula` already uses with `firing_node.get_local_value(&"ranged_damage")`.

**Evaluated once, at seed.** `CastSpell.damage` is a *running product*: `SpellResolver` sets `seed_state.damage = spell.base_damage × config.seed_damage_fraction`, then each `PropagationStep` does `next.damage = payload.damage × config.damage_multiplier_per_hop`. `DamageEffect` only reads it. So the INT term belongs in the seed expression:

```
seed.damage = base_damage × int_scaling × spell_damage(source_node) × seed_damage_fraction
```

Re-evaluating per hop would **compound INT** — INT² by hop 2, INT³ by hop 3 — which no one wants, and would also break `damage_multiplier_per_hop`'s job of decaying the payload with distance.

**Impl status:** Not built. `attack/spell/spell_def.gd`, `attack/spell/spell_resolver.gd`, `stats_system/defs/spell_damage.tres` (net-new), `entity/default_entity_board.tres`. Child issue under #248.

---

## D-21 — The entity health pool scales with CON; `dealloc_damage` is the class knob

**Question:** does the entity `health` pool — the death clock — get a growth channel? (#248)

**Resolution:** **Yes: `health` scales with CON, and `dealloc_damage` becomes the paired per-class lever.**

**The finding.** `health.tres` is `default_value = 10.0` and **nothing anywhere scales it** — not CON, not level, not territory. Meanwhile the forced-dealloc cascade chips it 1 unmitigable HP per depleted-or-islanded node, and D-10 leans on exactly that as the structural anti-camping clock:

| | L1 | L20 | L100 |
|---|---|---|---|
| owned nodes (D-16) | ~1 | ~42 | ~218 |
| `node_health` (CON, D-14) | 10 | ~30 | ~110 |
| **entity `health`** | **10** | **10** | **10** |
| cascade size that kills | n/a | 10 nodes = **24% of territory** | 10 nodes = **4.6%** |

D-14's own rationale — *"defence needed a growth channel or high-level combat would collapse into one-shots"* — was applied to `node_health` and **missed the pool that actually kills you.** Nodes get 11× tankier while the entity's own bar never moves, so the death clock accelerates relative to territory at every level. Same shape as the round-2 armor finding, one level up.

**Two knobs, and class identity lives in their ratio:**

- `health = base + CON` (linear) — the bucket. One channel (CON) now carries the whole defensive axis, as D-14 argued it should.
- `dealloc_damage` (default 1) — the chip rate, **the per-class lever**, suitable for playable classes *and* for authoring enemies. A glass core at 3 re-creates the cliff deliberately; a bulwark at 0.5 doubles the buffer.

```
nodes lost before death = health / dealloc_damage
Balanced : 119 hp ÷ 1   = 119      Glass : 119 ÷ 3 = 40      Bulwark : 119 ÷ 0.5 = 238
```

**The core also takes damage directly** — this already works: `SkillNode.take_damage` routes overflow past a depleted core node into `owned_by.stat_board.health`. So the pool has two drains (cascade chip, core overflow) and, per D-22, essentially one meaningful heal.

**Implementation note:** `health_per_con` is plausibly its own stat, but the simpler home is a `StatFormula` on the innate `intrinsic_modifiers` list, exactly like the other four derived stats. Prefer that unless a class needs to modify the *rate*.

**⚠ Pinned — allocating CON grants the max-HP delta as current HP.** Take +40 CON, gain +40 current HP. This is the intuitive reading and consistent with D-9 having accepted the analogous node dealloc/realloc refill. **It is knowingly exploitable and that is accepted** — in a game where the skill graph *is* the mechanics, engineering your graph to move your numbers is legitimate play. The bar is not "loophole-free"; it is **"doesn't take the fun out of the game or make it too easy."**

**The one failure mode to guard, named now:** a node that rolls **big CON *and* +1 max deallocation points** is an infinite heal — *if and only if* allocating it grants an immediately-spendable DP alongside the raised maximum. **The guard is to raise the maximum without granting the point.** That closes the loop at its actual source and costs nothing elsewhere. Two fallbacks if it still misbehaves: cap per-turn healing from this channel at `N × core_healing`, or reconsider the grant entirely (see D-22 — the two decisions are coupled).

**Impl status:** **Built** — #276. `health = 10 + core_health_scaling x CON` as a board intrinsic; the delta grant is `StandardPoolStatDef.grant_max_increase_delta` (health opts in via `heal_on_max_increase`), and the DP guard is `deallocation_points.tres` opting *out* of the same flag. `dealloc_damage` needed no work: it was already an ordinary board stat, so a CoreClass tunes it with an ordinary modifier. Pinned by `test/unit/test_entity_health_scaling.gd`.

---

## D-22 — `core_healing` is a sliver, because CON expansion is the real heal

**Question:** `core_healing` was descoped from #270 and exists nowhere in code. What is it? (#248)

**Resolution:** **It regenerates the *entity* `health` pool — not node HP — and it stays deliberately small (a sub-1/turn sliver, fractionally accumulated).**

It is **not** a duplicate of D-10's aura. The aura heals `node_health` on the core's own node; `core_healing` heals `stat_board.health`, the pool the cascade chips and core-overflow drains. Before this, **nothing healed that pool at all.**

**Why a sliver, and why that is the interesting part.** `core_healing` magnitude and D-21's grant-the-delta decision are **coupled and near-exclusive:**

- **Sliver (pinned).** The pool barely self-regenerates, so the *only* meaningful way to heal your death clock is **to grow your CON territory.** That is a real, legible strategic answer to being chipped — and it pairs exactly with D-10's anti-camping cascade: **you are chipped by camping and you heal by expanding.** The core loop, expressed in the death clock.
- **Substantial (1–10/turn, or CON-scaling) — rejected for now.** If the pool heals itself briskly, granting the CON delta on top is both redundant and genuinely exploitable, and expansion stops being the answer to attrition. Taking this branch would require **reversing D-21's grant.**

Pinning the sliver keeps one heal channel meaningful instead of two overlapping ones, and preserves the loop.

**Open (a #268 tuning value):** the exact rate, whether it obeys a D-9-style damage gate, and its UI sliver. **The interaction that must be measured, not guessed:** if `core_healing` ever meets or exceeds the cascade chip rate (`dealloc_damage` × nodes lost per turn), **camping becomes viable again and D-10's structural guarantee is silently undone.** That invariant belongs in #268.

**Impl status:** Not built. Own issue, `design` until the rate and gate are pinned.

---

## D-23 — Procgen needs no level input; map content is radial and already built

**Question:** "procgen has no level or depth input at all — the dial has to be invented." (#248, open since round 1)

**Resolution:** **It does not need one. The item closes.** Two mechanisms already cover what a `depth` parameter would have bought:

- **Entity level is the difficulty dial** (D-19) — "a level 20 map" means *the enemies on it are level 20*, expressed as the territory they spawn holding. Nothing about the graph itself has to know.
- **Map content difficulty is radial, and the plumbing exists and is in use.** `procgen/placement/radial_gradient_field.gd` is wired as the `budget_field` in `procgen/presets/first_level/first_level.tres`, alongside `radial_band_profile.gd`. Content richness already rises with distance from the start. Since enemies are placed at `viability_radius` from the player, the rich terrain and the danger already coincide.

A map-level `content_depth: int` was considered and rejected: it would gate tiers *uniformly*, making the node beside your core as rich as the far corner, which is strictly worse than the gradient already shipping.

**Correction to a round-4 note — keystones are not uniformly high-tier.** The basic keystone should be a **simple +20 WIS**, scattered broadly rather than reserved for tier 4–5 placement. At D-15's `xp_per_turn = WIS//2` that is **+10 XP/turn — a doubling of the pinned baseline income of 10**, and by D-19's identity it shifts the player's level ratio by √2. A large, legible reward from one common node, and exactly the "go out and occupy WIS-bearing territory" pull D-15's positional taper depends on.

**⚠ Caveat on the placement mechanism itself:** keystone placement may still be **v1**. The v2 notion — *keystones as pre-authored nodes, or constellations of them, stitched into the generated graph* — remains open and is **#180's** business (the stitch-marker / arc contract). This decision says what the basic keystone *is* and how widely it scatters; it does not claim the machinery to place it is finished.

**Impl status:** Radial gradient — built and in use. Basic WIS keystone + scatter — #180.

---

## D-24 — Territory selection is one policy: spawn seeding and the AI share it

**Question:** D-19 needs a territory-seeding strategy for spawned enemies. The AI needs to choose which node to allocate each turn. Are these the same thing? (#248, #275)

**Resolution:** **The same thing, at different call rates. One shared policy resource, `pick_next(entity, candidates) -> SkillNode`.**

`AIController._pick_frontier_node()` is already a degenerate seeder — its own docstring says *"Frontier = unowned node adjacent to a node this entity already owns. **Picks the first match — no scoring heuristic at v1.**"* The greedy BFS ball pinned for #275 differs only in tiebreak (nearest vs. first-edge-found) and call rate (N times at spawn vs. once per turn). The "weighted growth" follow-up filed against #275 — score by modifier value × archetype match — *is* the AI v2 scoring heuristic that comment is asking for. It was filed twice by accident.

**Callers supply the candidate set; the policy never reaches for `graph` itself.** This is the load-bearing part. The seeder picks from the **whole** graph; the AI at v2 picks from its **sensed** subgraph (`AIController` notes vision is deliberately unconsulted at v1 — *"a proper per-entity vision pass is post-MVP"*). Identical to the rule `.claude/rules/graph.md` already pins for `RangeFinder.gather(source, mirror)`: *"gather traverses whatever mirror it's handed. That divergence is the point."* Same pattern, same reason.

**Gating stays with the caller too.** Seeding applies via `force_allocate` (ungated); the AI via `allocate` (SP/AP-gated). The policy only *picks* — it never applies.

**⚠ Tactical objectives must be switchable off.** If the AI ever allocates as an *attack maneuver* — a directed run of allocations to bring a target into range — that objective must not leak into spawn seeding, which wants plausible built-out territory rather than a spear aimed at nobody. **The shared entry point takes an objective/tactics argument the seeder passes as neutral.** If that proves insufficient, split the policy rather than letting the seeder inherit combat intent.

**Pinned — the AI spends *all* available SP each turn, not one node.** `AIController._try_allocate_frontier()` currently allocates exactly one. There is no current reason to hold SP; loop while `skill_points.current > 0`.

*Why this is structural, not polish:* SP income per turn is `sp_gain / turns_per_level = W / (5L)`, so an entity banks unspent SP whenever `L < W/5` — at a D-19 enemy's WIS 80, every level below **16**. That is precisely the early window where a high-WIS enemy is designed to out-level the player, so a one-per-turn cap would strand its economy and leave it landless for the wrong reason. (A future core class that *scales with unspent SP* would be the first legitimate reason to hold — none exists today.)

**Payoff.** A spawned enemy's territory becomes exactly what that AI would have built, which makes D-19's landless-elite legible rather than arbitrary, and gives #268 fixtures policy-generated territory instead of hand-waved shapes.

**Consequence to watch:** tuning the AI now reshapes every spawn. A #268 fixture pinned against policy v1 will shift when v2 scoring lands — that coupling is the price of the shared policy and is worth it, but it must be *known*, not discovered.

**Open — floated, not pinned** (see the AI-allocation issue):

- **AP-aware candidate horizon.** N unspent AP means N hops worth checking, so the candidate set could widen with banked AP rather than staying at the immediate frontier.
- **Beelining.** An elite AI should head for a special node when it can, offset against stretching-too-thin danger — unless its core class *demands* a thin-stretched playstyle, which is its own design thread.

**Impl status:** Policy resource + seeder — #275. AI-side adoption, spend-all-SP, and the open items — own issue.

---

## D-25 — `core_healing` is an integer per-turn heal, ungated and unramped

**Question:** D-22 pinned `core_healing` as a sub-1/turn sliver but left the rate, the gate, and the UI open. (#277)

**Resolution:** **An integer heal on the entity `health` pool, placeholder `1`/turn. No damage gate, no ramp.**

**Integer, not a sliver — and the UI decides it.** The main gauges already render an *"incoming next turn"* segment (mana/turn, xp/turn), so an integer `health`/turn costs **zero new UI**. A sub-1 sliver needs net-new fractional-accumulation rendering on the core bar, for a value that may not survive tuning. Ship the integer.

**No ramp, and this one is structural.** A D-9-style ramping out-of-combat heal rewards sitting still — and sitting still is exactly what D-10's forced-dealloc cascade is engineered to punish. The ramp is right for *nodes* (a held node recovering is territory you are defending); it is wrong for the death clock, because it hands camping back the thing the cascade takes away. No gate either: the gate exists to make the ramp meaningful, and there is no ramp.

**⚠ `1` is the break-even point — this is a placeholder, per D-13.**

```
L100:  CON ~110  →  health ~120
core_healing = 1/turn  =  0.83%/turn  =  50 HP over a 50-turn level  =  42% of the pool
cascade chip = dealloc_damage (default 1) x nodes lost per turn
```

At a 1-node-per-turn chip, `core_healing = 1` **cancels D-10's clock exactly.** Whether that matters depends entirely on the real chip rate under sustained pressure — a committed attacker very likely depletes more than one node per turn, in which case `1` softens the clock rather than stopping it. **That is a #268 measurement, not a design call.**

**Corrected from an earlier draft:** `dealloc_damage` is a **curse/debuff knob** — a balancing lever, later raisable by a Hex/Curse effect — **not** a scaling base. `core_healing` must not be *expressed* as a fraction of it. The relationship survives only as a **named #268 invariant**: if `core_healing >= dealloc_damage x nodes_lost_per_turn`, camping is viable again and D-10's structural guarantee is silently undone.

**Impl status:** **Built** — #277. `core_healing.tres` + the board scalar; `health` is `per_turn_mode = ADD` with `per_turn_stat_id = &"core_healing"` (a new `PoolStatDef` field, so upkeep stayed declarative instead of becoming a hand-wired turn-start hook). `hero_sigil_card.gd` binds the existing incoming-next-turn band. Pinned by `test/unit/test_core_healing.gd`.

---

## D-26 — `health = 10 + core_health_scaling x CON`, and some stats are entity-only

**Question:** D-21 pinned `health = base + CON` with both terms hardcoded. Should either be a knob? (#248 round 6)

**Resolution:** **The CON coefficient becomes a knob, `core_health_scaling`, defaulting to `1.0`. The flat `+10` stays baked for now.**

Same shape as `dealloc_damage` being a class lever (D-21): a class can trade pool size against something else, and the ratio is where identity lives. Default `1.0` keeps every number D-21 published valid (L100 ~119).

**The flat `+10`:** could become a base stat, or an innate `StatModifier` granting an unscaling flat bonus. **Bake it for now** and revisit — it is a small instance of the same authoring problem #279 exists to solve.

**⚠ New fork surfaced, not settled — entity-only stats.** `core_health_scaling` is meaningful **only on the entity**. As a node-local stat it has zero meaning, or worse, a counterintuitive one. The stat system localises stats per node; there is currently no way to say *"this stat is entity-scope only."* That gap is now real and needs its own decision — see the entity-scope stat issue.

**Impl status:** **Built** — rode with D-21 on #276. `core_health_scaling` is a board scalar (default 1.0); the flat +10 stays baked as `pool_health`'s `base_value`. The entity-scope-only fork it surfaced is #287, still open.

---

## D-27 — A CoreClass is a leaf; reuse lives inside its typed arrays

**Question:** every enemy needs a mostly-similar batch of offensive/defensive/attribute/WIS modifiers, and each `.tres` hand-declares them. What is the authoring architecture? (#279)

**Resolution:** **A `CoreClass` `.tres` is a flat leaf. It never references another `CoreClass`. Shared batches are file-backed resources dropped into its existing typed arrays — a `CompositeStatModifier` `.tres` in `modifiers`, an `Effect`/`CoreAura` `.tres` in `effects`. `CompositeStatModifier` gains `@export var loots_as_unit: bool = true` so a pack can declare whether it is one loot atom or several.**

The requirement, in the user's words: *author stuff and plug it into any enemy, reuse it across multiple enemy **definitions**, and if it needs to change — change 1 `.tres` and every class composing it gets the change.* That is composition **by reference** — which rules out factory helpers (moves duplication into code, loses inspector authorability) and any copy-on-author scheme. It does **not** imply a composition mechanism on `CoreClass` itself.

### Revised twice; both earlier resolutions are wrong and are recorded as traps

- **First:** `@export var inherits: CoreClass`, base-first append. Shipped in `59d2444`.
- **Second:** `@export var composes: Array[CoreClass]` with DFS, dedupe-by-identity, and a cycle guard. Shipped in `1ff127e`. Reverted.
- **Third (this one):** no mechanism on `CoreClass` at all.

The second revision was correct that *"composition, not inheritance"* — but it composed the wrong noun. The unit of reuse is **the modifier array**, not the class.

### Why the arrays, not the class

**`CompositeStatModifier` already is the container.** It is a `class_name` Resource extending `StatModifier`, so it can be a standalone `.tres` sitting directly in `CoreClass.modifiers`. `StatBoard.add_modifier` flattens before routing, `duplicate(true)` deep-copies `children`, and `scales_with` / `collect_formula_edges` / `format` all recurse. Its own docstring already named `CoreClass.modifiers` as the motivating case. Zero new API.

**`effects: Array[Effect]` already composes by reference.** So half of batch-reuse worked before either revision landed; `modifiers` was simply the array missing the property.

**Each field composes independently, in its own vocabulary.** A class-level mechanism is all-or-nothing per entry: you cannot take a base's modifiers without also taking its effects. Per-array file-backed entries give reuse to every array `CoreClass` ever grows, for free, and never force an authoring order.

**A class-level mechanism pollutes the class registry.** `CoreClass.load_all()` returns every `.tres` in `entity/core/` that `is CoreClass` — so `attribute_baseline_core.tres` became a phantom sixth class visible to #322's board-vs-class DAG check and to any future class-select UI. Fixing that needs a `selectable: bool`. Mechanism begetting mechanism. Packs are not `CoreClass`es and never enter the registry.

### `loots_as_unit`

Composite atomicity is **not** intrinsic. Every consumer flattens — `StatBoard.add_modifier`, `SkillNode`, `AllocationVfx`, `scales_with`, `collect_formula_edges`, `format`, `contribution_text`. Exactly two places treat a composite as one thing: `LootSystem._core_modifiers` (does not flatten) and `loot_picker.gd` (one card per candidate).

So one boolean on the resource settles the only question that differs by pack:

| pack | `loots_as_unit` | why |
|---|---|---|
| `ninja_core`'s `+2 deallocation_points / −1 skill_points` | `true` | #183's motivating case — a buff yoked to a real tax, balanced only as a unit |
| a shared `attribute_baseline` pack | `false` | plain authoring reuse; nothing about `+10 STR/DEX/INT` is all-or-nothing |

The flag reframes `CompositeStatModifier` from *"loot bundle"* to *"modifier pack, optionally atomic for loot"*; its docstring and `.claude/rules/stats-system.md` must be updated to match.

**It costs nothing at apply time**, because apply and the draw read different things. `CoreClass.apply()` expands a **duplicate** onto a board; the authored array is untouched, and the container is never bound to a `Stat` — the board holds leaves, always. `LootSystem._core_modifiers` reads the **source resource**, where the container is still intact. `loots_as_unit` is a flatten decision the draw makes; no apply-time behaviour can answer it.

**Apply-time unwrapping is already unconditional and already reversible.** `add_modifier` flattens; `remove_modifier` flattens the *same stable child instances*, so `remove_modifier(the_composite)` revokes exactly the children it granted. The container is retained by the **granter** (`EffectContext` handle, the node's modifier list, the class `.tres`), never by the board. No `unwrap_on_apply` toggle is needed — that behaviour is the baseline.

### The authoring convention

- **A `CoreClass` `.tres` is a leaf.** It declares its own identity and references shared parts. No class ever references another class.
- **Shared modifier batches** are file-backed `CompositeStatModifier` `.tres`, `loots_as_unit = false` for plain reuse, `true` when balanced only as a unit.
- **Shared effects/auras** are file-backed `Effect` / `CoreAura` `.tres` in `effects`. The heal-somewhat-at-turn-start core aura is the first real case — wanted on effectively every core. Every effect in-tree today is an inline `SubResource`; convert on the second consumer, not before.
- **Packs live outside `entity/core/`** so they never touch `CoreClass.load_all()`.

**Pure append, not override-by-`stat_id`** (carried from the first resolution, still correct). The stat pipeline already stacks modifiers — multiple modifiers on one stat is the native semantic. "Weaker than the base" is a **negative modifier**, not an override rule.

### What this does NOT solve

**Behaviour reuse.** Neither `composes` nor a pack composes `on_turn_started` or an `apply()` override — two enemy families wanting the same turn hook still have no shared home. The likely answer is `Effect` (which already has lifecycle hooks and already composes by reference), which would keep *"a CoreClass is a leaf"* true all the way down. Filed separately; nothing here depends on it.

**Seam, not a bug:** nothing retains a composite container after it is *won* as loot — the addon holds duplicated candidates. Irrelevant until something revokes looted modifiers, and #323's per-entity core-modifier register is where it would land.

**Impl status:** Revert `1ff127e`; `59d2444` is in pushed history so both undos are forward commits. `entity/core/core_class.gd`, `stats_system/composite_stat_modifier.gd`, `systems/loot_system.gd`, the `.tres` set, `.claude/rules/stats-system.md`. #279.

---

## D-28 — A node survives by being inside a *life source's reach*, not by touching core

**Question:** LifeLine grants islanded nodes a one-turn reprieve. How is "protected" actually decided, and does building it now paint us into a corner for the planned **lifelink** addon? (#240)

**Resolution:** **Generalize the survival rule to life sources with a reach.** A node stays allocated iff it is within the reach of at least one *surviving* life source.

| Source | Reach | Duration |
|---|---|---|
| **core** | ∞ over the owned subgraph | permanent |
| **lifeline addon carrier** | **2 hops** (self + 2), tunable | 1 turn of grace |

"Connected to core" is not a separate rule — it is core's infinite-reach case, and stays implemented by the existing single-anchor `nodes_islanded_by_removing_set(D, core)`. Nothing about life sources enters `GraphMirror`.

**Grace spares *would-be islanding* kills only.** A node that is itself depleted always deallocates, tagged or not — LifeLine protects against *structural* loss, never against damage. Corollary, and the reason it must be stated: if the depleted node **is** the lifeline carrier, it dies, its island loses its tag source, and the whole island collapses in the same resolution step. That is intended.

**Protection is `has_tag(&"lifeline")` recomputed on the POST-cut subgraph.** This supersedes the earlier "snapshot the spare-set before the dealloc loop" decision, which is wrong — not merely inelegant. Config C4 below is the counterexample: a lifeline node hanging off the cut vertex carries the tag *before* the cut (it reaches the carrier through the cut vertex) and loses it *after*. A pre-cut snapshot spares it; it must die. Reading `has_tag` mid-cascade is equally wrong for the reason the original decision gave (`_on_node_deallocated → recompute → revoke_all` tears the tag set down mid-loop). The only correct read is a fresh `gather` from each surviving source over `owned − D`.

**The seam is one shared function, and it is the deliverable of #240:**

```
apply_depletions(entity, D: Array[SkillNode]) -> { died, graced }
    surviving_sources = all lifeline sources − D
    islanded  = navigator.nodes_islanded_by_removing_set(D, core)      # topology
    sustained = ⋃ gather(s, owned − D) for s in surviving_sources      # effect layer
    died   = D ∪ (islanded − sustained)
    graced = islanded ∩ sustained                                       # 1-turn countdown
```

Both the speculative resolvers (spell propagation, the melee blade sim — which precompute deliberately, so the AI can score moves) and real playback call the same function. That is what keeps preview and result honest, and it is why grace does **not** live in `BattleSystem`'s cascade loop as the earlier draft assumed. It also drops the previously-proposed relocation of the cascade into `AllocationSystem` — neither system owns this.

**Consequence — the voluntary-dealloc gate uses the same predicate.** `AllocationSystem.deallocate` today blocks any move that would island a node from core (`allocation_system.gd:126`). Once an island is held by a lifeline, the anchor inside that island is the *carrier*, not core. Calling `apply_depletions(entity, [candidate])` and denying on a non-empty `died` makes the gate and the cascade agree by construction. The worked example: `…-(core)-a-b-c-(lifeline)`, enemy snipes `a`; voluntary dealloc is legal in dependency order `b → c → lifeline`, illegal out of order.

**Reconnection cancels grace favorably.** Each tick, if the graced node is reachable from core again, drop the countdown — no dealloc. Only expire when still unsustained *and* the counter hit 0.

**Lifeline and lifelink are orthogonal — this forecloses nothing.** LifeLine is entirely effect-layer (bounded tag + countdown + a filter on the islanding result). **Lifelink** (the planned permanent, unbounded variant) is topology — a *virtual edge* in the mirror, which makes core-reachability literally true and needs no life-source machinery at all. The filter composes on top of whatever the islanding query returns, so neither model constrains the other. Lifelink's design, its emergent consequences, and its balance live in its own issue; do not build for it here.

**Acceptance configs (RED — LifeLine is not built).** All at reach 2, `X` = the depleted node, `L` = lifeline carrier. Build fixtures by instantiating scenes and `force_allocate`, never by adding to containers directly, or `entity.navigator` stays empty and every islanding query silently returns `{}`.

| # | Topology | Deplete | Expected |
|---|---|---|---|
| C1 | `core—X—L—A—B` | `X` | `X` dies; `L,A,B` graced (all ≤2 hops from `L`) |
| C2 | `core—X—L—A—B—C` | `X` | `X` dies; `L,A,B` graced; **`C` dies** (3 hops — out of reach) |
| C3 | `core—A—X—L—B` | `X` | `X` dies; `A` untouched (still core-connected); `L,B` graced |
| C4 | `core—A—X—L—B` plus `X—C` | `X` | `X` dies; `L,B` graced; **`C` dies** — tagged pre-cut, untagged post-cut. *This is the config that falsifies the snapshot approach.* |
| C5 | `core—X—L—B` | **`L`** | `L` dies (depletion beats grace); **`B` dies** — no surviving source |
| C6 | cycle `core—X—M—Y—core`, plus `M—L—B` | `X` **and** `Y` in one step | `X,Y` die; `M,L,B` graced. Neither cut alone islands anything — exercises the joint cut and the set-taking API. |

Plus: C1 followed by the owner re-allocating `X` on their turn → grace dropped, nothing deallocates.

**Impl status:** Not built. #240. Unblocked — #267 (tag channel + `TagAuraEffect` + the aura-origin fallback rule) landed. Melee/ranged grace can ship on the batch alone; **magic** correctness additionally needs D-29's wave interleaving, so #240 is not done until both.

---

## D-29 — Depletions resolve as a set, and the resolver owns deaths

**Question:** damage currently lands per projectile *arrival*, and each depletion runs its own full cascade synchronously. What decides who dies, and when? (#240, spell propagation)

**Resolution:** **Deaths are decided during resolution, as a set, per wave. Playback animates a decided outcome and decides nothing.**

**How it works today.** `SkillNode.take_damage` emits `Events.skill_node_depleted` synchronously (`skill_node.gd:692`), and `BattleSystem` runs the *entire* islanding cascade on that signal (`battle_system.gd:116`). Damage is applied in `Projectile.arrived` callbacks (`arrow_volley_coordinator.gd:41-43`, `magic_bounce_coordinator.gd:153-156`), so depletion order is projectile *arrival* order — flight time, i.e. euclidean screen distance between nodes. The headless path (`battle_system.gd:186`) interleaves differently again.

**What that does and doesn't break — stated precisely, because the loose version is wrong.** Under D-28's post-cut recompute the *died/graced set* is already order-independent, so playback order does **not** decide who survives. Two properties make it so: `nodes_islanded_by_removing_set` reports every core-**un**reachable node rather than only newly-cut ones, so each later depletion re-sweeps standing islands; and the surviving-source set is `sources − D`, which has no order in it. (Relatedly, `gather` over `owned − D` needs no fixpoint: anything routing to a carrier *through* an unsustained node is farther from the carrier than that node, hence unsustained itself.) The three real reasons to batch:

1. **Magic wave-reactive propagation** — genuinely order- and timing-dependent, and the substantive one. Deaths in wave N change what wave N+1 branches over.
2. **Grace bookkeeping and its side effects are not order-free even when the set is.** A node graced by X's cascade, whose source is killed by Y later in the same wave, gets registered, announced, and then swept — countdown entries created and destroyed, VFX and hooks firing for a reprieve that never existed. Computing the final graced set once per wave is what makes the *observable* behavior match the verdict.
3. **Preview/result parity.** Headless and VFX paths interleave differently, so a test can pass against an interleaving the shipped game never produces.

**The resolver can decide deaths without applying damage.** It already knows every `DamageInstance` and every node's HP, so it carries a speculative HP ledger through the wave loop and calls D-28's `apply_depletions` per wave. Preview stays exactly equal to the result, AI move-scoring still works, and the projectile-ordering nondeterminism disappears because playback stops deciding anything.

**Three resolution clocks** (distinct from `spell-vfx.md`'s beat/travel/visual *playback* clocks):

1. **Route topology lags one wave.** Next-wave candidates are selected against the topology as of the *start* of the current wave, before its own kills land.
2. **The HP ledger is live within the resolve.** Damage accumulates across waves; deaths are known immediately.
3. **Defensive stats are a cast-time snapshot.** Every landing in one cast resolves against the defender's board as of the cast.

**Why (3) — and it is the load-bearing constraint.** `_on_node_damaged` has *zero* handlers today (`effects/effect.gd:48` declares the hook; no subclass implements it), so nothing reactively changes HP mid-cast and the ledger really can be just HP. But `_on_node_deallocated` **does** have handlers — `aura_effect.gd:59` and `tag_aura_effect.gd:43` both recompute — and `Mitigation.apply` merges the node board with the owner's, so killing node A can strip an aura granting armor to node B and change B's mitigation later in the same cast. Rather than shadow-run the whole modifier pipeline (which would duplicate it and drift), a cast resolves against the board the caster saw. It is the rule a player can reason about and an AI can score. The user's framing: *if the first node to die is one that adds HP, deducting that before the next wave is not intuitive at all.*

**Why (1).** Worked through TrailBlazer on a long string: each hop deals `N, 2N, 3N…`, so eventually a hop is a killing blow, and the node ahead was eligible because it had degree 2. If the kill were applied before candidate selection, the dead node behind would drop the node ahead to degree 1 and disqualify it — the spell would stop for a reason the player cannot see. Selecting candidates *before* applying the wave's kills gives the plain, intuitive "keeps blasting down the string." **Stop-on-kill remains a legitimate per-spell knob** for a spell whose fantasy is expending itself on the kill — a config option, not a global law.

**A killed node counts as unallocated for propagation filters.** Whether a spell continues through it is then just its existing filter config — a spell that allows propagation to unallocated nodes naturally continues, one that doesn't naturally stops. No new concept. Exception: a core node is not "killed-unallocated" — `take_damage` routes core overflow to the entity health pool and returns early (`skill_node.gd:686-689`), so the node only vacates when the entity dies.

**Impl status:** Not built. Melee and ranged batching is pure cleanup (order-independent, target set fixed). Magic is the substantive part: `SpellResolver.resolve` (`spell_resolver.gd:55-120`) currently precomputes every wave up-front against frozen cast-time state, so wave-reactive propagation is a **new feature**, not something batching preserves — the wave loop must interleave resolve → ledger → `apply_depletions` → next wave.

---

## D-30 — Degree has three disagreeing definitions, and Resonator is authored against the wrong step

**Question:** Resonator should propagate to the largest-degree node(s) each hop (ties → more than one). It doesn't. What is "degree" when propagation targets by it? (#240 spinoff)

**Resolution (settled):** **Resonator propagates to the highest-degree neighbour(s), ties included.** `attack/spell/defs/resonator.tres:37` wires `step_fan` (`FanAllStep` — "goes everywhere the filter allowed"), which contradicts both the intent and `DegreeRanker`'s own docstring (*"Drives Silencing Bolt / Resonator targeting (max-degree fan)"*). The machinery already exists: `TakeTopNStep` + `DegreeRanker`. Two gaps: the `.tres` must be rewired, and `TakeTopNStep` takes exactly `take_count` after a stable sort — it has **no tie-inclusive mode**, so "the largest degree node(s)" with three-way tie currently yields one. Needs an `include_ties` option. This needs a test; it is the explicitly-requested deliverable.

**Open fork — which degree does propagation targeting read?** Three definitions are live and they disagree:

| Definition | Self-loops | Scope |
|---|---|---|
| `GraphMirror.get_degree` (`:115-119`) | counted, **×2** | mirrored subgraph |
| `GraphMirror.get_nodes_by_degree` (`:122-128`) | **ignored** | mirrored subgraph |
| `DegreeRanker.score` | via `graph.get_neighbours` | **true graph degree** |

The first two disagree with each other outright — a self-loop-heavy node is high-degree to *gating* and invisible to *selection*. That is a plain bug independent of any spell. The third contradicts **D-4**, which settled degree-for-gating as *allocated*-degree via `EntityNavigator.get_degree`; propagation targeting reads true graph degree instead. D-4's scope was cast-source gating, so this is not strictly a reversal — but propagation targeting needs its own explicit answer rather than inheriting one by accident.

This is load-bearing for Resonator specifically, whose crit condition keys on self-loops (`crit_self_loop`) while its targeting would key on a degree notion that may not count them. Reconcile the accessors before any degree-*selection* ships.

**Impl status:** Not built. `resonator.tres`, `take_top_n_step.gd`, `graph_mirror.gd`. Filed separately from #240.

---

## D-31 — The node combat pool ratchets exactly like the entity pool

**Question:** D-21 pinned cap-change semantics for the *entity* `health` pool. The per-node combat HP pool (`node_combat_health`) was never given the same answer, and #346 observed nodes sitting at ~1/10 max HP. What happens to a node's `current` when CON moves its cap? (#298 / #346)

**Resolution:** **Mirror D-21. Cap rises → grant the delta into `current`. Cap falls → clamp `current` to the new max, never subtract.**

The node pool gets no bespoke rule. `node_combat_health.tres` already carries `heal_on_max_increase = true`, so the authored intent was always this; only the code path bypassed it.

**Restating the three options, because #346 blurred them:**

| Option | Rise | Fall | Status |
|---|---|---|---|
| Symmetric | grant delta | **subtract** delta | **Rejected** (D-21) — losing a high-CON node would be more lethal than a low-CON one, so investing in the defensive attribute makes you *more* fragile |
| **Asymmetric / ratchet** | grant delta | **clamp only** | **Adopted** — this decision, matching D-21 and #276's acceptance criterion 6 |
| Voluntary/forced split | grant delta | voluntary subtracts + is illegal if lethal; forced reduces max only | **Recorded, not adopted** (D-21) — still the first thing to reach for if the ratchet misbehaves |

"Do not lose the healed delta" (#346's wording) means **do not subtract it**, not "let `current` exceed max". A pool where `current > .value` is not a legal state.

**Why it looked broken.** `Stat.base_value`'s setter never runs `PoolStat._apply_max_change()` — that is reachable only from the modifier path. `SkillNode._sync_combat_health_base()` followed the owner's `node_health` baseline with a **raw `base_value` write**, so the cap moved outside the ratchet entirely: no grant on a rise, no clamp on a fall. As CON climbed with level, every allocated node's cap rose while `current` stayed frozen, and node regen (~1/turn, D-9) could not close a widening gap. Not a ratchet misbehaving — a path that never entered it.

**⚠ Consequence that D-21's bounding argument does NOT cover: this ratchet is territory-wide.** Node content grants `constitution` to the **entity** board, so one CON allocation raises `node_health` once and the re-sync signal fans that delta into **every owned node's** `current` — up to ~218 nodes at L100 (D-16). D-21 accepted its exploit on the explicit grounds that *"DP is not free"*: there, one DP bought one pool's delta. Here one DP buys `delta × owned_nodes`, so the payoff scales with territory while the cost stays flat, and `node_health_scaling` as a class knob multiplies it again. The cycling shape survives too — damage nodes below `max − delta`, then alloc/dealloc a CON node repeatedly; clamp-on-fall never claws anything back from a *damaged* node.

This is accepted for now, because the alternative on the table was frozen `current` (unambiguously broken) and because the ratchet is the semantics D-21 already pinned. But it is **not** bounded by the argument D-21 used, and it is **live input to #274 / #278** — the damage tuning those issues do is measured against exactly these numbers, which is the ordering constraint lane A exists to protect. The standing lever if it misbehaves is the same one D-21 recorded: the voluntary/forced dealloc split. Registered as a balance invariant to measure on **#268**.

**The bypass is load-bearing and stays.** A raw `base_value` write is the deliberate door for moving a cap *without* the ratchet, and three callers depend on it: `SkillPointStat.claim()` (which is exactly what distinguishes it from `grant()`, and `AllocationSystem` calls it on every allocation), `GrowablePoolStatDef` growth, and combat-pool seeding. Welding the setter shut would have made every `claim(1)` silently mint a spendable SP. So the fix names the *other* door — `PoolStat.set_base_ratcheted()` — rather than removing this one. See `docs/domain/stat-knobs-and-bins.md` §3.

**Impl status:** **Built** — #346. `PoolStat.set_base_ratcheted()` routes into `_apply_max_change` → `StandardPoolStatDef.grant_max_increase_delta` (still the single named home for the ratchet, per D-26). Pinned by `test/unit/test_node_board_health.gd`; the claim-vs-grant distinction is pinned by `test/unit/test_skill_point_stat.gd`.

---

## D-32 — A spell has exactly one absolute number; every propagation knob is a ratio

**Question:** D-20 pinned "board stat × per-spell coefficient", but implementing it exposed six overlapping damage knobs — `SpellDef.base_damage`, a proposed `int_scaling`, a proposed `damage_formula`, `PropagationConfig.seed_damage_fraction`, and the per-hop ramp — with no rule for which layer owned what. The complaint that forced this: *"too many layers to pass through from definition to final effect."* (#274, round 8)

**Resolution:** **`power` is the only absolute number in a spell. Everything downstream is a ratio of the seed.**

```
seed  = spell_damage(source_node) × spell.power
hop n = f(hop n-1)          f = the spell's HopDamageProgression
```

Three layers, each answering exactly one question — *who casts* (`spell_damage`, INT-driven board stat), *which spell* (`power`), *how it travels* (the progression). The seam is testable, and that test is the design:

> **Doubling `spell_damage` doubles every hit, and no propagation knob changes value.**

**Why the propagation layer owns shape but never magnitude.** A hop **is a re-cast** — `PropagationStep._propagate_to` mints a fresh `CastSpell` from its predecessor, so "the hit node casts the spell again at its neighbour" is the implementation, not an analogy. Under that reading the geometric factor is *re-cast efficiency*, a property of the walk; `power` is a property of the spell. Different layers, different questions.

**The dimensional bug this exposed.** `AddRamp(increment = 2.0)` put an **absolute** number in the ratio layer. At INT 1000 a Resonator seed is ~100 and the ramp still adds +2 per hop — the ramp decays to rounding error and the spell silently becomes flat at high level. Trailblazer had the same defect. The additive term is therefore a **fraction of seed** (`damage + seed × seed_fraction_per_hop`), which keeps growth **linear in hops** — preserving D-30/#352's "the convergence crit is the only multiplicative source" — while scaling 1:1 with INT. The ramps were authored before anything scaled with INT, so this was latent, not wrong at the time.

**Knobs deleted outright** (each had zero users, verified across all seven spell `.tres`):

| Deleted | Why |
|---|---|
| `PropagationConfig.seed_damage_fraction` | `1.0` in every spell. Its motivating case ("¼ power initially, then ramp") is a lower `power`. |
| `SpellDef.int_scaling` (proposed) | Same number as `base_damage`, spelled twice. Collapsed into `power`. |
| `SpellDef.damage_formula` (proposed) | A seventh path through one number. Exotic scaling belongs on a `spell_damage` modifier, where the stats system already handles it. |
| `AffineRamp` | Zero users; its both-terms case is covered by the expression form, which now has `seed` in scope. |

**`spell_damage` is absolute, not a percent.** `default_value = 1.0`, intrinsic linear INT formula, mirroring `blade_damage` (STR) and `ranged_damage` (DEX). Decided on the addon test: a node-local "mana font" must read `+2 spell damage` and behave exactly like a spike addon on `blade_damage`. **`spell_range` being a percent is not a counter-precedent** — it is a percent on a *hop count*, a dimension where no absolute is meaningful.

**No spell opts out of INT.** There is no melee weapon that ignores STR. A low-scaling spell is `power = 0.3`; a fixed-damage utility effect is an `OnHitEffect`, not base damage.

**Naming.** `HopDamage` → `HopDamageProgression` (the `…Damage`/`Propagation` collision was the live confusion), with `MultiplyProgression` / `AddProgression` / `ExpressionProgression` — literally the ratio and the difference of a geometric and an arithmetic progression.

### ⚠ AMENDED same day — "the dimensional bug" was not a bug

**The text above is left standing because its reasoning is the trap.** Read the amendment before acting on it.

The claim was that `AddRamp`'s absolute increment is a dimensional error because it becomes rounding error at high INT. The arithmetic is right and the conclusion is wrong. **An absolute additive term is a compressive curve, and compression is a legitimate — and needed — spell personality.**

| Caster | seed | `+2`/hop, hop 6 | ratio to seed |
|---|---|---|---|
| INT 10 | 2 | 14 | **7.0×** |
| INT 1000 | 101 | 113 | **1.12×** |

Absolute damage still rises with INT (14 → 113). What collapses is the spell's *edge over its own seed*. So a flat-ramp spell is **strong for a novice and marginal for an archmage** — which is exactly the design target:

> We want spells that scale more and spells that scale less. A 10–50 INT novice should have spells that do real work. A bruiser who spots that one granted spell fits *this particular enemy topology* should be able to wreak havoc with it despite terrible INT. Reading the opportunity is the play.

**What was actually wrong was the invariant, which was stated too strongly.** "Doubling `spell_damage` doubles every hit" holds only for **relative** progressions. It is a per-class property, not a global law:

| Progression | Term | Scales with caster | Invariant |
|---|---|---|---|
| `MultiplyProgression(factor)` | geometric | yes | holds |
| `ScaledAddProgression(seed_fraction_per_hop)` | arithmetic, relative | yes | holds |
| `FlatAddProgression(increment)` | arithmetic, **absolute** | **no, deliberately** | **does not apply** |
| `ExpressionProgression` | authored | author's choice | n/a |

`ScaledAddProgression` still earns its place beside `MultiplyProgression`: linear growth is a different shape from geometric, and Trailblazer's `max_hops = 20` makes an exponential ramp unusable. `FlatAddProgression` earns its place because **the compression is the point** — its docstring must say so, or someone will "fix" it again.

**So the layer rule survives, restated honestly:** `power` is the only absolute number a *spell* carries, and a progression declares whether it scales with the caster. What is forbidden is not an absolute term — it is an **undeclared** one. The three classes make the declaration syntactic: you cannot author a ramp without choosing whether it scales.

**Migration is now zero-change**: Resonator and Trailblazer stay flat-additive at `increment = 2.0`, behaviour identical. No fixture pinning trick needed. Whether either *should* be flat or scaled is a **#278** personality call.

**Impl status:** **Specced, not built** — #274, sized L, `Ready`. Every fork is closed in the issue body under `SETTLED`. Numeric rates remain **#278's**, measured on **#268**. The gates that stop high INT from auto-winning are **D-33**, not damage tuning.

---

## D-33 — Spell power is gated by four independent conditions, not by damage tuning

**Question:** D-18 made INT the deliberate runaway and D-32 made spell damage scale linearly with it. What stops a high-INT caster from simply winning? If the answer were "tune damage down", D-18's payoff would be cancelled and the archmage fantasy with it. (#274 round 8 / #278)

**Resolution:** **A spell's power is gated by four independent conditions. Damage tuning is not one of them.** A sick high-INT wizard lobbing a pyroblast *should* feel devastating; the constraint is on **when they get to do it**, not on how hard it lands.

| # | Gate | How it binds |
|---|---|---|
| 1 | **Knowing the spell** | Innate in your spellbook, or granted by a node you hold (#206). Not everything is castable. |
| 2 | **Casting degree** | `SpellDef.min_degree`, read as **entity degree** — incident edges whose far endpoint you *also* own (D-30). This is the primary gate. |
| 3 | **Mana** | Cost vs. pool and regen. **Settled — see D-34.** |
| 4 | **Range from the cast node** | Hop or euclidean reach to eligible primary targets. Hops and euclidean are *not* interchangeable (#278). |

### The degree ladder

Degree is the load-bearing gate because it is **topological and positional at once** — it cannot be bought with attributes, only built.

| `min_degree` | Tier |
|---|---|
| 1–2 | Low. Everyday spells; castable from most of your territory. |
| 3 | Medium. Wants a deliberate small hub. |
| 4 | Picky and tricky. Powerful spells live here. |
| 5+ | Real powerhouses. Endgame. Good luck meeting the condition — but if you do, may god help your enemies. |

**Gates 2 and 4 fight each other, and that tension is the game.** A 6-degree hub in the middle of nowhere casts nothing worth casting. You are pushed to build a *smaller* 3–4 degree hub near the frontline instead of one perfect tower in safety. Reach and degree are a genuine positional trade, not two independent stat checks.

### Every attack channel stays a live tool

Investing heavily in STR, DEX, or INT makes the other two weaker *by comparison* — it must never rule them out. **A high-INT caster should still take a cut vertex with a Ranged attack when they spot the opportunity.** Reading the opportunity is the play, and the three channels are three tools with different topological affinities.

The spellbook is the same idea one level down: **each spell is a tool that thrives against a different topology.** That is why D-32 keeps compressive (flat-ramp) progressions — a low-INT bruiser who recognises that one granted spell fits this enemy's shape gets to wreak havoc with it. Spell selection is pattern recognition, not a damage ladder.

### Mana — settled by D-34

Gate 3 was the weakest. The premise that the pool max and regen were "plucked from the air" was **stale by the time D-33 landed** — they were already wired to INT (see D-34 for the verification and the resolution). The bar this gate must clear stays as the test:

> If mana never blocks a cast, why have the resource. If it always blocks, why have it.

D-34 answers it; **#278 is unblocked** once #268 lands the measurement invariants D-34 registers. The ladder values are authored per `SpellDef` and pinned by **#278** (a user pinning session, not a drone — see its body).

---

## D-34 — Mana is INT-bought across-turn sustain tempo (gate 3 settled)

**Question:** D-33 deferred the mana gate as "unsettled" and floated the full option space — flat pool, attribute-scaled regen, territory-scaled regen, positional mana bins, or deletion. **#365** carried the fork. (2026-08-03 / #248 lineage)

**Verified against `master` before deciding** (the #365 body's "plucked-from-the-air magic numbers" premise was stale):

- **Pool max is already INT-derived.** `entity/default_entity_board.tres:307` `pool_mana.base_value = 10`, plus intrinsic `mod_int_to_mana` → `RatioFormula(intelligence, divisor 10.0)` (`:174-181`). So `mana_max = 10 + INT/10`.
- **Regen is already INT-derived.** `mana_per_turn` intrinsic via `formula_int_to_mana_pt = "floor(log10(max(1e-5, float(intelligence))))"` (`:183-192`); applied as `PoolStat.run_turn_upkeep` ADD per turn (`stat_board.gd:373`, `pool_stat.gd:45-59`).
- **All 7 `SpellDef`s wire `HopRangeFinder`.** `EuclideanRangeFinder` exists in code but no `.tres` uses it — #278's "hops vs euclidean both live" framing is also stale; whether euclidean survives is itself #278's call, not a live mana-design input.

**Resolution: mana is KEPT, INT stays the owning attribute, the current shape stands.** No code change is required to land this decision — pool max and regen are already expressed as board stats read as formula inputs (the D-26 / `node_health_scaling` precedent the #365 body asked for), so `#268` can vary them.

- **Purpose: across-turn sustain tempo, not burst gating.** Pool max grows linearly with INT (`INT/10`); regen grows `log10(INT)`. At BalancedCore's flat +10 INT a fresh caster has max=11, regen=1/turn (Spark every turn, Reverberator drains in one cast and needs ~4 turns dry). At the D-18 INT 1000 endgame max=110, regen=3 — **pool stops binding against 1–5 cost spells; log-regen becomes the gate.** An archmage sustains Spark every turn forever but Reverberator only every ~1.7 turns. That is *the reason the resource exists*: it caps sustained casting rate, never burst capacity.
- **Level scaling is indirect, by caster investment** — via the +1 INT/level grant (D-15). There is no separate mana-per-level channel; a levelled caster who refuses to buy INT does not grow their mana, by design (consistent with D-15's "stagnation is punished by the map"). Confirmed: `BalancedCore` touches STR/DEX/INT/CON/WIS only, never `mana`/`mana_per_turn`.
- **Per-entity pool, not positional bins.** #365 raised "per-node mana bins you build and raid" as a possible topological fit with the other gates. Rejected — the other three gates already carry the topology load; a per-entity INT-bought pool is the deliberate odd one out, *because* every caster identity choice concentrates there.
- **Dry caster has ranged + melee (D-33).** A spent wizard still takes the cut-vertex with a Ranged attack. Mana never gates *having* an action, only *which* action. This is the property that answers "if it always blocks, why have it": it never blocks the turn, only the spell.
- **The D-18 "quadruple-dip" concern is accepted, not patched.** INT buys damage (linear, D-32), reach (hard-capped ×2, D-18), pool (linear), regen (log). The compression of the utility terms — cap on reach, log on regen — is *what keeps "buy INT" from being "win"*. The damage payoff stays unbounded because D-18 promised the archmage fantasy; the gates that stop high INT auto-winning are the compressive utility curves + the topological gates (degree, range), never damage tuning.

**Invariants registered on #268** (to be printed per L5/L20/L50/L100 fixture, with INT matching a mid-WIS build at that level):

1. **`casts_before_dry`** — count of the highest-cost `SpellDef` a fresh full pool sustains from max to empty, no regen. Proves the pool binds somewhere in the curve (the test against "if it never blocks").
2. **`sustain_rate = regen / cheapest_cost`** — sustained casts/turn of the cheapest spell once steady-state is reached. Proves log-regen actually binds at high INT (the test against "if it always blocks" — it never blocks the cheapest spell, by construction).

**Impl status:** Resolved by decision; **no code change to land** — pool-max and regen are already formula-input board stats. #365 closes as Done. #278 is unblocked (its hops-vs-euclidean premise will be re-verified when that session runs; the euclidean finder's absence from `master` is noted there).

---

## Decisions log

- 2026-06-25: All 8 D-decisions resolved in roadmap session. Issues to follow.
- 2026-07-21: D-9 … D-13 resolved in the #248 balancing design session. Numeric values deliberately **not** pinned here — they live in `.tres` / the stat board, gated on the #268 harness. Starting SP / starting allocated node count remains **open** (see #248).
- 2026-07-21: D-14 added, D-10/D-11 revised (round 2–3) — durability scales through CON; CON drives `node_health` only; the aura is an authored `base`/`range` channel.
- 2026-07-21: **D-15 … D-17 resolved — the progression cluster.** XP economy, SP gain, attribute bands. Starting SP / starting node count now **closed** (D-16). Still open on #248: procgen↔level linkage · INT→spell damage · `core_healing` · the node-local `armor` mitigation bug · per-attribute numeric personalities (D-17).
- 2026-07-21: **D-18 … D-23 resolved — the INT / durability / level-dial cluster (round 5).** Every remaining #248 hub item is now closed or has a home:
  - **D-18** INT is the runaway; utility compresses (`spell_range` hard-capped at ×2), damage is the linear payoff; `bonus_hops` is battlefield-found and adds *after* the multiplier. Settles the substance of **#273** (log scale forced) without closing its UX fork.
  - **D-19** enemy level = starting nodes (`/1`, levelled-but-landless); elevated enemy WIS lives on the CoreClass and is the difficulty dial, `level_ratio = √(W/20)` — a **spawn-time handicap, not a standing invariant**.
  - **D-20** spell damage: board stat × per-spell coefficient, read from the **cast-from** node, evaluated **once at seed**.
  - **D-21** entity `health` scales with CON; `dealloc_damage` is the paired class knob; the CON max-HP delta **is** granted, guarded by not granting the DP alongside a raised DP maximum.
  - **D-22** `core_healing` heals the *entity* pool and stays a sliver — CON expansion is the real heal.
  - **D-23** procgen needs no level input: entity level + the already-shipping radial gradient cover it. Basic keystone = **+20 WIS scattered broadly**; placement machinery (v1 vs v2 stitching) stays #180's.
  - **Retired as stale:** the node-local `armor` mitigation bug was fixed in **be477f5** — `Mitigation.apply` reads `defender.get_local_value(&"armor")`. Only a stale `KNOWN BUG` block in `.claude/rules/stats-system.md` survived it.
  - **D-24** territory selection is ONE policy — `pick_next(entity, candidates)` — shared by spawn seeding and the AI, with the candidate set injected by the caller (the `RangeFinder.gather(source, mirror)` pattern) and tactical objectives switchable off. The AI spends **all** available SP each turn, not one node.
  - Still open, each with its own issue: the **spell-balance pass** (mana cost × degree requirement × hops-vs-euclidean reach — hop distance ignores edge length, so the two range kinds are not interchangeable) · **enemy CoreClass composability** (every enemy needs a mostly-similar batch of modifiers; the authoring architecture is unsettled) · `core_healing` rate + gate.
- 2026-07-23: **D-28 … D-30 resolved — the LifeLine / death-resolution cluster (round 7).** Survival generalized to **life sources with a reach** (core = ∞, lifeline addon = 2 hops); "connected to core" is just core's case, and nothing about it enters `GraphMirror`. **Two earlier #240 decisions are superseded:** the pre-cut spare-set *snapshot* (wrong — config C4 falsifies it; protection must be `has_tag` recomputed on the **post-cut** subgraph) and the relocation of the depletion cascade into `AllocationSystem` (dropped — the seam is a shared `apply_depletions` function called by both speculative resolvers and real playback, owned by neither system). Depletion always beats grace, including for the carrier itself. **D-29** moves death decisions out of playback into resolution — not because playback order decides the *set* (under D-28's post-cut recompute it provably doesn't), but for wave-reactive magic propagation, for grace bookkeeping whose side effects *are* order-sensitive, and for preview/result parity. **Still open:** which degree definition propagation targeting reads (D-30) — three live definitions disagree, two of them outright. **Deliberately not an MVP decision:** the **lifelink** addon (permanent, unbounded, virtual-edge) — explored and found orthogonal to D-28, parked in its own backlog issue.
- 2026-07-22: **D-25 … D-27 resolved (round 6).** `core_healing` is an **integer** heal (placeholder 1/turn), **ungated and unramped** — a ramp would reward the camping D-10 punishes, and the existing "incoming next turn" gauge segment makes integer free while a sliver is net-new UI. `dealloc_damage` corrected to a **curse/debuff knob**, not a scaling base. `core_health_scaling` added as the CON coefficient (default 1.0); the flat +10 stays baked. **D-21's asymmetric ratchet is kept as pinned** — the voluntary-vs-forced dealloc split (voluntary subtracts the delta and is gated as illegal if lethal; forced reduces max only) is recorded as a **good split to think along**, not adopted: the ratchet is probably strong, but DP is not free, and if it misbehaves there are a thousand ways to mitigate it. **The requirement that came with that:** the delta grant must live in a **named method**, never inlined, so the toggle is findable when we do change it. D-27 settles #279 by reference-composition. **#273 settled** — static log, fixed floor/ceiling, bounds shared across entities so an enemy's radar is comparable to your own (#228 renders them side by side). **New fork surfaced:** entity-only stats have no scope marker (D-26).
- 2026-07-31: **D-12 marked built, and #299 closed on the design fork it was blocking.** #299 asked whether CON deserves a full archetype or whether `defensive.tres` expressed "defensive territory" better. Settled on design grounds — **`defensive.tres` was a smell that adding CON solved, so CON keeps its archetype** — without waiting on #268, since the question was about where defence *lives*, not how it is tuned. Consequence: `defensive.tres` is deleted and its `Role.DEFENSIVE` pools moved into `constitution.tres`, giving the defensive axis one authoring home. Provably inert (the flatten filters per-`TierPool`). `node_health` ADD_BASE dropped in the same pass — with base `node_health = 10 + CON`, a flat draw was numerically identical to the percent draw at L1 and decayed after; the percent channel survives, re-ranged to `+5–15%`. **New fork surfaced:** `Role` is a 3-valued enum encoding a 2-valued fact (`DEFENSIVE` and `RARE` are mechanically identical), and it is fully derivable from `archetype_stat` emptiness — filed as **#319** with two live proposals: rejecting off-archetype rolls outright (which would revise D-12 away) and replacing `RARE` with pre-authored keystones.
- 2026-08-02: **D-31 resolved, and #298 settled without a new mechanism (lane A opening).** The node combat pool ratchets exactly like the entity pool (grant on rise, clamp on fall); #346's "~1/10 max HP" was a raw `base_value` write bypassing the ratchet, not the ratchet misbehaving, and the bypass itself is kept because `SkillPointStat.claim()` depends on it. **#298's fork is dissolved rather than answered:** the CON→`node_health` rate is neither a CoreClass genesis param (option 2 — a real cliff, since coreless entities exist) nor a split board-baseline-plus-class-delta (option 1), but `node_health_scaling`, an ordinary board scalar read as a formula input — the D-26 `core_health_scaling` precedent, which `.claude/rules/stats-system.md` already stated as *"no genesis/class-param mechanism is needed or wanted here"*. **Generalized while it was fresh:** a tunable rate is a board stat; the authoring procedure for that and for pool bins is now `docs/domain/stat-knobs-and-bins.md`. Per-class coefficient *values* remain #268's. Unblocks #274 / #278.
- 2026-07-31: **D-12 revised away — procgen draw-model v4 lands via #321.** Both of #319's live proposals landed: off-archetype rolling is rejected entirely (this revises D-12 — the "starve survivability" rationale only held while defence had no home; CON + the universal `archetype_stat == &""` pool axis are now that home), and `RARE` is abolished. v4 replaces `TierPool`+`TierDef`+`Role` with one flat `StatPool`, a single `TierLadder` (`value = 2·cost − 1` → costs [1,2,4,8], V [1,3,7,15]), a spend-until-broke + per-`(stat,op)` aggregation draw (ADD*/INCREASE sum, MULTIPLY product, SET max), and an auto-stamped tier→rarity tag map (T1/T2 common, T3 rare, T4 mythic) so the radial band profile finally gates content that can actually be rolled. Rare content (`rare.tres`) becomes 4 pre-authored `Keystone` SkillNode scenes under `entity/keystone/instances/` (placement wiring is a separate open issue). `first_level.tres` budget envelope tuned (field outer 5→4, `rbp_main` outer.mythic 8→3) per the v4 simulation. Retuning from the seed table is #268's job. See `docs/domain/procgen-v4.md`.
- 2026-08-03: **D-32 AMENDED same day, and D-33 resolved — the gating cluster.** The "AddRamp is a dimensional bug" reasoning in D-32's first draft is **wrong and is left standing as a trap marker**: an absolute additive ramp is a *compressive* curve (7x seed at INT 10, 1.12x at INT 1000), which is exactly the novice-spell / topology-specialist niche the design wants. What was actually too strong was the **invariant** — "doubling spell_damage doubles every hit" is a per-progression property, not a global law. Three progressions now declare their own answer (`Multiply` / `ScaledAdd` relative, `FlatAdd` deliberately absolute); what is forbidden is an *undeclared* absolute, not an absolute. Migration becomes zero-change. **D-33** then answers what actually stops a high-INT caster: four independent gates — knowing the spell, casting degree (the ladder: 1-2 low / 3 medium / 4 picky / 5+ endgame), mana, and range — with degree and range in deliberate tension, so a 6-degree hub in the middle of nowhere casts nothing. Damage tuning is explicitly NOT a gate; the archmage fantasy is the payoff D-18 promised. **Mana** was called out as unsettled here; **settled same day by D-34** (the premise that pool max and regen were "plucked from the air" was stale — they were already INT-derived on `master`; #278 unblocked).
- 2026-08-03: **D-32 resolved — #274's knob stack collapsed (round 8).** Six overlapping spell-damage knobs became three layers and one rule: `power` is the only absolute, every propagation knob is a ratio of the seed. Three knobs deleted for having zero users (`seed_damage_fraction`, `AffineRamp`, and the never-built `int_scaling` / `damage_formula` pair). **The bug that forced it:** `AddRamp`'s absolute increment sat in the ratio layer, so Resonator and Trailblazer would have decayed into flat spells at high INT — latent because nothing scaled with INT yet when the ramps were written. Additive is now a fraction of seed, keeping the ramp linear (so #352's convergence crit stays the sole multiplicative) *and* INT-scaled. #274 promoted to `Ready` with every fork closed in-body; it had bounced back to `Needs design` five-plus times because "open questions" read to agents as an invitation.
- 2026-08-03: **D-34 resolved — mana gate settled (D-33 gate 3), #365 closed.** swarmify pass on #365 against `master` found the body's "magic numbers plucked from the air" premise stale: pool max (`10 + INT/10` via `RatioFormula`) and regen (`floor(log10(INT))`) were already INT-derived board-stats-as-formula-inputs — the exact D-26 / `node_health_scaling` shape the body asked for. Decision: **mana kept, INT kept as owning attribute, current shape stands, no code change to land.** Purpose is *across-turn sustain tempo* — at INT 1000 the linear pool stops binding (costs are 1–5) and log-regen becomes the gate (archmage sustains Spark/turn forever, Reverberator only every ~1.7 turns), which is the whole reason the resource exists. The D-18 "quadruple-dip" concern (INT buys damage-linear + reach-capped×2 + pool-linear + regen-log) is **accepted** — compression of the utility terms is what keeps "buy INT" from being "win", damage unbounded per the archmage fantasy. Two invariants registered on #268: `casts_before_dry` (highest-cost spell count from a full pool) and `sustain_rate = regen / cheapest_cost`, per L5/L20/L50/L100 fixture. **#365 → Done, #278 unblocked** (its hops-vs-euclidean premise also stale — all 7 spells wire `HopRangeFinder`, euclidean ladder never wired; re-verified when #278's session runs). #278 stays a user pinning session per its body — not drone work.
- 2026-08-04: **D-27 revised a third time — the mechanism is deleted, not reshaped.** `inherits: CoreClass` (`59d2444`) then `composes: Array[CoreClass]` (`1ff127e`) both composed the wrong noun: the unit of reuse is the **modifier array**, not the class. Resolution is now *a `CoreClass` `.tres` is a leaf; shared batches are file-backed resources dropped into its existing typed arrays* — a `CompositeStatModifier` `.tres` in `modifiers`, an `Effect`/`CoreAura` `.tres` in `effects` (which already composed by reference all along). Zero new API; `composes` reverted. The one thing the class-level mechanism bought — per-attribute loot granularity — turned out to be a single boolean, `CompositeStatModifier.loots_as_unit`, because composite atomicity is not intrinsic: every consumer flattens except `LootSystem._core_modifiers` and `loot_picker`. Two arguments killed the mechanism outright: it is all-or-nothing per entry (you cannot take a base's modifiers without its effects), and `CoreClass.load_all()` turned every shared base into a phantom class in the registry. **Surfaced and left open:** behaviour reuse (`on_turn_started`, `apply()` overrides) is composed by nothing, and the likely home is `Effect`, not `CoreClass`. Spun out of the same session: #323's re-cut (see below).
- 2026-08-04: **#323 re-scoped — lootability is which source arrays the draw reads, not a filter over a pool.** There is no `StatBoard.modifiers[]`; modifiers live in a private per-`Stat` `_modifiers`, so "draw from everything unfiltered" is not an available position, and harvesting the board would make an atomic `CompositeStatModifier` **structurally unlootable as a unit** (the board only ever holds flattened leaves). Instead the pool is a union of weighted **provenance buckets**, each one a source array: node grants (`node.modifiers`), class grants, board innates (`StatBoard.intrinsic_modifiers`), looted. This resolves #323's internal contradiction — its section 1 ("innate rules are not trinkets") loses to its section 2 ("stealing a growth curve is the loop"): the provenance *axis* survives, the *exclusion* dies, and **rarity does the work exclusion was doing** (a low-weight innate bucket makes looting `+1 blade_size per 20 STR` funny rather than routine). `_is_lootable`'s `scales_with(&"level")` filter is deleted. Requires a new per-entity **core-modifier register** (`Entity.core_modifiers`, granted-atoms, unflattened) with `grant_core_modifier()` as the *only* grant path so it cannot drift from the board — which is also the only place `loots_as_unit` can survive a loot round-trip, and which fixes a latent bug where the draw read a shared `.tres` template rather than what the entity actually has.
