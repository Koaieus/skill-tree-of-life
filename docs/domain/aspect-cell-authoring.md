# Authoring an aspect cell — what each column of the matrix actually touches

The design table is `docs/design/aspect_matrix.md`; this is the *what is*:
for each column, the files a cell lands on, the fields that carry its
identity, the registry that makes it exist, and the test that notices when
it is missing. A **full row** is simply every cell for one concept; a
**column pass** is one cell for every concept. The same list either way.

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
scan does not survive export). No code: `Entity.reload_yield`, the ranged
tray's ammo cards and `AIController._compose_volley` iterate the roster.

| facet | field | note |
|---|---|---|
| stats | `order` | volley position; specials sit below the base arrow's 100, scout last |
| | `damage_scale` | raw-damage multiplier before mitigation |
| | `status_power` | stacks per landing arrow, before potency × (1 − resistance) |
| | `max_stock` | the type's own bank cap, outside the shared quiver capacity (ADR 0041) |
| | `per_reload_stat_id` | `<concept>_aspect` |
| effect | `status_def` | the concept's `effects/status/<concept>.tres`; a reveal type uses `reveal_fraction` / `reveal_stack_bonus` instead and never both |
| looks | — | **none per type today**: nothing in flight reads the `AmmoType`; the card text comes from `AmmoCard.effect_line`. A per-type look is an open fork (an `AmmoType` tint vs the volley coordinator reading `status_def.tint`) |

Guards: `test/unit/attack/test_ammo_type_roster.gd` (roster vs disk, ids,
distinct mint stats, order invariants) and `test_reload_command.gd`.

## Addon (map and temp are one scene)

One `SkillNodeAddon` scene, `skill_node/addons/defs/<name>_addon.tscn`.
The scene *is* the addon (`docs/domain/scene-composition.md`); a subclass
only when a hook needs code. Lead-by example: `spike_ring_addon.tscn`.

| facet | where | note |
|---|---|---|
| modifiers | `entity_modifiers`, `local_modifiers` | authored arrays; a subclass may synthesise stake-scaled ones via `get_local_modifiers()` / `get_entity_modifiers()`. On a blade, entity modifiers apply for the swing except currency (`aspects` family, `blade_size`) |
| blade effect | `apply_to_blade(state, idx)` | optional — node-local stats are often enough (SpikeRing needs none); `DotAddon` writes the vertex status |
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
| cast gate | `min_degree`, `mana_cost`, `carve_shape` |
| reach | `targeting` (a `Targeting` with a range finder), `propagation` (`PropagationConfig` + filter) |
| payload | `power`, `on_hit_effects` (`DamageEffect`, `HealEffect`, `ApplyStatusEffect(def, power)` …) |
| crit | `crit_conditions` (`LandingCondition`s) |
| presentation | `vfx_coordinator_scene`, `windup_vfx_scene`, `tempo` (`.claude/rules/spell-vfx.md`) |

The concept's spell uses `ApplyStatusEffect` with its def; the design work
is what else the spell does, so it is not "damage plus status" again.

## Infusion (magic column, provisional — #1250)

Nothing concrete beyond the rule: an `X`-infused spell spends `X_aspect`
budget to add or alter spell behaviour or on-hit effects. The leaning is a
fifth `SpellDef` component (an `Infusion` resource: an on-hit effect plus
an optional drawback on another component), scaled by charges, never an
on/off flag. Author nothing here until #1250 lands; then this section
lists its files.
