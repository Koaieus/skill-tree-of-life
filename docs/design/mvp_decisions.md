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
- Self-loop generation today is naive per-node RNG. Want a better draw mechanic that supports rare-but-possible *double* self-loops on a single node (an instant magic powerhouse). Carve as a procgen issue.

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

**Resolution:** **Neither migrate nor duplicate — pools stay cross-rollable.** An archetype node may roll modifiers outside its own archetype at a reduced chance, and **that reduction is less severe for CON / defensive modifiers** than for other off-archetype draws.

**Rationale:** A hard migration would make defensive draws CON-gated and starve every other archetype of survivability. Straight duplication muddies where a stat "lives." Softening the off-archetype penalty specifically for defence keeps armor and health available as the common filler/pity draw #248 wants, while still making CON nodes the concentrated source.

**Impl status:** Not built. Requires a per-archetype off-archetype weight with a defensive-family exception. Depends on D-11.

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

**Impl status:** #268 (swarmable). Runs at entity/scene level (real fixtures), not raw formulas, because `SkillNode.take_damage` bypasses `attack/formulas/mitigation.gd` today — a formula-level harness would report balance that doesn't match play.

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

**Impl status:** Not built. `stats_system/defs/health.tres`, `entity/default_entity_board.tres`, and the DP-grant path. Child issue under #248.

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
  - Still open, each with its own issue: the **spell-balance pass** (mana cost × degree requirement × hops-vs-euclidean reach — hop distance ignores edge length, so the two range kinds are not interchangeable) · **enemy CoreClass composability** (every enemy needs a mostly-similar batch of modifiers; the authoring architecture is unsettled) · `core_healing` rate + gate.
