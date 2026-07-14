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
##
## Visual (#168): scene-composed (skill_dust_addon.tscn) with a child InnerDisk
## instance, per .claude/rules/scene-composition.md — the gold/mix knobs below
## are only actually inspector-tunable because they live on a scene, not a
## script that's always bare `.new()`'d. InnerDisk's `show_diamond` (see
## inner_disk.gd) etches the loot gem cut; this script forces `allocated =
## true` on it — the "hijack the allocation-state render" option from #168,
## scoped to this addon's OWN disk instance so nothing needs to be faked on
## the carrier SkillNode/AllocationSystem. LootSystem falls back to
## `SkillDustAddon.new()` when no scene is configured (see
## `skill_dust_scene` on LootSystem) — that bare fallback has no InnerDisk
## child, so it's intentionally visual-lite (sparkles only), not a bug.

## The drawn modifiers, already `duplicate(true)`d by LootSystem (independent
## copies — formula-mod binding-state safety, see the stats-system rule).
@export var payload: Array[StatModifier] = []

## The dying entity's color, injected by LootSystem before this addon enters
## the tree (same timing as `payload`) — mixed into the gold tint below so a
## relic visibly carries whose corpse it came from.
@export var victim_color: Color = Color.WHITE:
	set(value):
		victim_color = value
		_sync_gold_tint()

## Base loot color and how much of `victim_color` tinges it — both exported so
## a scene author can dial the look without touching script (#168).
@export var gold_color: Color = Color(0.95, 0.78, 0.25, 1.0):
	set(value):
		gold_color = value
		_sync_gold_tint()
@export_range(0.0, 1.0, 0.01) var victim_tint_mix: float = 0.3:
	set(value):
		victim_tint_mix = value
		_sync_gold_tint()

const _SPARKLE_COLOR := Color(1.0, 0.95, 0.75, 1.0)
const _SPARKLE_COUNT := 10

## Null when this addon was `.new()`'d directly instead of instanced from
## skill_dust_addon.tscn (LootSystem's headless/no-scene fallback) — every
## use below is null-guarded, so that path just skips the gold diamond disk
## and keeps the sparkle-only look.
## Deliberately untyped: statically typing this as Node2D would make GDScript
## complain about the InnerDisk-specific properties set below (disk_radius,
## show_diamond, entity_tint, ...) — node_visuals_composite.gd sidesteps the
## same issue by reading its InnerDisk child through the `%InnerDisk` unique-
## name accessor, which Godot resolves to the attached script's type; a plain
## get_node_or_null() return is statically just Node, so this stays Variant.
@onready var _inner_disk = get_node_or_null("InnerDisk")

var _radius: float = 32.0
var _t: float = 0.0


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
		# Pickup == the carrier gaining an owner. owner_changed ALSO fires on the
		# death-strip (victim → null); _on_carrier_owner_changed guards that case.
		if not carrier.owner_changed.is_connected(_on_carrier_owner_changed):
			carrier.owner_changed.connect(_on_carrier_owner_changed)
	if _inner_disk != null:
		_inner_disk.show_diamond = true
		_inner_disk.allocated = true
		_inner_disk.configure(_radius)
	_sync_gold_tint()
	set_process(not Engine.is_editor_hint())
	queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	if _inner_disk != null:
		_inner_disk.configure(r)
	queue_redraw()


func _sync_gold_tint() -> void:
	if _inner_disk == null:
		return
	_inner_disk.entity_tint = gold_color.lerp(victim_color, victim_tint_mix)


func _process(delta: float) -> void:
	_t += delta
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
		# #70: core-held modifier looted — the build-defining "mythic" floater.
		Events.stat_modifier_changed.emit(collector, m, ModifierBinding.Kind.CORE, true)
	payload.clear()


## Shimmering sparkle ring (#168) — richer than the old static 8-dot draw:
## each dot twinkles on its own phase offset so the ring reads as animated
## glimmer rather than fixed decoration. Addon-owned rather than a
## SkillNodeVisual family member — this FX is relic-specific, not a reusable
## node-visual component.
func _draw() -> void:
	if _radius <= 0.0:
		return
	var step := TAU / float(_SPARKLE_COUNT)
	for i in _SPARKLE_COUNT:
		var theta := i * step + float(i % 2) * step * 0.5
		var dist := _radius * (0.55 + 0.12 * float(i % 3))
		var p := Vector2.from_angle(theta) * dist
		var phase := _t * 1.6 + float(i) * 1.7
		var twinkle := 0.5 + 0.5 * sin(phase)
		var c := _SPARKLE_COLOR
		c.a = _SPARKLE_COLOR.a * (0.35 + 0.65 * twinkle)
		draw_circle(p, _radius * (0.035 + 0.04 * twinkle), c)
