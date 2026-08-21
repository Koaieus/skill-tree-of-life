# Audit — `attack/` (80 `.gd`, 4588 lines, + 5 `.tscn`, 8 `.tres`)

Read: every `.gd` in full, all 8 spell presets, all 5 scenes,
`docs/domain/attack_plan_system.md`, issues #381 / #356, and the rule files
covering this slice (degree, scene-composition, skill-node-scale,
rendering-performance, stat-knobs-and-bins, hdr-color).

---

## The headline hypothesis, answered with counts

**~57 lines/file is not the shape of over-fragmentation here — it is mostly the
shape of a data-driven strategy system that the `.tres` presets genuinely
exploit. But one family of 6 files is pure ceremony, and 6 more concrete
strategies have zero consumers.** The 80 files partition as:

| Bucket | Count | Verdict |
|---|---|---|
| Abstract bases (`AttackPlan`, `RangeFinder`, `Targeting`, `PropagationFilter`/`Step`, `IncidentReducer`, `HopDamageProgression`, `CritCondition`, `OnHitEffect`, `NodeRanker`, `RankPass`, `BladeConstraint`, `BladeDriver`) | 13 | Earned — each is `@export`-authored on a `.tres` and dispatched polymorphically |
| Pure data records (`CastSpell`, `PropagationContext`, `AttackOutcome`, `DamageInstance`, `HealingInstance`, `PropagationEvent`, `SpellCancellation`, `BladeState`, `BladeTrajectory`, `BladeHitEvent`, `RangeVisual`) + 2 authored-data resources (`SpellDef`, `PropagationConfig`) | 13 | Earned, with two real modelling defects (F2, F6) |
| Concrete plans | 3 | Earned |
| Melee sim + visuals | 10 | Earned as a layer; **triplicated** internally (F1) |
| Formulas / rules / resolvers | 5 | Earned — `Mitigation`, `SpellRangeRules`, `SpellResolver.impact_damage` are each "the one home" for a formula and say so |
| Range-finder concretes + visuals | 4 | Earned |
| `NodeTargeting` | 1 | Earned |
| **Concrete spell strategies** | **31** | **Mixed — see below** |

Of the 31 concrete strategies, **8 of the 8 shipped presets compose 19 of
them**; 6 have zero consumers anywhere (no preset, no test, no code — only
docstring mentions): `CoreDistanceFilter`, `MaxVisitsFilter`,
`CancelIfEvenReducer`, `ExpressionReducer`, `MinDamageReducer`,
`RandomPickStep`. `FirstReducer` is a 7th: the resolver deliberately
short-circuits `reducer == null` rather than instantiating it
(`spell_resolver.gd:227`), so the class exists only to document a default.

**The one collapse to make: the reducer fold family (F4).** Six files —
`sum_`/`max_`/`min_damage_reducer`, `first_reducer`, `cancel_if_even`,
`cancel_if_multi` — are each `_merge_payload_defaults()` plus one fold over
`incidents[*].damage`. ~20 lines apiece, 6 scripts, one behaviour axis.

**The counter-example that proves the indirection can earn its keep: the four
`HopDamageProgression` subclasses. Do not collapse these.**
`hop_damage_progression.gd:18-28` states why they are four resources instead of
one class with three knobs ("A progression DECLARES whether it scales with the
caster"), and `flat_add_progression.gd:8-22` is an explicit trap marker — the
class was once deleted as a "dimensional bug" and deliberately restored per the
D-32 amendment. Same for the `RangeFinder` / `Targeting` pair: two concretes,
both preset-referenced, with a documented non-interchangeability contract
between `in_range` and `gather` (`range_finder.gd:35-45`).

---

### 1. LARGE | attack/plan/melee_attack_plan.gd:386 | Blade construction written three times
**Defect:** `MeleeAttackPlan.build_blade_state` (L386-418) and
`SkillBlade.build_from_skill_nodes` (L62-94) are near-identical
position/radii/pivot/`sn_to_idx`/`vertex_damage`/addon-dispatch bodies, and
`MeleeAttackPlan.build_drivers` (L445-463) is a verbatim copy of
`SkillBlade._build_swing_drivers` (L163-181); `MeleePreview.launch` (L47-74)
then re-runs the whole simulate→scan→pop pipeline a third time.
**Breaks:** It has already drifted once — commit `e23d975 fix(melee): dispatch
node addons in build_blade_state (#405)` exists solely because the addon loop
was added to one copy and not the other, so preview/AI scoring disagreed with
the live swing; the comment at L384-385 claiming the method is "Public so the
MeleePreview controller can share the same construction with resolve()" is
false — `MeleePreview` calls `SkillBlade.build_from_skill_nodes` instead.
**Fix:** Make `SkillBlade` build from a `BladeState` the plan hands it (one
`build_blade_state` + one `build_drivers`, both on the plan) and delete both
copies from `skill_blade.gd`.

### 2. LARGE | attack/outcome/propagation_event.gd:47 | Parallel per-effect-kind slots, not a hit list
**Defect:** `AttackOutcome` carries `hits: Array[DamageInstance]` beside
`heals: Array[HealingInstance]`, and `PropagationEvent` carries singular
`damage` beside `heal` — the two TODOs (`healing_instance.gd:9`,
`propagation_event.gd:50`) are the same defect, and it is issue #381.
**Breaks:** `spell_resolver.gd:96` ships a live `assert(outcome.hits.size() -
pre <= 1, "landing appended >1 hit; VFX applies only the first")` — an assert
guarding a structural limitation — and `magic_bounce_coordinator.gd:164-176`
already carries a patched-bug comment about the two-slot shape dropping a heal;
every new effect kind (DoT, shield, mana burn) adds a slot to two classes plus
a branch to every consumer.
**Fix:** #381's `Array[HitInstance]` is the right shape — take it, and settle
in that issue where `DamageInstance.Type` lives, since `HealingInstance` has no
`type` field and a naive shared parent would either hoist a damage-only enum or
leave the subclasses asymmetric again.

### 3. LARGE | attack/spell/defs/reverberator.tres:71 | Preset contradicts its own description and test
**Defect:** The shipped config is `TakeTopNStep(take_count=2)` +
`MaxDamageReducer` + `ScaledAddProgression(0.5)`, while its own player-facing
`description` says "Fans to every enemy neighbour, +{SEED} damage per hop.
Converging branches ADD" and `test_spell_defs.gd:70-73` asserts
`SumDamageReducer` + `MultiplyProgression` — description and test agree with
each other and disagree with the data.
**Breaks:** This is a shipped-content bug, not just a red test: players read a
description that describes a different spell, and the self-loop-crit identity
("the spell feeds back into its own path") only works with an additive merger.
All three diverged inside one commit, `aca098b`, whose title claims to be a
`TakeTopNStep` refactor — editor-side design churn rode along unreviewed.
**Fix:** Decide which Reverberator is intended (the description's Sum/FanAll
identity is the documented one, per #352's Resonator/Reverberator design), then
fix the `.tres` and test together — **not fixed here, reporting only.**

### 4. MEDIUM | attack/spell/propagation/reducer/sum_damage_reducer.gd:10 | Six reducer files, one fold axis
**Defect:** `sum_`/`max_`/`min_damage_reducer`, `first_reducer`,
`cancel_if_even_reducer`, `cancel_if_multi_reducer` are each
`_merge_payload_defaults(incidents, node)` plus one fold or one cancel
predicate over `incidents[*].damage`; `ExpressionReducer` already subsumes
every one of them (`sum_damage`, `max_damage`, `min_damage`,
`incident_count if incident_count >= 3 else -1`).
**Breaks:** Adding a seventh fold (average, median, "top two") means a seventh
script, a seventh `.uid`, a seventh `ext_resource` line in every consuming
preset — and an author picking a merger in the inspector has to distinguish six
near-identically-named scripts instead of reading one enum.
**Fix:** One `FoldReducer` with a `Mode { SUM, MAX, MIN, FIRST, CANCEL_IF_MULTI,
CANCEL_IF_EVEN }` enum; keep `IncidentReducer` abstract for genuinely bespoke
reducers and keep `ExpressionReducer` as the escape hatch.

### 5. MEDIUM | attack/spell/propagation/filter/max_visits_filter.gd:1 | Dead filter whose docstring narrates an unbuilt design
**Defect:** Zero consumers (no preset, no test, no code path), and the rule it
claims to enforce is already enforced unconditionally by the resolver —
`spell_resolver.gd:124-129` caps candidates by `config.max_visits_per_node`
with the comment "Always enforce … even if filter is null."
**Breaks:** Its 18-line docstring describes three abandoned plumbing designs
("the resolver injects `cap` before each filter call", "let `PropagationConfig`
mirror its `max_visits_per_node` onto this filter at compose time") that nothing
implements, and its `fallback_cap = 1` would silently *disagree* with a preset's
`max_visits_per_node = 6` if anyone ever composed it — Reverberator territory.
**Fix:** Delete the class; the resolver's unconditional cap is the real rule.

### 6. MEDIUM | attack/spell/propagation/propagation_context.gd:16 | `CastSpell` and `PropagationContext` duplicate four fields
**Defect:** `caster`, `graph`, `rng` and the seed node (`CastSpell.seed_node` /
`PropagationContext.seed_node`) live on **both** objects, threaded through
every propagation call side by side; `_merge_payload_defaults` then hand-copies
all of them per merge (`incident_reducer.gd:38-41`).
**Breaks:** Two live copies of the same state can disagree (nothing keeps
`state.graph` and `ctx.graph` equal), and every strategy author must decide
which one to read — `DegreeFilter` reads `ctx.graph`, `LeafCritCondition` reads
`state.graph`, for the same value.
**Fix:** Strip the per-cast constants off `CastSpell` and read them from the
context. *(Note: this refutes the brief's framing of #356 — `PropagationContext`
is a single class, not duplicated across paths; see F14 for what #356 actually
describes.)*

### 7. MEDIUM | attack/plan/melee_attack_plan.gd:495 | Full edge-list walk per candidate node per repaint
**Defect:** `_is_neighbor_of_blade_set` iterates all of `graph.get_edges()`, and
is called from `get_node_role` — i.e. once per node, per highlight repaint —
alongside `get_induced_edges` (L423) and `collect_target_excludes` (L477), which
each walk every edge or every node too.
**Breaks:** At the 500–2500-node scale `.claude/rules/rendering-performance.md`
mandates, that is a nodes × edges walk per repaint — the exact quadratic-CPU
shape this codebase has hit before, and the shape #385 already fixed for
`MagicAttackPlan` via `_cached_valid_targets`.
**Fix:** Give `MeleeAttackPlan` the same `state_changed`-invalidated adjacency
cache `MagicAttackPlan` got in #385, built off one pass over the edge list.

### 8. MEDIUM | attack/plan/ranged_attack_plan.gd:61 | #385's per-repaint scan, still unfixed for ranged
**Defect:** `get_node_role` (L67) and `get_node_range` (L79) each call
`get_firing_positions().has(node)` — a navigator leaf-node query plus a linear
`Array.has` — once per node per repaint; `get_reaching_firing_positions` re-runs
the same query again inside `validate()`.
**Breaks:** Identical to the cost #385 removed from `MagicAttackPlan`, left in
place on the ranged path, so the ranged overlay degrades with graph size while
the magic overlay no longer does.
**Fix:** Cache the firing-position set as a `Dictionary[SkillNode, bool]`
invalidated on `state_changed`, mirroring `MagicAttackPlan._valid_targets()`.

### 9. MEDIUM | attack/plan/melee_attack_plan.gd:25 | Temp-upgrade catalog is an untyped Dictionary protocol
**Defect:** `CLAMP_UPGRADE`/`SPIKE_UPGRADE` are bare `Dictionary` literals with
implicit `.scene`/`.script` keys; four public methods
(`can_apply_temp_upgrade`, `has_temp_upgrade_budget`, `apply_temp_upgrade`,
`temp_upgrade_cost_for`) take `upgrade: Dictionary`, and
`TEMP_UPGRADE_CATALOG.has(upgrade)` (L201) does membership by Dictionary
identity.
**Breaks:** Nothing type-checks a caller passing the wrong dict shape; the
`script` key exists only because `can_attach_addon` needs Script identity before
an instance exists (L36-39), and `static var _cost_cache` (L46) is a second
workaround for the same missing type — three workarounds for one absent class.
**Fix:** A small `TempUpgradeDef` Resource (or inner class) holding
`scene`/`script`/`cost`, which absorbs the cost cache and lets the catalog be
`Array[TempUpgradeDef]`. This is the newest code in the slice (#406) — cheap now.

### 10. MEDIUM | attack/range_finder/range_finder.gd:54 | Base `gather()` violates its own documented contract
**Defect:** The base implementation writes `out[n] = 0.0` for every in-range
node, while its docstring promises nodes "mapped to **its distance**" and adds
"The returned distance is what feeds an aura's `DistanceScale` — a bool
predicate cannot express Halo's shell or the Ninja's per-hop debuff."
**Breaks:** Both shipped subclasses override `gather`, so the defect is
invisible today and bites the *third* finder someone writes — it will silently
collapse every distance-scaled aura to distance 0.
**Fix:** Make `gather` `@abstract` (the two concretes already implement it), or
return `-1.0` as an explicit "unknown distance" sentinel.

### 11. MEDIUM | attack/melee/skill_blade.tscn:1 | Scene ships without the children its code depends on
**Defect:** `skill_blade.tscn` contains only an `Edges` child, so
`skill_blade.gd:_ready` (L35-45) `get_node_or_null`s **and code-constructs**
both containers at runtime.
**Breaks:** Direct violation of `.claude/rules/scene-composition.md` ("a scene
must ship pre-packaged with the children its `@onready`s depend on"); the scene
previews wrong in the editor and the runtime tree diverges from the authored one.
**Fix:** Add the `Nodes` `Node2D` to the `.tscn` and reduce `_ready` to two
`@onready` lookups.

### 12. MEDIUM | attack/spell/on_hit/healing_effect.gd:13 | TODO says "nothing consumes" — both consumers now exist
**Defect:** The TODO claims neither `BattleSystem`'s headless path nor
`MagicBounceCoordinator` consumes `AttackOutcome.heals`; both do —
`systems/battle_system.gd:209-211` and
`ui/vfx/coordinator/magic_bounce_coordinator.gd:173-176` each call
`heal.target.heal_damage(...)`.
**Breaks:** A stale TODO on a shipped feature (`healing_beam.tres` composes
`HealingEffect`) reads as "this is unfinished, don't build on it" and will cost
the next author a re-derivation. **Not dead code — a lying comment.**
**Fix:** Delete the TODO; the surviving structural concern is F2 (#381).

### 13. MEDIUM | attack/plan/melee_attack_plan.gd:423 | `get_induced_edges() -> Array` of positional pairs
**Defect:** Returns an untyped `Array` of two-element `[SkillNode, SkillNode]`
arrays, indexed as `pair[0]`/`pair[1]` at three call sites
(`melee_attack_plan.gd:405`, `skill_blade.gd:82`, `melee_preview.gd:86`) — while
`graph/edge.gd` already models an edge with named `from`/`to`.
**Breaks:** No type-checking on a structure the whole melee pipeline threads;
the `.from`/`.to` names are stripped at the boundary and re-derived positionally
by every consumer.
**Fix:** Return `Array[Edge]` (the induced subset of `graph.get_edges()` is
already what the body computes) and index `.from`/`.to`.

### 14. NIT | attack/spell/propagation/reducer/incident_reducer.gd:21 | Every stock reducer's `ctx` param is dead; crit's `outcome` is always null
**Defect:** All 7 reducers name the parameter `_ctx` and read nothing from it;
`CritCondition.evaluate(state, target, outcome)` receives `outcome` as a literal
`null` from its only caller (`spell_resolver.gd:195`).
**Breaks:** Two abstract signatures advertise capabilities the pipeline does not
supply — an author writing a context-dependent reducer will find the object
present but the resolver never populating per-landing data into it.
**Fix:** This is exactly issue #356 (which is `Needs design` pending the
one-context-vs-sub-context fork); confirmed accurate as filed. Do not
pre-empt it — settle the fork first.

### 15. NIT | attack/spell/propagation/filter/core_distance_filter.gd:1 | Six concrete strategies with zero consumers
**Defect:** `CoreDistanceFilter`, `MaxVisitsFilter` (F5),
`CancelIfEvenReducer`, `ExpressionReducer`, `MinDamageReducer`, `RandomPickStep`
appear in no preset, no test, and no code path — only in each other's
docstrings. `FirstReducer` is a near-seventh (the resolver short-circuits
`null` rather than using it, `spell_resolver.gd:227`).
**Breaks:** Each carries a confident docstring describing gameplay that does not
exist ("Drives Homing Decoring and Corifugal Bolt"), so a reader can't tell
shipped mechanics from speculative ones; `CoreDistanceFilter._bfs_distance` also
runs a fresh whole-graph BFS *per edge candidate*, a landmine if it ever ships.
**Fix:** Delete the ones no design doc still wants (`MaxVisitsFilter`,
`MinDamageReducer`, `CancelIfEvenReducer` at minimum) and mark the rest in their
docstrings as unshipped with the issue that will consume them.

### 16. NIT | attack/spell/propagation/propagation_context.gd:15 | Bare `Dictionary`/`Array` where a typed collection belongs
**Defect:** 26 occurrences across the slice (I counted 26, not the brief's 34).
Sharpest instance is `var global_visit_count: Dictionary = {}  ## SkillNode ->
int` — the type parameter is written as a comment in the exact position the type
parameter belongs. Same pattern at `spell_resolver.gd:54` (`groups` —
`SkillNode -> Array[CastSpell]`), `blade_pop_resolver.gd:43/68/97/115`
(`particle_idx -> float`/`-> bool`), `melee_preview.gd:21-22`,
`melee_attack_plan.gd:394/430/448/484`, `skill_blade.gd:72/166`,
`blade_hit_scan.gd:32-33`.
**Breaks:** Every one is a homogeneous map the engine could check for free;
`BladePopResolver.Result.dead_at` is the riskiest — it crosses a public API
boundary into `MeleePreview._on_live_hit`, untyped.
**Fix:** Add type parameters; they are all single-type maps.

### 17. NIT | attack/range_finder/visuals/range_edge.gd:95 | Unconditional per-frame redraw makes its own signal wiring dead
**Defect:** `_process` calls `queue_redraw()` every frame regardless of change,
which makes the `endpoints_changed` connect/disconnect machinery at L77-88 (plus
the `_exit_tree` teardown) pure dead weight. `blade_edge.gd:29-30` has the same
unconditional `_process` redraw.
**Breaks:** These are spawned one-per-edge —
`HopRangeFinder.get_visual` (L80-96) emits an `EdgeEntry` for every edge with an
endpoint in the BFS depth map — so the count scales with reach, against
`.claude/rules/rendering-performance.md`; and the maintained-but-unused signal path
misleads the next reader into thinking redraws are event-driven.
**Fix:** Drop `_process` and redraw on `endpoints_changed` (the wiring already
exists), or drop the wiring and keep the honest per-frame redraw — not both.

### 18. NIT | attack/outcome/attack_outcome.gd:14 | `ap_cost` is decoration — nothing ever writes it
**Defect:** No code in the repo assigns `AttackOutcome.ap_cost`; `BattleSystem`
gates and deducts on it (`battle_system.gd:155-167`), so every attack of every
mode costs the hardcoded default of 1. `tools/balance/balance_scenarios.gd:439`
already acknowledges this in a comment.
**Breaks:** The field advertises a per-plan AP model that does not exist, so AI
scoring and the HUD both reason about a constant; a designer setting a 2-AP
heavy swing would find no write site.
**Fix:** Either have each `resolve()` set it, or drop the field and let
`BattleSystem` own the constant until a real cost model lands.

### 19. NIT | docs/domain/attack_plan_system.md:38 | Domain doc names classes that no longer exist
**Defect:** The doc lists `SingleHostileNodeTargeting` /
`SingleAlliedNodeTargeting` as the concrete `Targeting` subclasses (L38, L274)
and `get_highlight_role(node)` on `AttackPlan` (L21); the shipped names are
`NodeTargeting` (one class, with an `ownership_filter` flag mask) and
`get_node_role`, which now lives on `HighlightProvider`.
**Breaks:** It is the doc the brief points auditors and new agents at first, so
the first thing a reader learns is three names that don't compile.
**Fix:** Refresh the "What's in" section against the current class list.

### 20. NIT | (brief correction) | "26 missing `-> ` return types in attack" is a false positive
**Defect:** All 26 hits are multi-line function signatures whose return type
sits on the closing-paren line (e.g. `blade_state.gd:26` `static func build(` …
L30 `radii_: Array[float]) -> BladeState:`). Zero functions in `attack/` lack a
return type.
**Breaks:** The same naive grep produced the brief's procgen-22 and ui-9 counts,
so sibling auditors will likely burn time on the same non-finding.
**Fix:** Discard the metric; a `->`-anywhere-in-signature check is the right one.

---

## Verdict

The domain is well modelled and this slice is not over-fragmented in the way the
hypothesis suspected — the strategy explosion is genuinely data-driven, the eight
`.tres` presets compose 19 of the 31 concrete strategies, and the codebase
pre-refutes the obvious "collapse the four progressions" move with a trap marker
citing the last time someone tried. The real defects are elsewhere: the melee
pipeline is written three times and has already drifted once in a shipped fix
(#405), the outcome layer models effects as parallel per-kind slots and ships a
live assert guarding that limitation (#381 is the right shape), and one commit
titled as a refactor silently retuned the Reverberator preset away from both its
test and its own player-facing description. Six concrete strategies have zero
consumers and a seventh exists only to document a default, which is where the
line-count hypothesis is actually right. Two per-repaint quadratic walks survive
in the melee and ranged plans — the exact cost #385 removed from magic and did
not generalise.
