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
  parent (ADR 0029), on `stats_system/stat_def_roster.tres` and the entity
  board — the `manage-stats` skill is the checklist.
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
| stats | `order` | volley position: lower fires and lands first, the base arrow sits at 100, scout last (120). A **marker** flies early (curse 40, hex 30, greed 5) |
| | `damage_scale` | raw-damage multiplier before mitigation; markers 0.3, plain stacks 0.5 unless the row says otherwise (armor break 0.75), blindness and scout 0 |
| | `max_stock` | the type's own bank cap, outside the shared quiver capacity (ADR 0041); 999 unless tuned (curse and corruption 6, tentative) |
| | `per_reload_stat_id` | `<concept>_aspect` |
| effect | `on_hit_effects` | `OnHitEffect` riders run in order on every landing arrow ([On-hit shelf](#on-hit-shelf)) — usually one `ApplyStatusEffect` of the concept's `effects/status/<concept>.tres`, its `power` the stacks per landing arrow before potency × (1 − resistance). A scout type is one `ApplyStatusEffect(scouted.tres)` rider with `damage_scale` 0 (`AmmoType.is_scout()`) |
| looks | `visual_scene` | the type's own inherited scene of `ui/vfx/projectile/visual/status_arrow.tscn` under `ui/vfx/projectile/visual/arrows/<concept>_arrow.tscn`, picked per shot by `ArrowVolleyCoordinator` (#1351, #1352). A look is parts, not code ([Look shelf](#look-shelf)). `test_ammo_type_roster.gd` requires a statused type to fly its own scene |

Guards: `test/unit/attack/test_ammo_type_roster.gd` (roster vs disk, ids,
distinct mint stats, order invariants, own scene per statused type),
`test/unit/command/test_reload_command.gd`, `test/unit/vfx/test_arrow_parts.gd` (the parts),
`test_status_arrow_visual.gd` (the lifecycle).

### On-hit shelf

`RangedDamageFormula.riders_for` builds one `HitLanding` per arrow (paired to
it, so a gated arrow duds every rider) and runs each effect; the riders are
appended right after the arrow in the outcome (the coordinator reads them by
that adjacency). What an arrow may carry:

| effect | what it gives an arrow | example |
|---|---|---|
| `ApplyStatusEffect` | `def` + `power` stacks on the landed node, folded through the read node's `<family>_stacks_per_hit` | every statused arrow |
| `SplashEffect` | wraps one `inner` effect and re-runs it on every node in its `reach` (today only `TARGET_AND_HOSTILE_NEIGHBOURS`); each copy keeps the arrow's hit key and pairing, and a splashed status re-checks hostility at land (`require_hostile`) | blindness's flare |
| `OnHitEffect.status_def()` | the seam a wrapper answers through, so `AmmoType.first_status_def()` (tint, card swatch, scout check) never type-switches; a new wrapper overrides it | `SplashEffect` |

**Not on the shelf:** `DamageEffect`, `HealEffect` and `ScaleDamageEffect`
extend `SpellOnHitEffect`, which the `on_hit_effects` setter refuses at load
(`attack/ammo/ammo_type.gd`). An arrow's damage is the arrow itself
(`damage_scale`); a damage-dealing rider does not exist yet.

**Markers need no plumbing.** A volley lands in `order`, and every landing
reads the target's live slice, so a status an early arrow landed is already
there when the arrows behind it hit: curse lifts their damage floor, hex their
crit chance. Crit rolls *at landing* (one draw per hit, in landing order, off
`AttackOutcome.crit_stream` — local, never on the wire, null on a rebuilt
`AttackRecord`, which lands its recorded crits); `docs/domain/attack-timeline.md`.
Guards: `test_marker_arrows.gd`, `test_crit_at_landing.gd`, `test_splash_effect.gd`.

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
| `ArrowTip` | `shape` POINTED / BLUNT / CLUB, `length`, `width`, `tier`, `fade_to_shaft` (colour runs out toward the shaft), `pulse_hz` + `pulse_depth` (a beating head) | every look; blunt: armor break, blindness; club: corruption, weakness; pulse: corruption, greed, hex; fade: poison, wither |
| `ArrowShedEmitter` | (emitter knobs) + `density` (share of `amount` emitted; keeps a 20-arrow volley readable), `world_space` | the base trail; a second one: poison's froth |
| `ArrowImpactEmitter` | (emitter knobs) + `spread` TIP / RIM / RIDERS (every non-dud rider's target), `rim_spots`, `per_spot`, `delay` (hold the burst while a mark lingers) | the base burst; rim: wither; riders: blindness's cloud; delay: corruption |
| `ArrowImpactSprite` | `texture`, or with none a `shape` RING / EYE (`lid_ratio`, `pupil_ratio`; the scale curve is the lid opening — a blink); `anchor` TIP / NODE; `lifetime`, `size`, `ring_width`, `scale_curve`, `alpha_curve`, `tier` | corruption's pustule, curse's contracting ring, greed's gilding, weakness's thud, hex's eye |

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
  false` explicitly (armor break, bleeding, corruption, wither, poison's
  froth) — a per-look choice, not a default.
- **Widen a part, don't script a look.** Every look so far is a pure `.tscn`;
  when one needed a behaviour the kit lacked, the part grew an export
  (`ArrowImpactEmitter.delay`, `ArrowImpactSprite.shape`). A new part class
  only for genuine behaviour two looks share.
- **No look has been seen rendered** as of the column's landing (all checked
  headless); `StatusArrow.finished` waits on a timer, not
  `GPUParticles2D.finished`, because a headless run never processes particles.

| arrow | parts it touches |
|---|---|
| armor break | blunt wide tip; spark trail; fragment burst |
| bleeding | sparse drip trail |
| blindness | inert blunt tip; grit trail; smoke cloud burst spread over riders |
| corruption | beating club tip; swelling blip trail; delayed pop burst; pustule sprite |
| curse | inert tip and trail; contracting ring at the node |
| greed | pulsing tip; tumbling coin trail; gilt ring |
| hex | pulsing tip; eye sigil blinking open at the node |
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
| blade effect | `apply_to_blade(state, idx)` | optional — node-local stats are often enough (SpikeRing needs none); `DotAddon` appends its `on_hit_effects` (one `ApplyStatusEffect` per DoT scene; a `SpellOnHitEffect` is refused) to its own vertex's rider list, so two DoT addons on one carrier both apply |
| looks | a `Visual` child on the `AddonVisual` base (#1212) and/or `get_emblem()`; `icon`, `tint`, `description` for the tooltip | an addon with no visual child is invisible outside its tooltip |
| budget | `temp_placeable`, `temp_cost_blade_size` (≥ 1), `temp_cost_aspects` (`{&"<concept>_aspect": n}`, each > 0) | every currency is a pooled per-swing budget capped by the attacker's live stat; landed, guarded by `test_temp_upgrade_budget.gd` |
| procgen | an entry in each content pool's `AddonPolicy` (`procgen/modules/*/content.tres`), `weight`, `unique` | optional, lower priority |
| customization | anything the contract lacks | a new hook, extra hitscans, perf work — named in the cell so it becomes its own unit |

Guards: `test_addons_are_scenes.gd`, `test_addon_kind.gd`,
`test_addon_defs_folder.gd`, `test_dot_addon.gd`, `test_melee_temp_upgrade.gd`.

## Spells (magic column, today)

One `SpellDef` per spell, `attack/spell/defs/<id>.tres`, plus a `const` and
an `ALL` entry in `attack/spell/spell_catalog.gd`
(`test_spell_catalog.gd` fails on a def missing from the catalog).
A spell is many facets, each its own design call:

| facet | fields |
|---|---|
| identity | `id`, `name`, `tagline`, `description`, `icon` |
| cast gate | `min_degree`, `carve_shape` |
| reach | `targeting` (a `Targeting` with a range finder), `propagation` (`PropagationConfig` + filter) |
| payload | `power`, `on_hit_effects` (`DamageEffect`, `HealEffect` …; the one on-hit vocabulary for every mode, see `docs/domain/effect-system.md` and ADR 0044) |
| status | `affinities` (`SpellAffinity{status, innate, rate}`) + `default_rate` — never an `ApplyStatusEffect` in `on_hit_effects` (§ Infusion, ADR 0047) |
| crit | `crit_conditions` (`LandingCondition`s) |
| presentation | `vfx_coordinator_scene`, `windup_vfx_scene`, `tempo` (`.claude/rules/spell-vfx.md`) |

The concept's spell lists a `SpellAffinity` for its def (§ Infusion); the design work
is what else the spell does, so it is not "damage plus status" again.

## Infusion (magic column — ADR 0047, #1250)

A spell's status is its **affinity**, not an authored rider:

- `attack/spell/spell_affinity.gd`: `SpellAffinity{status, innate, rate}`. Its `get_description` gives the tooltip's on-arrival line.
- `attack/spell/spell_def.gd`: `affinities: Array[SpellAffinity]` and `default_rate` (for concepts the list leaves out; 0 refuses them).
- `attack/spell/spell_def.gd`: `infusion_capacity` (most points one cast of this spell takes; `INF` = the pool alone caps).
- `attack/spell/infusion.gd`: `Infusion.innate(spell)` / `for_cast(spell, points)`, `points` (concept id → points), `rate_of`, `affinity_of` = innate + ⌊points × rate⌋, `riders`. Riders are one `ApplyStatusEffect` per concept with affinity above 0; a concept the spell does not list finds its status through `effects/status_roster.gd` (`StatusRoster.by_concept`). `AspectRoster` ranks above `attack`, so it can't serve that lookup. A new `effects/status/*.tres` joins `effects/status_roster.tres` (`test_status_roster.gd` pins it).
- `attack/aspect_currency.gd`: `AspectCurrency.cap_of(attacker, stat_id)`, the one floored board read behind melee's `currency_cap` and magic's caps; `stat_of(concept)` = `<concept>_aspect`.
- `attack/plan/magic_attack_plan.gd`: `infusion` (never null; innate after `set_spell`), `set_infusion(id, points)`, `aspect_overrun()` (per-aspect stat + `infusion_slots` + `min(infusion_points, infusion_capacity)` + refused points), the `"infusion"` wire key (only when points are spent; `from_dict` ungated, ADR 0035), and the preview and launch resolves both carry it.
- `stats_system/defs/infusion_slots.tres` / `infusion_points.tres`: derived on `entity/default_entity_board.tres` from INT. Slots: a threshold ladder at 100 / 1000 / 10000. Points: ⌊√INT⌋.
- `attack/spell/spell_resolver.gd`: `resolve_against(…, infusion = null)` runs the riders after `on_hit_effects` at every landing.

A status cell's spell lists one `SpellAffinity` for the concept's
`StatusDef`. It never authors an `ApplyStatusEffect` in `on_hit_effects`.
`test_aspect_roster.gd` pins this. `test_infusion.gd` pins the cast-time
arithmetic and the overrun.
