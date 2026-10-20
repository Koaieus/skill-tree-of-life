# Authoring an aspect cell — what each column of the matrix actually touches

The design table is `docs/design/aspect_matrix.md`; this is the *what is*:
for each column, the files a cell lands on, the fields that carry its
identity, the registry that makes it exist, and the test that notices when
it is missing. A **full row** is simply every cell for one concept; a
**column pass** is one cell for every concept. The same list either way.

**Every cell ends on the Aspect.** A concept's row is
`aspects/defs/<concept>.tres` (an `Aspect`, listed on
`aspects/aspect_roster.tres`): a cell that lands a facet sets it there —
`stat`, `status`, `ammo`, `addon_scene`, or an entry in `spells`. The facet
carries the concept's `Identity`, never the Aspect.
Guard: `test/unit/aspects/test_aspect_roster.gd`.

## Stat (prerequisite for every other cell)

- `stats_system/defs/<concept>_aspect.tres`, a child of the `aspects`
  parent (ADR 0029) with `identity` + `role = ASPECT`, on
  `stats_system/stat_def_roster.tres` — no board field: every entity board
  mints it at init, read as `board.facet(&"<concept>", StatDef.Role.ASPECT)`
  (ADR 0054). The `manage-stats` skill is the checklist.
- It is a **count**, read three ways: arrows minted per reload (flat off
  the entity board, `Entity.reload_yield`), the per-swing cap on that
  concept's temp addons (`test_temp_upgrade_budget.gd`), and whatever
  infusion settles on (#1250). Potency stays `<family>_stacks_per_hit`.
- Findable in play only once an attribute pool places it (#1249).

## Arrow (ranged column)

One `AmmoType` resource, `attack/ammo/types/<concept>.tres`, plus one line
on `attack/ammo/ammo_type_roster.tres` (hard `ExtResource` edges; a folder
scan does not survive export), plus one look scene. No code:
`Entity.reload_yield`, the ranged tray's ammo cards and
`AIController._compose_volley` iterate the roster. The column's design —
markers, the flare, every arrow's look — is `docs/design/aspect_matrix.md`
§ Arrow faces; this section is the shelf a new arrow shops from.

| facet | field | note |
|---|---|---|
| stats | `order` | volley position: lower fires and lands first, the base arrow sits at 100, scout last (120). A **marker** flies early (curse 40, mark 30, greed 5) |
| | `damage_scale` | raw-damage multiplier before mitigation; markers 0.3, plain stacks 0.5 unless the row says otherwise (sunder 0.75), blindness and scout 0 |
| | `max_stock` | the type's own bank cap, outside the shared quiver capacity (ADR 0041); 999 unless tuned (curse and corruption 6) |
| | `per_reload_stat_id()` | derived: the concept's ASPECT facet (base arrow authors `base_per_reload_stat_id`) |
| effect | `on_hit_effects` | `OnHitEffect` riders run in order on every landing arrow ([On-hit shelf](#on-hit-shelf)) — usually one `ApplyStatusEffect` of the concept's `effects/status/<concept>.tres`, its `power` the stacks per landing arrow before potency × (1 − resistance). A scout type is one `ApplyStatusEffect(scouted.tres)` rider with `damage_scale` 0 (`AmmoType.is_scout()`) |
| looks | `visual_scene` | the type's own inherited scene of `ui/vfx/projectile/visual/status_arrow.tscn` under `ui/vfx/projectile/visual/arrows/<concept>_arrow.tscn`, picked per shot by `ArrowVolleyCoordinator` (#1351, #1352). A look is parts, not code ([Look shelf](#look-shelf)). `test_ammo_type_roster.gd` requires a statused type to fly its own scene |

Guards: `test/unit/attack/test_ammo_type_roster.gd` (roster vs disk, ids,
distinct mint stats, order invariants, own scene per statused type),
`test/unit/command/test_reload_command.gd`, `test/unit/vfx/test_arrow_parts.gd` (the parts),
`test_status_arrow_visual.gd` (the lifecycle).

### On-hit shelf

`RangedDamageFormula.ride` builds one `HitLanding` per arrow, anchored at its
slot in the outcome (paired to it, so a gated arrow duds every rider), runs
each effect, then places the span: statuses just before the arrow, damage-shaped
riders just after (ADR 0067). The arrow takes the landing's `hit_key`, and the
coordinator finds its riders by that key (`riders_of`). What an arrow may carry:

| effect | what it gives an arrow | example |
|---|---|---|
| `ApplyStatusEffect` | `def` + `power` stacks on the landed node, folded through the read node's `<family>_stacks_per_hit` | every statused arrow |
| `SplashEffect` | runs its `inners` (via `OnHitEffect.run_all`) on the target unless `hits_centre` is off, then again on every other node its `range_finder` gathers around the target (over the global `Navigator`, unscaled) whose ownership bit matches the mask — `NodeTargeting`'s mask + finder pair, the caller sets the radius on the finder. The mask is `ownership_filter`, or at **0 the landing's own `target_mask`** (hostile for an arrow or blade, the spell's targeting filter for a spell): a splash hits what its hit may hit. Each copy keeps the hit key, pairing, raw amount and mask, and every hit a copy emits re-checks the same mask at land (`land_mask`, ADR 0049); the gather goes through the landing's `gather_cache` — one per volley, keyed (target, finder, reach), pre-mask — so a volley's splashes on one node sweep the board once | blindness's flare: `HopRangeFinder(max_hops = 1)` + Hostile |
| `PairedDamageEffect` | a `PairedDamageInstance` (a `PairedHealInstance` when the landing's `paired` is a heal) on the landed node worth `fraction` × the landing's `raw_amount` (the arrow's or contact's amount, a spell payload's damage), fixed at compile (pre-crit, pre-mitigation, so each node mitigates it once by its own armour); with a `paired` hit it duds with it and copies its crit at land, on a damage spell landing it stands alone; a heal spell's landing rides its heal (`LandingContext.ride_heal`) | Explosive's shrapnel, inside a `BlastEffect` |
| `BlastEffect` | a `SplashEffect` preset: `hits_centre = false` (the centre already took the main hit), `ownership_filter = 0` (inherit the landing's mask). Its reach is its finder's, built by whoever emits it — one finder per distinct radius, so `gather_cache` still dedupes a volley | Explosive's blast: `BlastEffect(EuclideanRangeFinder, [PairedDamageEffect])`, built only by `ExplosiveSpread.blast_for` (the explosive status's spread owns the boom: reach = node radius × `reach_per_radius` × power^`charge_exponent`, via `radius_for`; see `docs/domain/explosive.md`) |
| `DetonateEffect` | never authored: `DetonateEffect.arm(riders, load)` (the arming rule's one owner) prepends it at the hit's detonate `load` to every arrow's riders (`RangedDamageFormula.riders_for`, load 0) and a cast's riders (`SpellResolver`, `Infusion.detonate_load`), unless any rider lands explosive (a `PlantUse` hit, which never blasts); a riderless hit still detonates. With `present` charges on the target (a core with none reads its entity host), not yet set off in `HitLanding.detonated` (per arrow, per spell wave, shared by a splash copy), it blasts iff `power_of(load, present, resonance) > 0`: a `spend_of` = `max(1, min(load, present))`-stack `CureInstance` spend when `present > 0`, then `ExplosiveSpread.blast_for(target, power, [chained Detonate, PairedDamageEffect] + riders minus explosive)` — so a blast chains through charged nodes and never plants. The formula: `docs/domain/explosive.md` | Explosive's detonation |
| `OnHitEffect.status_def()` | the seam a wrapper answers through, so `AmmoType.first_status_def()` (tint, card swatch, scout check) never type-switches; a new wrapper overrides it | `SplashEffect` |

**Not on the shelf:** `DamageEffect`, `HealEffect`, `ScaleDamageEffect` and
`AddStackTermDamageEffect` extend `SpellOnHitEffect`, which the `on_hit_effects` setter refuses at load
(`attack/ammo/ammo_type.gd`). An arrow's damage is the arrow itself
(`damage_scale`); a damage-dealing rider is `PairedDamageEffect`.

**Markers need no plumbing.** A volley lands in `order`, and every landing
reads the target's live slice, so a status an early arrow landed is already
there when the arrows behind it hit: curse lifts their damage floor, mark their
crit chance. Crit rolls *at landing* (one draw per hit, in landing order, off
`AttackOutcome.crit_stream` — local, never on the wire, null on a rebuilt
`AttackRecord`, which lands its recorded crits); `docs/domain/attack-timeline.md`.
Guards: `test_marker_arrows.gd`, `test_crit_at_landing.gd`, `test_splash_effect.gd`, `test_splash_reach.gd`, `test_splash_gather_cache.gd`, `test_paired_damage_effect.gd`, `test_blast_effect.gd` — all on `test/support/volley_board_fixture.gd`.

### Look shelf

`StatusArrow` (`status_arrow.gd`) finds every `ArrowPart` child and drives
it through one lifecycle; it never names a part. The base scene already
carries `Trail` (`ArrowShedEmitter`), `Tip` (`ArrowTip`) and `Burst`
(`ArrowImpactEmitter`): a look overrides their exports on the inherited
instance, or instances more parts from `ui/vfx/projectile/visual/arrow_parts/`.

The lifecycle, the same for every part (`arrow_part.gd`):
`paint(tint, dud, absorbed)` — the shot's SDR status colour, or the verdict;
`launch()` — leaves the string; `stop()` — struck or spent;
`arrive(ctx)` — only a landing that *counted* (not a dud, not absorbed),
with the `ArrowImpactContext` the coordinator built; `drain_seconds()` —
how long the part outlives its stop. Shared exports: `show_on_dud`,
`show_on_absorbed`, `fades_with_shaft` — off on `ArrowPart` and the impact
parts, but `ArrowTip` defaults to `show_on_dud` + `fades_with_shaft` and
`ArrowShedEmitter` to both `show_on_*` (the plain trail keeps flying for the
defender's absorb). A part reads only its arguments and
its exports — never the arrow or a `SkillNode`.

| part | knobs a look sets | used by |
|---|---|---|
| `ArrowTip` | `shape` POINTED / BLUNT / CLUB, `length`, `width`, `tier`, `fade_to_shaft` (colour runs out toward the shaft), `pulse_hz` + `pulse_depth` (a beating head) | every look; blunt: sunder, blindness; club: corruption, weakness; pulse: corruption, greed, mark; fade: poison, wither |
| `ArrowShedEmitter` | (emitter knobs) + `density` (share of `amount` emitted; keeps a 20-arrow volley readable), `world_space` | the base trail; a second one: poison's froth |
| `ArrowImpactEmitter` | (emitter knobs) + `spread` TIP / RIM / RIDERS (every non-dud rider's target), `rim_spots`, `per_spot`, `delay` (hold the burst while a mark lingers) | the base burst; rim: wither; riders: blindness's cloud; delay: corruption |
| `ArrowImpactSprite` | `texture`, or with none a `shape` RING / EYE (`lid_ratio`, `pupil_ratio`; the scale curve is the lid opening — a blink); `anchor` TIP / NODE; `lifetime`, `size`, `ring_width`, `scale_curve`, `alpha_curve`, `tier` | corruption's pustule, curse's contracting ring, greed's gilding, weakness's thud, mark's eye |

Emitter knobs (`ArrowEmitterPart`, both particle parts): `process_material`,
`texture`, `amount`, `lifetime` (also the drain), `tier`.

`ArrowImpactContext` carries `position` (target centre), `radius` (its grown
radius) and `rider_positions` (non-dud riders' targets, in hit order) — all a
part may know about the landing. A part that needs more (a reveal radius, an
edge list) is a new context field filled by
`ArrowVolleyCoordinator.impact_context_for`, never a part reading the board.

Gotchas:

- **Colour is never authored.** `status_tint` is stamped per shot from
  `AmmoType.first_status_def().tint`; each part lifts it to its `tier`
  (`Emissive`), and an inert-looking part is `tier = 0`. The part scene's own
  `process_material` is the one material every instance shares, so a volley
  stays batched — a look that needs a different motion gives its instance a
  new `ParticleProcessMaterial` sub-resource, never a per-node uniform.
- Writing `amount` restarts an emitter's buffer; the part writes it only on
  a change.
- A restyled trail usually sets `show_on_dud = false` / `show_on_absorbed =
  false` explicitly (sunder, bleeding, corruption, wither, poison's
  froth) — a per-look choice, not a default.
- **Widen a part, don't script a look.** Every look so far is a pure `.tscn`;
  when one needed a behaviour the kit lacked, the part grew an export
  (`ArrowImpactEmitter.delay`, `ArrowImpactSprite.shape`). A new part class
  only for genuine behaviour two looks share.
- `StatusArrow.finished` waits on a timer, not `GPUParticles2D.finished`,
  because a headless run never processes particles.

| arrow | parts it touches |
|---|---|
| sunder | blunt wide tip; spark trail; fragment burst |
| bleeding | sparse drip trail |
| blindness | inert blunt tip; grit trail; smoke cloud burst spread over riders |
| corruption | beating club tip; swelling blip trail; delayed pop burst; pustule sprite |
| curse | inert tip and trail; contracting ring at the node |
| explosive | pulsing fuse tip; spark trail (second shed emitter) |
| greed | pulsing tip; tumbling coin trail; gilt ring |
| mark | pulsing tip; eye sigil blinking open at the node |
| poison | fading neon tip; froth (second shed emitter) |
| scout | the base look, its own scene so its flare can come |
| weakness | short wide club tip; thud ring |
| wither | fading tip; ash-flake trail; rim crumble burst |

## Addon (map and temp are one scene)

One `SkillNodeAddon` scene, `skill_node/addons/defs/<name>_addon.tscn`.
The scene *is* the addon (`docs/domain/scene-composition.md`); a subclass
only when a hook needs code. Lead-by example: `spike_ring_addon.tscn`.

| facet | where | note |
|---|---|---|
| modifiers | `entity_modifiers`, `local_modifiers` | authored arrays; a subclass may synthesise stake-scaled ones via `get_local_modifiers()` / `get_entity_modifiers()`. On a blade, entity modifiers apply for the swing except currency (`aspects` family, `blade_size`) |
| per-turn effect | `effects` — an `Effect` with a hook (`_on_turn_start`, …) | granted to the holder on allocation with the carrier as `source_node`, revoked when the node is cut — no subclass. Example: `abyssal_conduit_addon.tscn`'s `SelfCorruptEffect` |
| addon-owned hooks | `on_turn_start()` (the owner's turn start, every owned node, host and mirror), `on_detached()` (after the carrier's ledger erase; runtime, non-temp) | for behaviour the addon itself describes on its carrier rather than an entity-wide `Effect`. Example: `explosive_barrel_addon.gd` refills its carrier's charges to its barrel count and spends one on removal |
| blade effect | `on_hit_effects`; `apply_to_blade(state, idx)` for code | optional — node-local stats are often enough (SpikeRing needs none). Any addon's authored `on_hit_effects` (usually one `ApplyStatusEffect`; a `SpellOnHitEffect` is refused) ride every contact its carrier's vertex lands — no subclass; the base `apply_to_blade` appends them to that vertex's rider list, so two addons on one carrier both apply. An override must call `super` |
| looks | a `Visual` child on the `AddonVisual` base (#1212) and/or `get_emblem()`; `icon`, `tint`, `description` for the tooltip | an addon with no visual child is invisible outside its tooltip |
| budget | `temp_placeable`, `temp_cost_blade_size` (≥ 1), `temp_cost_aspects` (`{&"<concept>_aspect": n}`, each > 0) | every currency is a pooled per-swing budget capped by the attacker's live stat; landed, guarded by `test_temp_upgrade_budget.gd`. Set `temp_placeable = true` explicitly: the script default `false` is not a design call — every addon is placeable unless its cell records a dated exclusion (`aspect_matrix.md` § The addon recipe, item 6) |
| role | `SkillNodeAddon.role`: offence / debuff / defence / utility, the job it does on a forged blade; never left `UNSET` (guarded by `test_temp_upgrade_catalog.gd`) | `docs/design/temp_addon_shop.md` § Role tags |
| procgen | an entry in each content pool's `AddonPolicy` (`procgen/modules/*/content.tres`), `weight`, `unique` | optional, lower priority |
| customization | anything the contract lacks | a new hook, extra hitscans, perf work — named in the cell so it becomes its own unit |

Guards: `test_addons_are_scenes.gd`, `test_addon_kind.gd`,
`test_addon_defs_folder.gd`, `test_addon_on_hit.gd`, `test_melee_temp_upgrade.gd`.

## Spells (magic column)

One `SpellDef` per spell, `attack/spell/defs/<id>.tres`, plus a `const` and
an `ALL` entry in `attack/spell/spell_catalog.gd`
(`test_spell_catalog.gd` fails on a def missing from the catalog).
A spell is many facets, each its own design call:

| facet | fields |
|---|---|
| identity | `id`, `name`, `tagline`, `description`, `icon` |
| cast gate | `min_degree`, `carve_shape` |
| reach | `targeting` (a `Targeting` with a range finder), `propagation` (`PropagationConfig` + filter; its `reach` swaps graph neighbours for another candidate set, e.g. Firecracker's `FuelBlastReach`) |
| payload | `power`, `on_hit_effects` (`DamageEffect`, `HealEffect` …; the one on-hit vocabulary for every mode, see `docs/domain/effect-system.md` and ADR 0044) |
| status | `intakes` (`AspectIntake{identity, innate, affinity_gain, affinity_cost, use}`) + `ingest_gain` / `ingest_cost` (§ Infusion, ADR 0060) |
| crit | `crit_conditions` (`LandingCondition`s) |
| presentation | `vfx_coordinator_scene`, `windup_vfx_scene`, `tempo` (`.claude/rules/spell-vfx.md`) |

An intake row's `PlantUse.stack_terms` (`StackTerm`s, e.g. `DefenderStatShare`) ride its
rider and land as extra stacks; share the SAME SubResource with an
`AddStackTermDamageEffect` authored before `DamageEffect` and the spell also hits
harder by that amount — one formula, two readers (Rend, `rend.tres`).

The design work is what else the spell does, so it is not "damage plus status" again.

## Infusion (magic column — ADR 0047, ADR 0060, #1250)

Five words, one meaning each (owner, 2026-10-13, #1593):

| term | means | where |
|---|---|---|
| **innate** | the spell's authored starting amount of a concept | `AspectIntake.innate` |
| **affinity** | the per-concept exchange rate, `gain:cost` ints; 0 refuses ("venom has 2:1 poison affinity") | `AspectIntake.affinity_gain` / `affinity_cost`; 1:1 when unlisted |
| **ingest rate** | the spell-wide exchange rate, multiplied with every affinity | `SpellDef.ingest_gain` / `ingest_cost` |
| **infusion** | what the caster adds this cast | `Infusion.points` |
| **load** | the final amount: `innate + floor(infusion × ingest × affinity)`, exact int arithmetic | `Infusion.load_of` |

A spell's status is the **load** of its intake rows, not an authored rider:

- `attack/spell/aspect_intake.gd`: `AspectIntake{identity, innate, affinity_gain, affinity_cost, use}` — points at the concept's `Identity` (a concept with no status can be listed); `status()` resolves the concept's `StatusDef` by id. Its `get_description` gives the tooltip's line, as its use's `describe`. `use` is a `LoadUse` resource (`attack/spell/load_use/`, ADR 0070): `PlantUse` (lands the status rider; owns `stack_terms` and `power_from`), `DetonateUse` (spent at the hit as a blast), `FuelUse` (spends nothing), `CleanseUse` (the load is the cap of one shared `CleanseEffect` per cast, found in the bag's riders by `template`); null takes the concept status's `StatusDef.default_face` through `AspectIntake.use_for_status` (`resolved_use()`; explosive detonates, everything else plants). A **shaping intake** (`use = FuelUse`, Firecracker's explosive fuel) lands no rider: its load still counts in `load_of` and the readouts, and a spread or reach reads it from `PropagationContext.load` (the cast's `load_of`), never from `riders` — Firecracker's `FuelBlastReach` burns it as fuel.
- `attack/spell/spell_def.gd`: `intakes: Array[AspectIntake]` and the ingest pair `ingest_gain` / `ingest_cost` (default 1:1; ingest 0 refuses every infusion).
- `attack/spell/spell_def.gd`: `infusion_capacity` (most points one cast of this spell takes in total; `INF` = each aspect capped only by its own stat).
- `attack/spell/infusion.gd`: `Infusion.innate(spell)` / `for_cast(spell, points)`, `points` (concept id → points), `ratio_of` (affinity × ingest as a `gain:cost` `Vector2i`), `gained` (⌊points × gain / cost⌋), `load_of` = innate + `gained`, `riders` / `detonate_load` (both read `bag`: one walk over `load_of`, each concept with load above 0 spending it through `use_of(spell, id).spend(...)` into a `LoadBag`); `rate_of` is that ratio as a float, for display and the refusal test only. Riders are one `ApplyStatusEffect` per `PlantUse` concept with a status (a `PlantUse.power_from` is copied onto its rider: the rider lands that named `CarriedScalar`'s value instead of the load wherever the payload carries one — Fault Line's crack, #1721) (a `DetonateUse` load is `detonate_load`, spent at the hit; a `FuelUse` load only shapes the spell); every concept finds its status through `effects/status_roster.gd` (`StatusRoster.by_concept`). `AspectRoster` ranks above `attack`, so it can't serve that lookup. A new `effects/status/*.tres` joins `effects/status_roster.tres` (`test_status_roster.gd` pins it).
- `attack/aspect_currency.gd`: `AspectCurrency.cap_of(attacker, stat_id)`, the one floored board read behind melee's `currency_cap` and magic's caps; `stat_of(concept)` = the concept's ASPECT facet id (`StatRegistry.facet_def`).
- `attack/plan/magic_attack_plan.gd`: `infusion` (never null; innate after `set_spell`), `set_infusion(id, points)`, `aspect_overrun()` (per-aspect stat + `infusion_slots` + total over `floor(infusion_capacity)` when finite + refused points), the `"infusion"` wire key (only when points are spent; `from_dict` ungated, ADR 0035), and the preview and launch resolves both carry it.
- `stats_system/defs/infusion_slots.tres`: derived on `entity/default_entity_board.tres` from INT, a threshold ladder at 10 / 100 / 1000 (development tuning, owner 2026-10-14; 100 / 1000 / 10000 later) — breadth. There is **no shared points pool** (#1574, owner 2026-10-12; the √INT `infusion_points` stat of #1462 is deleted): depth is the aspect held. Nothing is consumed (ADR 0047), so a socketed aspect carries the most it can — `min(<concept>_aspect, what infusion_capacity leaves)` — and `ArmedStack.clamp_infusion` (memory restore) and `AiInfusionPicker.pick` fill each kept aspect to that.
- `attack/spell/spell_resolver.gd`: `resolve_against(…, infusion = null)` runs the riders after `on_hit_effects` at every landing, then places that landing's span (`HitLanding.place`): the riders' statuses land *before* the spell's own hits at that hop, their damage-shaped hits after (ADR 0067).

A status cell's spell lists one `AspectIntake` for the concept's
`Identity`. It never authors an `ApplyStatusEffect` in `on_hit_effects`.
`test_aspect_roster.gd` pins this. `test_infusion.gd` pins the cast-time
arithmetic and the overrun.
