@tool
class_name LootSystem
extends Node

## Authority for killing-blow rewards (#68 XP, #69/#173 SkillDust loot,
## #204 spellbook draft). Reacts to `Events.entity_dying(victim)` — the
## PRE-cleanup phase, while the corpse still owns its nodes (so the XP payout
## can count the territory held at death, and the spell draft can still
## read core-sourced spells before the strip). The phase split guarantees this
## runs before AllocationSystem's `entity_died` strip; no tree-order /
## connection-order dependency. On the bus:
##   * XP reward — the killer gains XP for the territory the victim held at
##     death (core included), fed through the normal `xp` pool so it converts to
##     SP / levels via the existing replenished cascade
##     (Entity._on_xp_replenished). Don't bypass the pool — a raw `set_current`
##     would skip the level-up. The complementary per-node trickle rides
##     `Events.skill_node_destroyed` instead of this phase.
##   * SkillDust drop — the victim's CORE modifiers (the only ones lost on death)
##     are attached to its former core node as a [SkillDustAddon], a pick-N-from-M
##     relic. Node mods are NOT looted — they return to the graph. See
##     docs/domain/loot-system.md.
##   * Spell draft (#204) — the victim's PERMANENT (core ∪ innate) spells,
##     minus what the killer already knows permanently, offered pick-1-from-M;
##     the chosen spell lands on the killer's core via a [SpellGrant]. See the
##     "#204: Spellbook loot draft" section below.
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
@export var award_xp_on_node_kill: bool = true
@export var drop_skill_dust_on_death: bool = true
@export var award_spell_loot_on_death: bool = true

## ── XP reward (#68, #173, reworked off `level`) ───────────────────────────────
## XP is paid for TERRITORY DESTROYED and nothing else. One currency, one axis:
##
##   per node destroyed  = xp_per_node_killed                    (the trickle)
##   entity killing blow = xp_per_node_killed * (held_at_death + 1)
##                         * entity_kill_bonus                   (the payout)
##
## `level` used to be the base term's axis (`xp_per_victim_level * victim.level`)
## and it was a double-count dressed as a second signal: D-19 pins an enemy's
## level to its starting node count, so "level" and "territory" were already the
## same number, and killing a grown empire paid twice for one fact. Node count is
## the honest axis — it's what the player actually fought through — so the level
## term is gone and the territory term is the whole reward.
##
## Why XP and not looted stats: territory modifiers are only LENT by the graph
## (granted on allocation, released back to neutral on death), so copying them
## into loot would duplicate mods still on the battlefield and re-claimable. XP
## is the honest reward for the scale of the kill; the stat loot draws strictly
## from the core (see `_draw_payload`). See #173 discussion.

## XP for destroying one node — the whittling trickle (#182). Paid per node the
## killer actually depletes; nodes that merely island off the cascade pay
## nothing (they're collateral, not kills, and the entity term already covers the
## territory an entity held).
@export var xp_per_node_killed: float = 5.0

## Multiplier on the entity killing blow, on top of the per-node rate. The kill
## is worth strictly more than dismantling the same territory node by node —
## that premium is what makes going for the throat a real alternative to
## grinding the limbs.
@export var entity_kill_bonus: float = 2.0

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
## Keep-count slope on victim level. Small: at 0.1 you keep +1 per 10 levels, so
## you only walk away with a near-whole core from a much higher-level victim.
##
## Was 0.25, tuned when enemies were low-level. D-19 then pinned enemy level to
## its starting node count (`ProcgenPlaySandbox.enemy_territory_size`, 20 by
## default), so EVERY first_level kill computed keep = 1 + 0.25*20 = 6 against a
## 5-modifier core — N >= M, the picker's explicit no-choice branch. The modal
## never appeared and the player just received the whole core at random, which
## read as "the new loot system isn't wired up". Knob.
@export var core_keep_per_level: float = 0.1

## Optional packed scene for the dust addon (inspector-set). Falls back to a bare
## `SkillDustAddon.new()` when unset — the addon's visual is script-driven, so the
## fallback still renders.
@export var skill_dust_scene: PackedScene = null


func _ready() -> void:
	Events.entity_dying.connect(_on_entity_dying)
	# NOT skill_node_depleted: that signal's other handler (BattleSystem's
	# cascade) clears `owned_by`, and connection order is tree order. The
	# destroyed-phase signal carries the defender instead. See Events.
	Events.skill_node_destroyed.connect(_on_skill_node_destroyed)


## Pre-cleanup phase — corpse still owns its nodes (see Events.entity_dying).
func _on_entity_dying(victim: Entity) -> void:
	if victim == null:
		return
	var killer := _resolve_killer(victim)
	_award_kill_xp(victim, killer)
	_drop_skill_dust(victim)
	_award_spell_loot(victim, killer)
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
	# `+ 1` counts the core the victim died on. `_held_node_count` deliberately
	# excludes it (it answers "territory"), but for the reward the core IS a node
	# the killer had to destroy — and without it a landless enemy (D-19's core-only
	# elite) would be worth a flat zero.
	#
	# ASSUMPTION — held AT DEATH, not before the attack that killed. Whittling the
	# limbs first shrinks this term, but each of those nodes already paid
	# `xp_per_node_killed` on its own destruction, so the two paths stay
	# comparable instead of double-counting the same territory.
	var nodes := _held_node_count(victim) + 1
	_grant_xp(killer, xp_per_node_killed * float(nodes) * entity_kill_bonus)


## Per-node kill trickle (#182). Reacts to the destroyed-phase signal so the
## defender is known even though BattleSystem's cascade handler has already
## stripped the node by the time a `skill_node_depleted` listener would run.
func _on_skill_node_destroyed(node: SkillNode, defender: Entity) -> void:
	if not award_xp_on_node_kill or node == null or defender == null:
		return
	var killer := _resolve_killer(defender)
	if killer == null or killer.is_dead:
		return
	_grant_xp(killer, xp_per_node_killed)


## Pour `amount` XP onto `entity`'s pool. Always through `replenish` — a raw
## `set_current` would skip `on_pool_filled` and thus the level-up cascade.
func _grant_xp(entity: Entity, amount: float) -> void:
	if amount <= 0.0 or entity == null:
		return
	var board := entity.stat_board
	if board == null or board.xp == null:
		return
	board.xp.replenish(amount)


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


## Build the CORE-ONLY loot draw. The candidate pool is the victim's core_class
## modifier set (class-identity template) — the only modifiers genuinely lost when
## the entity dies. Previously-looted mods are permanent board additions and are
## not individually re-lootable (#185). Offered as pick-N-from-M: M = the
## full core supply, N (keep-count) scales with victim level. When N >= M the
## picker won't pop (no real choice) and the addon auto-grants all. Every entry
## is `duplicate(true)`d so the dust owns independent copies.
## Returns { "candidates": Array[StatModifier], "pick_count": int }.
func _draw_payload(victim: Entity) -> Dictionary:
	var core_mods := _core_modifiers(victim).filter(_is_lootable)
	var supply := core_mods.size()
	var keep := core_keep_base + core_keep_per_level * float(maxi(0, victim.level))
	var pick_count := clampi(roundi(keep), 0, supply)
	# Keep the draw a genuine choice whenever one is possible. N == M is a
	# no-choice by construction (the addon auto-grants and the picker skips it),
	# so a keep-count that saturates the supply silently deletes the entire
	# pick-N-from-M feature — which is exactly what a high-level victim did.
	# Leaving at least one modifier on the table is what makes it a decision.
	if supply >= 2:
		pick_count = mini(pick_count, supply - 1)

	core_mods.shuffle()
	var candidates: Array[StatModifier] = []
	for m in core_mods:
		candidates.append(m.duplicate(true))
	return {"candidates": candidates, "pick_count": pick_count}


## Count of non-core nodes the victim still owns at death — the TERRITORY signal
## feeding the kill-XP payout (was the loot draw pre-#173-rework). Reads the
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


## Level-scaled identity mods are lost on death like the rest of the core set,
## but they are NOT lootable (#194). A `+1 STR per level` entry describes the
## victim's *progression*, not a transferable trinket — and since `duplicate(true)`
## keeps the shared formula, a looted copy would silently rebind to the LOOTER's
## level and grant a scaling relic nobody designed. Filtered in [method _draw_payload]
## rather than in [method _core_modifiers], which stays an honest answer to
## "what vanishes on death".
##
## Only `level` scaling is excluded — a plain formula mod ("+2 vision per PER")
## is ordinary class identity and stays lootable.
func _is_lootable(m: StatModifier) -> bool:
	return not m.scales_with(&"level")


## Core source: class identity mods (+10 STR/DEX/INT for BalancedCore, etc.).
## Previously-looted mods are permanent board additions (no node storage since
## #185) — they're not individually re-lootable; the loot chain starts fresh
## from each entity's core_class template.
func _core_modifiers(victim: Entity) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	if victim.core_class != null:
		out.append_array(victim.core_class.modifiers)
	return out


func _attach_addon(node: SkillNode, addon: SkillNodeAddon) -> void:
	var anchor := node.get_node_or_null("Visuals/AddonAnchor")
	if anchor != null:
		anchor.add_child(addon)
	else:
		node.add_child(addon)  # headless fallback (no Visuals subtree)


# ── #204: Spellbook loot draft (core-permanent spells) ───────────────────────
## The draft draws from the victim's PERMANENT spellbook — core-node-sourced ∪
## innate (both survive a dealloc, both vanish with the entity; territory-node
## spells already left the book when their node was cascade-stripped, so
## looting them would duplicate a spell that's still live on the battlefield —
## same anti-duplication reasoning as the core-only SkillDust draw above).
## Fires SYNCHRONOUSLY on the same `entity_dying` phase as the dust drop, so
## both requests reach HudRoot in the same call stack — HudRoot queues them
## (dust first, since it's dispatched first here).

## Offer is capped at this many candidates (M = min(this, remaining)).
const _SPELL_OFFER_CAP: int = 3
## Fixed keep-count for #204's MVP — see the issue NOTES on keep-count scaling.
const _SPELL_PICK_COUNT: int = 1


func _award_spell_loot(victim: Entity, killer: Entity) -> void:
	if not award_spell_loot_on_death:
		return
	if killer == null or killer.is_dead:
		return
	var victim_book := victim.spellbook
	if victim_book == null or victim.core_location == null:
		return
	var candidates := victim_book.permanent_spells(victim.core_location)
	candidates = _exclude_known(candidates, killer)
	if candidates.is_empty():
		return

	candidates.shuffle()
	var offer_count := mini(_SPELL_OFFER_CAP, candidates.size())
	var offered: Array[SpellDef] = []
	for i in offer_count:
		offered.append(candidates[i])

	var request := SpellLootRequest.new(
			killer, offered, _SPELL_PICK_COUNT, _make_spell_resolver(killer))
	Events.spell_loot_requested.emit(request)
	if not request.handled:
		# NPC / headless / no-HUD path — the DEFAULT branch. Random N of M.
		var pool := offered.duplicate()
		pool.shuffle()
		var auto_pick: Array[SpellDef] = []
		for i in mini(_SPELL_PICK_COUNT, pool.size()):
			auto_pick.append(pool[i])
		request.resolve(auto_pick)


## Territory-known (temporary) spells stay offerable as an upgrade — only
## PERMANENTLY-known spells are excluded, so the offer is a genuine addition.
func _exclude_known(candidates: Array[SpellDef], killer: Entity) -> Array[SpellDef]:
	if killer.spellbook == null or killer.core_location == null:
		return candidates
	var known := killer.spellbook.permanent_spells(killer.core_location)
	var out: Array[SpellDef] = []
	for s in candidates:
		if not known.has(s):
			out.append(s)
	return out


## Learn mechanism (#204): a [SpellGrant] placed on the killer's CORE node,
## same mechanism as an authored/earned core spell — symmetric, and re-lootable
## when the killer later dies (the draw reads core-sourced spells).
func _make_spell_resolver(killer: Entity) -> Callable:
	return func(chosen: Array[SpellDef]) -> void:
		if not is_instance_valid(killer) or killer.is_dead or killer.core_location == null:
			return
		for spell in chosen:
			if spell == null:
				continue
			var grant := SpellGrant.new()
			grant.spell_def = spell
			killer.core_location.effects.append(grant)       # persist on the node
			killer.grant_effect(grant, killer.core_location) # → book.add_spell(spell, core_node)
