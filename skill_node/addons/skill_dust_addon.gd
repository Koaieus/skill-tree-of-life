@tool
class_name SkillDustAddon
extends SkillNodeAddon

## "SkillDust" — the loot a dying entity leaves on its former core node (#69).
## Carries a snapshot of stat modifiers drawn from the dead entity (core-class
## identity + a random sample of its node-granted mods — see [LootSystem]). On
## death the carrier core is neutralised (force-dealloc'd to unowned), so the
## dust sits on a claimable relic.
##
## When ANY entity allocates that relic node, the dust consumes itself and pours
## its payload onto the ALLOCATOR'S CORE — STEAL semantics (permanent, portable
## core modifiers), not onto the relic node itself. This is the MVP slice of the
## design doc's Loot Resolution; STEAL/PROLIFERATE choice, staining, and the
## picker UI are deferred (see docs/domain/loot-system.md).

## The drawn modifiers, already `duplicate(true)`d by LootSystem (independent
## copies — formula-mod binding-state safety, see the stats-system rule).
@export var payload: Array[StatModifier] = []

const _DUST_COLOR := Color(0.95, 0.85, 0.35, 0.9)
var _radius: float = 32.0


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
		# Pickup == the carrier gaining an owner. owner_changed ALSO fires on the
		# death-strip (victim → null); _on_carrier_owner_changed guards that case.
		if not carrier.owner_changed.is_connected(_on_carrier_owner_changed):
			carrier.owner_changed.connect(_on_carrier_owner_changed)
	queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	queue_redraw()


# ─── Tooltip contract (SkillNodeAddon) ─────────────────────────────────────

func get_tooltip_title() -> String:
	return "SkillDust loot"


func get_tooltip_modifiers() -> Array[StatModifier]:
	return payload


func _on_carrier_owner_changed() -> void:
	if Engine.is_editor_hint() or carrier == null:
		return
	var collector := carrier.owned_by
	if collector == null:
		return  # death-strip / deallocation — not a pickup
	_grant_to(collector)
	queue_free()


## Pour the payload onto the collector's core node: each modifier becomes a
## permanent core modifier — appended to the core node's `modifiers` array AND
## pushed live onto the board, mirroring how an allocated node grants modifiers,
## but targeting the collector's CORE rather than this relic node.
func _grant_to(collector: Entity) -> void:
	var core := collector.core_location
	if core == null:
		return
	var board := collector.stat_board
	for m in payload:
		core.modifiers.append(m)
		if board != null:
			board.add_modifier(m)
	payload.clear()


func _draw() -> void:
	# Minimal sparkle: a ring of small dust dots so a relic node reads as lootable.
	if _radius <= 0.0:
		return
	var count := 8
	var step := TAU / float(count)
	for i in count:
		var theta := i * step + float(i % 2) * step * 0.5
		var dist := _radius * (0.55 + 0.12 * float(i % 3))
		var p := Vector2.from_angle(theta) * dist
		draw_circle(p, _radius * 0.06, _DUST_COLOR)
