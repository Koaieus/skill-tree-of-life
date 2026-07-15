@tool
class_name LootSystem
extends Node

## Authority for killing-blow rewards (#68 XP, #69/#173 SkillDust loot). Reacts to
## `Events.entity_dying(victim)` — the PRE-cleanup phase, while the corpse still
## owns its nodes (so the XP empire term can count the territory held at death).
## The phase split guarantees this runs before AllocationSystem's `entity_died`
## strip; no tree-order / connection-order dependency. On the bus:
##   * XP reward — the killer gains XP for the victim's level PLUS its territory
##     size at death (the empire term), fed through the normal `xp` pool so it
##     converts to SP / levels via the existing replenished cascade
##     (Entity._on_xp_replenished). Don't bypass the pool — a raw `set_current`
##     would skip the level-up.
##   * SkillDust drop — the victim's CORE modifiers (the only ones lost on death)
##     are attached to its former core node as a [SkillDustAddon], a pick-N-from-M
##     relic. Node mods are NOT looted — they return to the graph. See
##     docs/domain/loot-system.md.
##
## KILLER ATTRIBUTION lives here, not on the entity or the bus: death fires
## SYNCHRONOUSLY inside the attacker's turn (core-HP overflow + cascade chip
## damage both run in the attacker's `launch_attack` call stack), so
## `turn_manager.current_entity` at death IS the killer. Resolving it in the
## rewards authority keeps Entity dumb and keeps reward logic out of BattleSystem
## (which owns attacks, not rewards). Thorns / counter-damage would kill on the
## defender's turn — when those land this needs real source-threading.

## Injected so this system can attribute the killing blow. DI per the
## scene-composition rule (NodePath @export, wired in game_root.tscn) — the same
## pattern BattleSystem / AllocationSystem use for their TurnManager dependency.
@export var turn_manager: TurnManager

## Per-side-effect kill-switches. A sandbox tab (a GameRoot-inherited scene) flips
## these in the inspector to neuter a reward path while keeping 1:1 wiring with
## the real system — ONE declarative guard at the data boundary, not guards
## littered through call sites, and no mock subclass needed for simple on/off.
## (For wholesale behaviour replacement, override the node's `script` to a
## `DevLootSystem extends LootSystem` in the inherited scene instead — same
## NodePaths, swapped logic. See docs/domain/sandbox-framework.md.)
@export var award_xp_on_kill: bool = true
@export var drop_skill_dust_on_death: bool = true

## ── XP reward (#68, extended #173) ────────────────────────────────────────────
## Two components, summed onto the killer's xp pool:
##   base   = xp_per_victim_level * victim.level        (killing the core itself)
##   empire = xp_per_held_node * held_count ^ held_node_xp_power
##                                                      (its territory at death)
## The EMPIRE term is where "you slew a sprawling lv20 giant" is rewarded —
## deliberately as XP, NOT as looted stats. Territory modifiers are only LENT by
## the graph (granted on allocation, released back to neutral on death), so
## copying them into loot would duplicate mods that are still on the battlefield
## and re-claimable. XP is the honest reward for the scale of the kill; the stat
## loot draws strictly from the core (see `_draw_payload`). See #173 discussion.

## XP awarded per level of the victim. Tuning knob — design says "XP proportional
## to the dead entity's level"; this is the slope.
@export var xp_per_victim_level: float = 5.0

## XP per node the victim still held at death — the territory-scale reward. A
## snipe-the-core kill (many nodes still held) and a whittle-the-limbs kill
## should land near the same total; this term rewards the held-at-death count.
## (The complementary per-node-kill trickle for the whittling path is #182.)
@export var xp_per_held_node: float = 1.0
## Exponent on held-count for the empire term. 1.0 = linear; >1 super-linear
## (e.g. 1.5 makes big empires disproportionately juicy). Tuning knob.
@export var held_node_xp_power: float = 1.0

## ── Core loot draw (#173) ─────────────────────────────────────────────────────
## The SkillDust draw is CORE-ONLY: the victim's class-identity mods plus
## whatever was permanently accreted onto its core (previously-looted mods).
## These are the modifiers that VANISH with the entity — everything on its owned
## nodes merely returns to the graph, so drawing those would duplicate live mods.
## The whole core set is offered as pick-N-from-M candidates (M = core supply);
## N (keep-count) scales with victim level, so a higher-level kill lets you keep
## more of their identity. When N >= M there's no real choice → auto-grant all.
##
##   N = round(core_keep_base + core_keep_per_level * victim.level), clamp [0, M]

## Flat baseline keep-count — how much of the core you keep off a level-1 kill.
@export var core_keep_base: float = 1.0
## Keep-count slope on victim level. Small: at 0.25 you keep +1 per 4 levels, so
## you only walk away with a whole core from a much higher-level victim. Knob.
@export var core_keep_per_level: float = 0.25

## Optional packed scene for the dust addon (inspector-set). Falls back to a bare
## `SkillDustAddon.new()` when unset — the addon's visual is script-driven, so the
## fallback still renders.
@export var skill_dust_scene: PackedScene = null


func _ready() -> void:
	Events.entity_dying.connect(_on_entity_dying)


## Pre-cleanup phase — corpse still owns its nodes (see Events.entity_dying).
func _on_entity_dying(victim: Entity) -> void:
	if victim == null:
		return
	var killer := _resolve_killer(victim)
	_award_kill_xp(victim, killer)
	_drop_skill_dust(victim)
	# Still the pre-strip world: the corpse owns its nodes, so an effect can
	# inspect the territory it just took (the Predator's BLITZ will want this).
	if killer != null:
		killer.dispatch(&"_on_killing_blow", [victim])


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
	if not award_xp_on_kill:
		return
	if killer == null or killer.is_dead:
		return
	var board := killer.stat_board
	if board == null or board.xp == null:
		return
	var amount := xp_per_victim_level * float(maxi(1, victim.level))
	var held := _held_node_count(victim)
	if held > 0 and xp_per_held_node > 0.0:
		# Empire term: territory scale rewarded as XP, not as looted stats.
		amount += xp_per_held_node * pow(float(held), maxf(0.0, held_node_xp_power))
	if amount > 0.0:
		board.xp.replenish(amount)  # routes through on_pool_filled → level-up


# ── #69/#173: SkillDust loot drop (core-only) ─────────────────────────────────

func _drop_skill_dust(victim: Entity) -> void:
	if not drop_skill_dust_on_death:
		return
	var core := victim.core_location
	if core == null:
		return
	var draw := _draw_payload(victim)
	var candidates: Array[StatModifier] = draw["candidates"]
	if candidates.is_empty():
		return
	var dust: SkillDustAddon = null
	if skill_dust_scene != null:
		dust = skill_dust_scene.instantiate() as SkillDustAddon
	if dust == null:
		dust = SkillDustAddon.new()
	dust.candidates = candidates
	dust.pick_count = draw["pick_count"]
	dust.victim_color = victim.color
	_attach_addon(core, dust)


## Build the CORE-ONLY loot draw. The candidate pool is the victim's whole core
## modifier set (class identity + core-accreted mods) — the only modifiers that
## are permanently lost when the entity dies. Offered as pick-N-from-M: M = the
## full core supply, N (keep-count) scales with victim level. When N >= M the
## picker won't pop (no real choice) and the addon auto-grants all. Every entry
## is `duplicate(true)`d so the dust owns independent copies.
## Returns { "candidates": Array[StatModifier], "pick_count": int }.
func _draw_payload(victim: Entity) -> Dictionary:
	var core_mods := _core_modifiers(victim)
	var supply := core_mods.size()
	var keep := core_keep_base + core_keep_per_level * float(maxi(0, victim.level))
	var pick_count := clampi(roundi(keep), 0, supply)

	core_mods.shuffle()
	var candidates: Array[StatModifier] = []
	for m in core_mods:
		candidates.append(m.duplicate(true))
	return {"candidates": candidates, "pick_count": pick_count}


## Count of non-core nodes the victim still owns at death — the TERRITORY signal,
## now feeding the XP empire term (was the loot draw pre-#173-rework). Reads the
## owned-subgraph mirror, so cascade-stripped nodes are already excluded.
func _held_node_count(victim: Entity) -> int:
	if victim.navigator == null:
		return 0
	var core := victim.core_location
	var count := 0
	for n in victim.navigator.get_mirrored_nodes():
		if n != null and n != core:
			count += 1
	return count


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


func _attach_addon(node: SkillNode, addon: SkillNodeAddon) -> void:
	var anchor := node.get_node_or_null("Visuals/AddonAnchor")
	if anchor != null:
		anchor.add_child(addon)
	else:
		node.add_child(addon)  # headless fallback (no Visuals subtree)
