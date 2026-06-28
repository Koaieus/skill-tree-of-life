class_name LootSystem
extends Node

## Authority for killing-blow rewards (#68 XP, #69 SkillDust loot). Reacts to
## `Events.entity_died(victim)`:
##   * XP reward — the killer gains XP scaled by the victim's level, fed through
##     the normal `xp` pool so it converts to SP / levels via the existing
##     replenished cascade (Entity._on_xp_replenished). Don't bypass the pool —
##     a raw `set_current` would skip the level-up.
##   * SkillDust drop — a snapshot of the victim's modifiers is attached to its
##     former core node as a [SkillDustAddon], turning the neutralised core into
##     a claimable relic. See docs/domain/loot-system.md.
##
## KILLER ATTRIBUTION lives here, not on the entity or the bus: death fires
## SYNCHRONOUSLY inside the attacker's turn (core-HP overflow + cascade chip
## damage both run in the attacker's `launch_attack` call stack), so
## `turn_manager.current_entity` at `entity_died` IS the killer. Resolving it in
## the rewards authority keeps Entity dumb and keeps reward logic out of
## BattleSystem (which owns attacks, not rewards). Thorns / counter-damage would
## kill on the defender's turn — when those land this needs real source-threading.
##
## ORDERING (load-bearing): this must run BEFORE AllocationSystem's death handler
## strips the corpse's nodes — the node-granted-modifier snapshot reads the
## victim's still-owned subgraph. Guaranteed by tree order: LootSystem is the
## FIRST child of `Systems`, so its `_ready` connects to the bus first and the
## bus serves handlers in connection order. (The XP grant and the dust attach are
## themselves order-independent — the addon survives the strip, the core mods come
## off the resource — only set X needs the pre-strip read.)

## Injected so this system can attribute the killing blow. DI per the
## scene-composition rule (NodePath @export, wired in game_root.tscn) — the same
## pattern BattleSystem / AllocationSystem use for their TurnManager dependency.
@export var turn_manager: TurnManager

## XP awarded per level of the victim. Tuning knob — design says "XP proportional
## to the dead entity's level"; this is the slope.
@export var xp_per_victim_level: float = 5.0

## Cap on how many modifiers the drop pulls from the victim's CORE (class
## identity). The remainder of the `level`-sized draw is filled from the victim's
## node-granted mods. Lower = more varied loot (you don't always get the full
## core dump). Tuning knob.
@export var max_core_picks: int = 2

## Optional packed scene for the dust addon (inspector-set). Falls back to a bare
## `SkillDustAddon.new()` when unset — the addon's visual is script-driven, so the
## fallback still renders.
@export var skill_dust_scene: PackedScene = null


func _ready() -> void:
	Events.entity_died.connect(_on_entity_died)


func _on_entity_died(victim: Entity) -> void:
	if victim == null:
		return
	_award_kill_xp(victim, _resolve_killer(victim))
	_drop_skill_dust(victim)  # MUST precede AllocationSystem's node strip


## The entity holding the turn at the synchronous death is the killer. Guarded
## against the victim itself (non-attack death — self-islanding, scripted) and a
## missing TurnManager (headless tests without one).
func _resolve_killer(victim: Entity) -> Entity:
	if turn_manager == null:
		return null
	var killer := turn_manager.current_entity
	return killer if killer != victim else null


# ── #68: XP reward ───────────────────────────────────────────────────────────

func _award_kill_xp(victim: Entity, killer: Entity) -> void:
	if killer == null or killer.is_dead:
		return
	var board := killer.stat_board
	if board == null or board.xp == null:
		return
	var amount := xp_per_victim_level * float(maxi(1, victim.level))
	if amount > 0.0:
		board.xp.replenish(amount)  # routes through on_pool_filled → level-up


# ── #69: SkillDust loot drop ─────────────────────────────────────────────────

func _drop_skill_dust(victim: Entity) -> void:
	var core := victim.core_location
	if core == null:
		return
	var payload := _draw_payload(victim)
	if payload.is_empty():
		return
	var dust: SkillDustAddon = null
	if skill_dust_scene != null:
		dust = skill_dust_scene.instantiate() as SkillDustAddon
	if dust == null:
		dust = SkillDustAddon.new()
	dust.payload = payload
	_attach_addon(core, dust)


## Build the loot payload — total size = victim level. Core-class identity mods
## first (shuffled, capped at `max_core_picks`), then random node-granted mods
## (a copy of what its still-owned non-core nodes offer) to fill the rest. Every
## entry is `duplicate(true)`d so the dust owns independent copies.
func _draw_payload(victim: Entity) -> Array[StatModifier]:
	var total := maxi(0, victim.level)
	var payload: Array[StatModifier] = []
	if total == 0:
		return payload

	var core_mods := _core_modifiers(victim)
	core_mods.shuffle()
	var core_take := mini(mini(max_core_picks, core_mods.size()), total)
	for i in core_take:
		payload.append(core_mods[i].duplicate(true))

	var node_mods := _node_modifiers(victim)
	node_mods.shuffle()
	for m in node_mods:
		if payload.size() >= total:
			break
		payload.append(m.duplicate(true))
	return payload


## Core source: class identity mods (+10 STR/DEX/INT for BalancedCore, etc.) plus
## anything sitting on the core node itself (e.g. previously looted mods — the
## relic loop closes).
func _core_modifiers(victim: Entity) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if victim.core_class != null:
		out.append_array(victim.core_class.modifiers)
	if victim.core_location != null:
		out.append_array(victim.core_location.modifiers)
	return out


## Node-granted source (the design doc's "set X"): the modifiers offered by every
## non-core node the victim still owns. Reads the owned-subgraph mirror, so nodes
## already force-dealloc'd by the finishing-blow cascade are naturally excluded —
## they left the mirror when they were stripped.
func _node_modifiers(victim: Entity) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if victim.navigator == null:
		return out
	var core := victim.core_location
	for n in victim.navigator.get_mirrored_nodes():
		if n != null and n != core:
			out.append_array(n.modifiers)
	return out


func _attach_addon(node: SkillNode, addon: SkillNodeAddon) -> void:
	var anchor := node.get_node_or_null("Visuals/AddonAnchor")
	if anchor != null:
		anchor.add_child(addon)
	else:
		node.add_child(addon)  # headless fallback (no Visuals subtree)
