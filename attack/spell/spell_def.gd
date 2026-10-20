@tool
class_name SpellDef
extends Resource

## Authored spell data — identity, cost, propagation strategy, on-hit effects,
## and the VFX coordinator scene. The "what it does" half is composition:
## pick a [PropagationConfig] (which itself composes [PropagationFilter] /
## [PropagationSpread] / [IncidentReducer]) and an array of [OnHitEffect] for
## what happens per node (damage is the default first entry).

## Stable wire name for this spell — the only legal way to refer to a
## [SpellDef] across a process boundary (#511). A [MagicAttackPlan] serializes
## `spell` as this id and [method SpellCatalog.by_id] resolves it back.
##
## [b]Not `resource_path`[/b] (owner call 2026-08-21). Path keying is taken
## case by case, where the path is the clean key (a scene that [i]is[/i] the
## kind, every peer running the same build: [Participant], [RunConfig],
## [GraphSnapshot], the temp-upgrade addon kind). Nothing about a spell made a
## path the clean key, and an authored id survives a rename or move of the
## `.tres`, which a path key would break silently with no error at the break.
##
## Must be unique across `attack/spell/defs/` — `test_spell_catalog.gd` pins it.
@export var id: StringName = &""

@export var name: String

## Snappy one-liner shown under the header in [SpellTooltip] (#764) — the
## LAN-08 finding was that nobody reads a wall of text mid-turn. Capped at 80
## chars, pinned by `test_spell_tooltip_sections.gd` over
## [constant SpellCatalog.ALL]. [member description] stays the long form,
## reserved for the spell catalogue (#853) and no longer rendered here.
@export var tagline: String = ""

## Long-form flavour text. No longer rendered in [SpellTooltip] (#764) — the
## four derived sections replace it there. Kept for the spell catalogue
## (#853), which shows it as-is.
@export_multiline var description: String
## The spell's display atom (kind SPELL) — its noun, NEUTRAL tint and glyph.
@export var identity: Identity = null
## Spell-card iconography, read through [member identity]. Rendered in the
## spell picker (top, large) and in tooltips. Null (no identity, or an identity
## without a glyph) falls back to a glyph derived from the spell name.
var icon: Texture2D:
	get:
		return identity.icon if identity else null

## The shape a node granting this spell carves into its dome (#315) — a
## SPELL-priority [EmblemSpec], outranking the archetype fallback. Typed as the
## BASE class on purpose: a spell isn't restricted to a baked-icon carve, it may
## just as well want a polygon or the gem cut. Distinct from [member icon],
## which is 2D card art — this is a height-field dent. Null contributes an empty
## dome at spell priority (honest: the spell claims the carve, no shape authored
## yet) rather than letting the archetype shape stand in.
@export var carve_shape: CarveShape = null

## Required degree for [SkillNodes] to have (how many edges they have) before
## this spell may be fired — [b]entity degree[/b], measured over the caster's
## own owned induced subgraph ([method SpellBook._node_meets_source_requirements]
## via [EntityNavigator]), never graph degree.
# 	could also opt for encoding this as an named (int)enum
##
## [b]It is a reach tax as well as a gate, and that is intended.[/b] Since #728
## the cast-from node is derived, so raising this shrinks the eligible-caster
## set — and your frontier nodes are exactly the degree-1 leaves OF YOUR OWN
## territory. So `min_degree = 2` costs a hop of effective reach in the one
## direction that matters: Lightning Bolt and Spark both author 3 hops, but the
## bolt cannot launch from the leaf nearest the enemy and falls back a node.
##
## Owner, 2026-09-04, on that asymmetry:
##
##   "no the min degree = 2 is perfect. it just bit me that i didn't know why it
##   wasn't in range."
##
## So the number stands and the LEGIBILITY was the defect: the eligible casters
## now paint their own highlight ([enum HighlightProvider.HighlightRole.CASTER],
## driven by [method MagicAttackPlan.get_node_role]), which is what makes a
## missing caster ring visible instead of an unexplained refusal. Do not "fix"
## a high `min_degree` by lowering it or by widening `max_hops` to compensate.
@export var min_degree: int = 1

## The spell's power coefficient — [b]the only absolute number a spell
## carries[/b] (D-32). The seed hit is
## [code]spell_damage(cast-from node) × power[/code]: the caster's board stat
## supplies "who is casting", this supplies "which spell". A low-scaling spell
## is [code]power = 0.3[/code]. A spell that should ignore the caster opts out
## with [member scale_by_spell_damage]; one that should ignore power authors
## [code]power = 1.0[/code]. Every hop after the seed is shaped by
## [member PropagationConfig.hop_damage] (a [HopDamageProgression]).
@export var power: float = 0.0

## Whether the seed hit multiplies [member power] by the caster's
## [code]spell_damage[/code]. Off, the seed is [member power] flat — the
## authored fraction of a percent-basis spell (Bruiser chips [code]power[/code]
## of current hp whoever casts it). [method SpellResolver.impact_damage] is the
## only reader.
@export var scale_by_spell_damage: bool = true

## How this spell propagates from the seed target. Composes
## [PropagationFilter] (what neighbours count), [PropagationSpread] (how
## payloads fan), and [IncidentReducer] (what happens when branches
## converge). See [code]docs/domain/spell-propagation.md[/code].
@export var propagation: PropagationConfig = null

## What happens at every node the spell lands on, run in order. Damage is
## the standard first entry via [DamageEffect].
@export var on_hit_effects: Array[OnHitEffect] = []

## The spell's intake list (#1250): per concept, the load it lands per hit
## with no infusion ([member AspectIntake.innate]) and its affinity, the
## per-concept exchange rate for an infusion of it. [Infusion] turns it into one
## [ApplyStatusEffect] rider per concept, run after [member on_hit_effects] at
## every landing — a status spell authors its stacks here, never as an
## [ApplyStatusEffect] in [member on_hit_effects].
@export var intakes: Array[AspectIntake] = []

## The gate every intake rider of a cast carries as its
## [member OnHitEffect.when] — null lands the riders at every landing, a
## condition only where it holds (the spell's own [member on_hit_effects]
## author their gates each).
@export var rider_when: LandingCondition = null

## Ingest rate numerator: the spell-wide exchange rate `ingest_gain:ingest_cost`,
## multiplied with every concept's affinity (an unlisted concept's is 1:1);
## 0 refuses every infusion.
@export_range(0, 10, 1, "or_greater") var ingest_gain: int = 1:
	set(value):
		ingest_gain = maxi(value, 0)
## Ingest rate denominator; ≥ 1.
@export_range(1, 10, 1, "or_greater") var ingest_cost: int = 1:
	set(value):
		ingest_cost = maxi(value, 1)

## Most infusion points one cast of this spell takes in total, across every
## socketed aspect; INF leaves each aspect capped only by its `<concept>_aspect`.
@export var infusion_capacity: float = INF

## Spell-specific crit conditions. Evaluated per landing in addition to
## the universal [code]crit_chance[/code] stat roll. Multiple conditions
## run as OR — if ANY returns true, the hit crits. Follows the same
## composed-resource pattern as [member on_hit_effects].
@export var crit_conditions: Array[LandingCondition] = []

## The visual coordinator scene the battle layer plays once resolution
## produces an outcome. Scene root must be a [VFXCoordinator] subclass.
@export var vfx_coordinator_scene: PackedScene = null

## This spell's presentation SHAPE — beat interval and bolt lead-in (#543 D3a).
## Same composed-resource pattern as [member vfx_coordinator_scene] above, and
## null means [method PresentationTempo.shared_default], so eight spells do not
## mean eight copies of the same two numbers. A spell only authors its own when
## its identity genuinely differs (artillery arc vs. chain of snaps); the
## player-facing RATE is not here, it is
## [member GameSettings.combat_time_scale].
@export var tempo: PresentationTempo = null

## Spell-specific wind-up FX layered ON TOP of the default caster draw (#1043):
## when set, [MagicBounceCoordinator.begin_windup] instances it as a child of
## the coordinator at the caster for the draw span and frees it when the cast's
## playback ends. Null (every spell today) means the default alone — the
## neighbour streaks and the caster flare are not replaced, only joined.
@export var windup_vfx_scene: PackedScene = null

## How this spell's target is gathered + what counts as valid. The kind
## drives input dispatch (NODE click vs. world click); the predicates drive
## valid-target enumeration for highlight + AI.
@export var targeting: Targeting


func validate(_plan: MagicAttackPlan) -> Array[String]:
	var errors: Array[String] = []
	if targeting == null:
		errors.append(&"Spell has no targeting set")
	if propagation == null:
		errors.append(&"Spell has no propagation set")
	# A status-only spell (Hex) lands nothing but its intake riders.
	if on_hit_effects.is_empty() and intakes.is_empty():
		errors.append(&"Spell has no on-hit effects")
	return errors


## True iff some [member intakes] row lands a [ScoutStatus] — the spell
## lights the fog it crosses. Mirrors [method AmmoType.is_scout].
func is_scout() -> bool:
	for intake in intakes:
		if intake != null and intake.status() is ScoutStatus:
			return true
	return false


func _to_string() -> String:
	return "<SpellDef %s>" % name
