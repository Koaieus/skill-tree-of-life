@tool
class_name SpikeRingAddon
extends SkillNodeAddon

## Offensive sharpness: contributes to the carrier's node-local `blade_damage`
## stat via the base class's authored `local_modifiers` array (see the
## addon's .tscn). Both blade-build paths read per-vertex damage via
## SkillNode.get_local_value(&"blade_damage"), which merges this node-local
## modifier with the owner's board — so a swept spiked node deals
## base + spike, and preview matches commit. See docs/design/skill_node_addons.md.
##
## Defensive `spikes` / `spike_regen` pop budget (#778): the ONLY source of
## either stat is this addon — an unspiked node holds `spikes` 0 at any stake
## level (there is no base grant anywhere else). Also raises the carrier's own
## `blunting` from the def's default 1 to 2, since a spiked node's blade
## vertex is itself reinforced.
##
## These three are computed, not authored on `local_modifiers` in the .tscn,
## because two of them scale with `stake_level` — see [method get_local_modifiers].
##
## Defensive side (blade-vs-blade collision, spike-attacks-incoming-blade
## structure) is explicitly out-of-scope per docs/design/skill_node_addons.md
## — collision model is open and "do not implement until specified".

const default_color = Color.WHITE  # Color(0.95, 0.55, 0.4, 0.95)

@export_range(4, 24, 1) var spike_count: int = 12
## Derived, never authored: the spikes take the carrier's owner colour, falling
## back to its archetype colour and then to white. Deliberately NOT `@export` —
## a getter-only export shows an inspector field that discards whatever is typed
## into it, and the editor serializes the *computed* value back into the scene
## (.claude/rules/gdscript-pitfalls.md, "never write a DERIVED value back into an
## @export"). The scene carried exactly such a dead `spike_color` line until it
## was dropped alongside this.
var spike_color: Color:
	get():
		if carrier and carrier.owned_by:
			return carrier.owned_by.color
		if carrier:
			return carrier.base_type_color
		return default_color
## How far out the spike tips reach beyond the carrier's radius.
@export_range(0.0, 1.0, 0.05) var spike_overshoot: float = 0.45
## Spike base width as a fraction of the carrier's radius.
@export_range(0.05, 0.6, 0.05) var spike_base: float = 0.18

var _radius: float = 32.0

## `spikes` cap grant, ADD_BASE with a [LinearFormula] reading the carrier's
## own `stake_level` (the N in the M/N dial, i.e. [member SkillNode.stake_level]
## — a bare token, deliberately not `stake_level__current`: it is the STAKE
## that scales the grant, not the fill). Coefficient 2 — a fully-staked (3)
## spiked node holds spikes cap 6, per the issue's own worked example.
## Built once and cached: [method SkillNodeAddon.get_local_modifiers]'s
## contract requires the SAME instance across calls (SkillNode reclaims by
## identity on remove).
var _spikes_modifier: StatModifier

## `spike_regen` grant, same shape as [member _spikes_modifier] but
## coefficient 1 — a stake-3 node recovers spike_regen 3 per turn.
var _spike_regen_modifier: StatModifier

## `blunting` grant — flat +1 ADD_BASE, no formula: the def's base is 1, this
## addon raises a spiked attacking vertex to 2. Not stake-scaled (#778 —
## "blunting ships with default 1, 2 on a spiked vertex, nothing else").
var _blunting_modifier: StatModifier


## Lazily builds and caches the three synthesized modifiers above. Idempotent
## — subsequent calls are no-ops once [member _spikes_modifier] exists.
func _ensure_synthesized_modifiers() -> void:
	if _spikes_modifier != null:
		return
	var spikes_formula := LinearFormula.new()
	spikes_formula.source_stat_id = &"stake_level"
	spikes_formula.per_phrase = "stake level"
	_spikes_modifier = StatModifier.new()
	_spikes_modifier.stat_id = &"spikes"
	_spikes_modifier.operation = StatModifier.Operation.ADD_BASE
	_spikes_modifier.value = 2.0
	_spikes_modifier.formula = spikes_formula

	var regen_formula := LinearFormula.new()
	regen_formula.source_stat_id = &"stake_level"
	regen_formula.per_phrase = "stake level"
	_spike_regen_modifier = StatModifier.new()
	_spike_regen_modifier.stat_id = &"spike_regen"
	_spike_regen_modifier.operation = StatModifier.Operation.ADD_BASE
	_spike_regen_modifier.value = 1.0
	_spike_regen_modifier.formula = regen_formula

	_blunting_modifier = StatModifier.new()
	_blunting_modifier.stat_id = &"blunting"
	_blunting_modifier.operation = StatModifier.Operation.ADD_BASE
	_blunting_modifier.value = 1.0


## Overrides the base class default (the authored [member local_modifiers]
## array, which still carries the offensive `blade_damage` bonuses from the
## .tscn) to append the three computed grants above.
func get_local_modifiers() -> Array[StatModifier]:
	_ensure_synthesized_modifiers()
	var out := local_modifiers.duplicate()
	out.append(_spikes_modifier)
	out.append(_spike_regen_modifier)
	out.append(_blunting_modifier)
	return out


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
		queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	queue_redraw()


# ─── Tooltip ───────────────────────────────────────────────────────────────

func get_tooltip_title() -> String:
	return "Spikes"


func _draw() -> void:
	if _radius <= 0.0 or spike_count <= 0:
		return
	var base_half := _radius * spike_base * 0.5
	var tip_dist := _radius * (1.0 + spike_overshoot)
	var step := TAU / float(spike_count)
	for i in spike_count:
		var theta := i * step
		var radial := Vector2.from_angle(theta)
		var tangent := Vector2(-radial.y, radial.x)
		var tip := radial * tip_dist
		var b1 := radial * _radius + tangent * base_half
		var b2 := radial * _radius - tangent * base_half
		draw_colored_polygon(PackedVector2Array([tip, b1, b2]), spike_color)
