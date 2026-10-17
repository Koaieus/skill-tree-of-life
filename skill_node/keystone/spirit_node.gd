@tool
class_name SpiritNode
extends SkillNode

## An aspect spirit: a neutral landmark carrying a one-round [SkillDustAddon]
## whose only offer is +1 `<aspect>_aspect`. The first entity to allocate it
## absorbs the grant into its core register; the relic then frees itself.
## The node owns which aspect and the tint; the addon owns the offer and the
## claim; procgen owns where. See docs/domain/spirits.md.
##
## The aspect is a pure function of the node's position, so a peer that
## rebuilds the node from a [GraphSnapshot] (scene by path, position by value)
## rolls the same one with nothing extra on the wire.

## The roll pool. Tentative: the 12 aspect identities.
@export var aspects: Array[Identity] = []
## Authored aspect; null = roll from [member aspects] by position.
@export var fixed_aspect: Identity = null
## Mystery variant: the relic shows [member mystery_color] and hides its offer
## until claimed.
@export var reveal_on_claim: bool = false
## The mystery look. Tentative.
@export var mystery_color: Color = Color(0.55, 0.55, 0.58, 1.0)
## How many of the aspect the offer grants. Tentative.
@export var aspect_count: float = 1.0

## The aspect this spirit offers — derived, never serialized.
var aspect: Identity:
	get:
		return fixed_aspect if fixed_aspect != null else _roll()


func _ready() -> void:
	super()
	configure()


## Fill the relic's offer and look from [member aspect]. Idempotent.
func configure() -> void:
	if Engine.is_editor_hint():
		return  # a derived offer must never serialize into the scene
	var dust := get_dust()
	var a := aspect
	if dust == null or a == null:
		return
	var m := StatModifier.new()
	m.stat_id = StringName(String(a.id) + "_aspect")
	m.operation = StatModifier.Operation.ADD_BASE
	m.value = aspect_count
	var cands: Array[StatModifier] = [m]
	dust.candidates = cands
	var w: Array[float] = [1.0]
	dust.weights = w
	dust.rounds = 1
	dust.victim_tint_mix = 0.0
	dust.conceal_offer = reveal_on_claim
	dust.gold_color = mystery_color if reveal_on_claim else a.tint


## The relic child, or null once it has been claimed and freed.
func get_dust() -> SkillDustAddon:
	for addon in get_addons():
		if addon is SkillDustAddon and not addon.is_queued_for_deletion():
			return addon
	return null


## Position-seeded pick: whole pixels, so a float round-trip cannot shift it.
func _roll() -> Identity:
	if aspects.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(position.x), roundi(position.y)))
	return aspects[rng.randi_range(0, aspects.size() - 1)]
