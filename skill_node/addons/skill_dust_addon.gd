@tool
class_name SkillDustAddon
extends SkillNodeAddon

## "SkillDust" — the loot a dying entity leaves on its former core node (#69).
## Carries a snapshot of stat modifiers drawn from the dead entity (core-class
## identity + a random sample of its node-granted mods — see [LootSystem]). On
## death the carrier core is neutralised (force-dealloc'd to unowned), so the
## dust sits on a claimable relic.
##
## When ANY entity allocates that relic node, the dust pours its loot onto the
## ALLOCATOR'S CORE — STEAL semantics (permanent, portable core modifiers), not
## onto the relic node itself. The loot is a pick-N-from-M choice over the dead
## entity's CORE modifiers (#173) — the only mods lost when it dies; its owned
## nodes merely return to the graph, so looting those would duplicate live mods.
## The player picks via the HUD loot picker; NPCs auto-pick at random.
## STEAL/PROLIFERATE choice and staining stay deferred (see loot-system.md).
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

## The M core-mod candidates offered as a pick-N-from-M choice (#173) — the dead
## entity's class identity + core-accreted mods, the only ones lost on its death.
## The human player picks `pick_count` of these via the HUD's loot picker; NPCs /
## headless get a random auto-pick. Already `duplicate(true)`d by LootSystem
## (independent copies — formula-mod binding-state safety, see the stats rule).
@export var candidates: Array[StatModifier] = []

## N — how many of `candidates` the collector keeps. When
## `candidates.size() <= pick_count` there's no real choice, so the whole set is
## auto-granted without ever popping the picker.
@export var pick_count: int = 0

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
	return candidates


## Pickup == the carrier gaining an owner. Routes the core-mod candidates through
## the pick-N-from-M handshake (#173):
##   * no real choice (empty, pick_count ≤ 0, or supply ≤ pick_count) →
##     auto-grant everything and free — the picker never pops for a non-choice.
##   * otherwise emit a [LootPickRequest]. A UI consumer sets `handled = true`
##     SYNCHRONOUSLY to take over (player); if nobody does, auto-resolve a random
##     pick right here (NPC / headless). Either way the resolver grants + frees.
## The addon only frees once resolved — which for the player picker can be
## seconds later (it stays on the now-owned relic until then).
func _on_carrier_owner_changed() -> void:
	if Engine.is_editor_hint() or carrier == null:
		return
	var collector := carrier.owned_by
	if collector == null:
		return  # death-strip / deallocation — not a pickup

	if candidates.is_empty() or pick_count <= 0 or candidates.size() <= pick_count:
		_grant_mods(collector, candidates)
		candidates = []
		queue_free()
		return

	var request := LootPickRequest.new(
			collector, candidates, pick_count, _on_pick_resolved)
	Events.loot_pick_requested.emit(request)
	if not request.handled:
		# NPC / headless / no-HUD path — the DEFAULT branch. Random N of M.
		var pool := candidates.duplicate()
		pool.shuffle()
		request.resolve(pool.slice(0, pick_count))


func _on_pick_resolved(chosen: Array[StatModifier]) -> void:
	# Fires possibly seconds later (player took time) — re-validate the collector.
	if carrier != null and is_instance_valid(carrier.owned_by):
		_grant_mods(carrier.owned_by, chosen)
	candidates = []
	queue_free()


## Pour `mods` onto the collector's core node: each becomes a permanent core
## modifier — appended to the core node's `modifiers` array AND pushed live onto
## the board, mirroring how an allocated node grants modifiers, but targeting
## the collector's CORE rather than this relic node.
func _grant_mods(collector: Entity, mods: Array[StatModifier]) -> void:
	var core := collector.core_location
	if core == null:
		return
	var board := collector.stat_board
	for m in mods:
		# A composite is stored WHOLE on the core (stays a lootable unit if this
		# collector later dies) but flattens onto the board via add_modifier.
		core.modifiers.append(m)
		if board != null:
			board.add_modifier(m)
		# #70: emit per LEAF — honest about each stat gained. A bundle's buff and
		# debuff are separate floaters; either alone may be no "mythic" at all.
		for leaf in m.flatten():
			Events.stat_modifier_changed.emit(collector, leaf, ModifierBinding.Kind.CORE, true)


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
