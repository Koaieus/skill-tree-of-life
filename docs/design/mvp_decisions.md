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

**Scaling:** the aura base scales with CON **sub-linearly** (e.g. `∝ √CON`) while `node_health` scales linearly (D-14). A flat base would decay into irrelevance as `Y` grows; matching linearly would keep the fortress dominant forever. Sub-linear means the aura is **decisive early and a thumb on the scale late** — which is the right curve, because a 100-node entity's aura covers a small fraction of its territory anyway, and late-game combat shouldn't be decided by core proximity.

**Parameters live on the AuraEffect resource, not the stat board.** Putting `aura_heal_base` / `aura_heal_falloff` on the board would mean canonicalising core healing as board stats — and it isn't clear that's the right shape (it would also need a node-local meaning it doesn't obviously have). Authoring them per-effect keeps each aura self-describing and lets future authored auras implement whatever logic they want without first negotiating a stat vocabulary.

Total per-turn heal = `(node_healing + regen_stacks × node_healing_ramp) + aura_flat`, where the `regen_stacks` term is subject to the D-9 gate and `aura_flat` is not. Taking damage still resets `regen_stacks` to 0 — so a node under sustained fire inside the aura receives a small constant trickle and never reaches the ramp payoff.

**Rationale:** Flat (not %) deliberately avoids compounding with `node_health` investment — it makes healing relatively stronger on cheap nodes and weaker on beefy ones, which is the healthier balance direction and costs no fractional-accumulation UI. Healing through combat is what gives the core's neighbourhood a fortress identity and makes aura *range* a load-bearing class decision. Denying the ramp under fire caps how fast regen *grows* under sustained pressure. Keeping the aura outside the ramp term keeps two independent, tooltip-readable numbers instead of one compounding one. Linear falloff gives the "gradient of safety" a flat radius can't.

**⚠ The sanctuary bubble — bounded by `range`, still must be watched.** Denying the ramp does *not* stop a besieged node out-healing its attacker: the aura term ignores the gate, and near the core it exceeds baseline incoming damage by design. Nodes well inside the aura are genuinely hard to chip down. **That is intended** — the core's neighbourhood should be a fortress, and taking one should demand focus-fire, burst, or TRUE damage rather than chip.

What must stay bounded is *how much of an entity's territory* enjoys it. That is what `range` is for. If the aura covers most of a 50–150 node entity, it out-heals the chip damage that drives the forced-dealloc cascade (see below) and the core's death clock stops ticking entirely. **The guard is `range ≪ territory radius`,** not the ramp denial. Tracked as a named invariant in #268.

**Why the aura does not need to bribe the core forward.** An earlier framing had the aura carrying the anti-camping burden — reward core proximity so players don't hide it. Unnecessary: the **forced-dealloc cascade already punishes camping structurally.** Every depleted node costs 1 unmitigable core HP, every node islanded by that loss costs another, and the entity sheds whatever stats those nodes granted. So an entity camping its core in a defensible corner still dies on a clock as its periphery is chipped away, and its "well-defended" core degrades as the territory supporting it falls off. (`dealloc_damage` defaults to 1 and is a natural hook for CoreClass debuffs, or later Hexes/Curses that raise it on an active target.) Structural pressure beats an incentive gradient — so the aura is free to be a pure reward, and `range` exists to bound coverage, not to force position.

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

## Decisions log

- 2026-06-25: All 8 D-decisions resolved in roadmap session. Issues to follow.
- 2026-07-21: D-9 … D-13 resolved in the #248 balancing design session. Numeric values deliberately **not** pinned here — they live in `.tres` / the stat board, gated on the #268 harness. Starting SP / starting allocated node count remains **open** (see #248).
