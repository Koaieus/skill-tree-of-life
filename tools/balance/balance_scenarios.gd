class_name BalanceScenarios
extends RefCounted

## Named scenario fixtures + readouts for the #268 balance harness. Every
## number here comes off a real `Entity`/`SkillNode` pair driven through the
## real allocation / damage / turn-upkeep code paths (`BalanceFixture`) — no
## formula is reimplemented, per #268 decision 2/3.
##
## `run_all(root)` is a coroutine; `root` is anything with a `get_tree()`
## (a `SceneTree`'s own root, or a `GutTest` node already in the tree).

const _BALANCED := preload("res://entity/core/balanced_core.tres")
const _BOARD := preload("res://entity/default_entity_board.tres")

## The full authored spell pool — the real `SpellDef` resources the magic
## readouts are computed against (#366; "full pool" per D-34). Preloaded so a
## retune of any spell's `power` / `mana_cost` shows up in the snapshot
## automatically, without touching this file.
const _SPELL_POOL := [
	preload("res://attack/spell/defs/spark.tres"),
	preload("res://attack/spell/defs/bruiser.tres"),
	preload("res://attack/spell/defs/leafblower.tres"),
	preload("res://attack/spell/defs/lightning_bolt.tres"),
	preload("res://attack/spell/defs/resonator.tres"),
	preload("res://attack/spell/defs/reverberator.tres"),
	preload("res://attack/spell/defs/trail_blazer.tres"),
]


## Ordered scenario names — also the row order of the printed table / snapshot.
const NAMES: PackedStringArray = [
	"mirror_L5",
	"mirror_L20",
	"mirror_L50",
	"matched_L100_zero_invest",
	"asymmetric_snipe_L20_vs_L80",
	"core_adjacent_aura_L50",
	"magic_mirror_L20",
]


static func run_all(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(await _mirror(root, "mirror_L5", 5))
	out.append(await _mirror(root, "mirror_L20", 20))
	out.append(await _mirror(root, "mirror_L50", 50))
	out.append(await _matched_zero_invest(root, "matched_L100_zero_invest", 100))
	out.append(await _snipe(root, "asymmetric_snipe_L20_vs_L80", 20, 80))
	out.append(await _core_adjacent_aura(root, "core_adjacent_aura_L50", 50))
	out.append(await _magic_mirror(root, "magic_mirror_L20", 20))
	return out


# ── Scenario builders ───────────────────────────────────────────────────────

## Both sides at the same level, both plain BalancedCore — the vanilla
## channel-parity / TTK reading at that level band.
static func _mirror(root: Node, name: String, level: int) -> Dictionary:
	var attacker := await BalanceFixture.build(root, level, _BALANCED)
	var defender := await BalanceFixture.build(root, level, _BALANCED)
	var readouts := combat_readouts(attacker, defender)
	readouts.merge(await _territory_growth(root, level, _BALANCED))
	free_fixture(attacker)
	free_fixture(defender)
	return {"name": name, "readouts": readouts}


## REQUIRED fixture (#268): matched level, attacker with ZERO STR/DEX
## investment (`core_class = null` — only the board's level→CON intrinsic
## still applies, since that channel is class-independent). Without this,
## `baseline_raw_damage_vs_mitigation_at_matched_level` isn't computable —
## comparing against a fixed/low-level attacker would conflate "uninvested"
## with "underleveled".
static func _matched_zero_invest(root: Node, name: String, level: int) -> Dictionary:
	var attacker := await BalanceFixture.build(root, level, null)
	var defender := await BalanceFixture.build(root, level, _BALANCED)
	var readouts := combat_readouts(attacker, defender)

	var raw: float = readouts.get("ranged_damage_raw", 0.0)
	var mitigated: float = readouts.get("mitigated_ranged_damage", 0.0)
	readouts["baseline_raw_damage_vs_mitigation_at_matched_level"] = \
		(mitigated / raw) if raw > 0.0 else 0.0
	readouts["defender_armor"] = float(defender.core_node().get_local_value(&"armor"))
	readouts["defender_min_damage_taken"] = float(defender.core_node().get_local_value(&"min_damage_taken"))

	free_fixture(attacker)
	free_fixture(defender)
	return {"name": name, "readouts": readouts}


## A low-level attacker sniping a much higher-level defender (or vice versa,
## depending which side of the table is read) — spans the range the D-16/D-21
## renormalization was meant to keep sane. Also the fixture that gives
## `melee_dpa_over_ranged_dpa` something to actually measure: every other
## scenario uses plain BalancedCore, where STR == DEX and the ratio would
## read 1.000 by construction — the sniper's DEX-over-STR skew is what makes
## the invariant move at all.
static func _snipe(root: Node, name: String, attacker_level: int, defender_level: int) -> Dictionary:
	var attacker := await BalanceFixture.build(root, attacker_level, _BALANCED)
	attacker.entity.stat_board.dexterity.base_value += 30.0
	attacker.entity.stat_board.strength.base_value = maxf(
		attacker.entity.stat_board.strength.base_value - 5.0, 0.0)
	var defender := await BalanceFixture.build(root, defender_level, _BALANCED)
	var readouts := combat_readouts(attacker, defender)
	free_fixture(attacker)
	free_fixture(defender)
	return {"name": name, "readouts": readouts}


## REQUIRED fixture (#268): defender's own core-adjacent territory (hop 0/1/2/3
## and beyond-range) under a base-10/range-3 heal aura, granted through a real
## `CoreClass` so `Entity._on_turn_started` applies it via the production path
## (never a hand-rolled `values_from` call standing in for the real mechanic).
## Makes both `aura_coverage_fraction` and `core_node_ttk_under_sustained_pressure`
## computable.
##
## Built on a branching (k-ary tree) topology, NOT the chain the other
## scenarios use. #268 review: a straight chain caps a range-R aura at
## exactly R covered nodes forever, so `aura_coverage_fraction` on a chain
## reports "safe" for a topological reason, never a balance one — D-10's
## sanctuary bubble is a statement about a hop-ball in BRANCHING territory,
## where the same range can plausibly cover a large fraction of a
## 100+-node entity. The branching factor is exactly what makes that
## fraction move, so it's reported alongside the reading.
const _AURA_BRANCHING_FACTOR := 3

static func _core_adjacent_aura(root: Node, name: String, level: int) -> Dictionary:
	var aura_class := CoreClass.new()
	var aura := HealAura.new()
	aura.base = 10.0
	aura.range = 3.0
	aura_class.aura = aura

	var attacker := await BalanceFixture.build(root, level, _BALANCED)
	var defender := await BalanceFixture.build(
		root, level, aura_class, BalanceFixture.Topology.TREE, _AURA_BRANCHING_FACTOR)

	var core := defender.core_node()
	var aura_values := aura.values_from(core, defender.entity.navigator)
	var owned := defender.owned_count()
	var readouts: Dictionary = {
		"defender_level": level,
		"defender_owned_nodes": owned,
		"topology_branching_factor": _AURA_BRANCHING_FACTOR,
		"aura_covered_nodes": aura_values.size(),
		"aura_coverage_fraction": (float(aura_values.size()) / float(owned)) if owned > 0 else 0.0,
	}

	# Sustained pressure: the attacker's mitigated ranged hit, landed on the
	# defender's CORE node every turn, with the defender's own turn-start
	# upkeep (node regen + the aura) running in between — the real D-9/D-10
	# interplay, not a standalone formula.
	var raw: float = float(attacker.core_node().get_local_value(&"ranged_damage"))
	var cap := 200
	var turns := 0
	var depleted := false
	while turns < cap:
		var hit := DamageInstance.new()
		hit.amount = raw
		hit.type = DamageInstance.Type.PHYSICAL
		core.take_damage(hit.amount, hit) # take_damage runs Mitigation.apply internally
		turns += 1
		if core.get_current_hp() <= 0.0:
			depleted = true
			break
		defender.entity._on_turn_started(defender.entity)
	readouts["core_node_ttk_under_sustained_pressure"] = turns if depleted else -1
	readouts["core_node_ttk_pressure_per_turn"] = raw

	free_fixture(attacker)
	free_fixture(defender)
	return {"name": name, "readouts": readouts}


# ── Shared readout computation ──────────────────────────────────────────────

## The magic channel (#366, follow-up to #268): the same mirror shape as the
## physical channels, but the damage readout is the D-32 seed — computed by
## the REAL production seed path (`SpellResolver._seed_damage`, i.e.
## `spell_damage(cast-from node) × power`) — run through the real
## `Mitigation.apply` against the defender's standard target node. AP cost is
## read as 1 for the magic channel, same as melee/ranged (see README).
##
## One row per real SpellDef in the pool: every seed scales with the caster's
## INT, so no single spell represents "the magic channel". The strongest seed
## plus the parity ratio against melee are what the invariant reads.
static func _magic_mirror(root: Node, name: String, level: int) -> Dictionary:
	var attacker := await BalanceFixture.build(root, level, _BALANCED)
	var defender := await BalanceFixture.build(root, level, _BALANCED)
	var readouts := combat_readouts(attacker, defender)

	var atk_core := attacker.core_node()
	var target: SkillNode = defender.nodes[1] if defender.nodes.size() > 1 else defender.core_node()
	readouts["spell_damage"] = float(atk_core.get_local_value(&"spell_damage"))

	var best := 0.0
	for spell in _SPELL_POOL:
		var seed: float = SpellResolver._seed_damage(spell, atk_core)
		var hit := DamageInstance.new()
		hit.amount = seed
		hit.type = DamageInstance.Type.MAGIC
		var mitigated: float = Mitigation.apply(hit, target)
		readouts["spell_dpa_%s" % spell.name] = mitigated
		best = maxf(best, mitigated)

	readouts["spell_dpa_best"] = best
	var melee_dpa: float = readouts.get("damage_per_ap_melee", 0.0)
	readouts["spell_dpa_over_melee_dpa"] = (best / melee_dpa) if melee_dpa > 0.0 else 0.0

	free_fixture(attacker)
	free_fixture(defender)
	return {"name": name, "readouts": readouts}


static func combat_readouts(attacker: BalanceFixture, defender: BalanceFixture) -> Dictionary:
	var atk_core := attacker.core_node()
	var def_target: SkillNode = defender.nodes[1] if defender.nodes.size() > 1 else defender.core_node()

	var ranged_raw: float = float(atk_core.get_local_value(&"ranged_damage"))
	var melee_raw: float = float(atk_core.get_local_value(&"blade_damage"))

	var ranged_hit := DamageInstance.new()
	ranged_hit.amount = ranged_raw
	ranged_hit.type = DamageInstance.Type.PHYSICAL
	var mitigated_ranged: float = Mitigation.apply(ranged_hit, def_target)

	var melee_hit := DamageInstance.new()
	melee_hit.amount = melee_raw
	melee_hit.type = DamageInstance.Type.PHYSICAL
	var mitigated_melee: float = Mitigation.apply(melee_hit, def_target)

	var node_max_hp: float = def_target.get_max_hp()
	var health_max: float = float(defender.entity.stat_board.health.value)

	var sp_gain: float = float(defender.entity.stat_board.sp_gain_on_levelup.value)
	var next_level: int = int(defender.entity.level) + 1
	var milestone: bool = (next_level % 5) == 0
	var marginal_sp: float = sp_gain + (1.0 if milestone else 0.0)

	return {
		"attacker_level": attacker.entity.level,
		"defender_level": defender.entity.level,
		"attacker_owned_nodes": attacker.owned_count(),
		"defender_owned_nodes": defender.owned_count(),
		"ranged_damage_raw": ranged_raw,
		"melee_damage_raw": melee_raw,
		# Mitigated, per-AP — NOT raw. Mitigation is non-linear
		# (max(min_damage_taken, raw - armor)), so a raw-damage ratio and this
		# one genuinely diverge wherever the floor bites (see
		# matched_L100_zero_invest, where raw 2 mitigates to 3). AP cost is
		# read as 1 for both channels because neither attack_plan.gd resolve()
		# ever sets AttackOutcome.ap_cost away from its default — see
		# tools/balance/README.md for that assumption in one place, not just
		# this comment.
		"damage_per_ap_ranged": mitigated_ranged,
		"damage_per_ap_melee": mitigated_melee,
		"melee_dpa_over_ranged_dpa": (mitigated_melee / mitigated_ranged) if mitigated_ranged > 0.0 else 0.0,
		"mitigated_ranged_damage": mitigated_ranged,
		"mitigated_melee_damage": mitigated_melee,
		"defender_node_max_hp": node_max_hp,
		"hits_to_drop_node": ceili(node_max_hp / mitigated_ranged) if mitigated_ranged > 0.0 else -1,
		"defender_health_pool": health_max,
		"turns_to_drop_core_naive": ceili(health_max / mitigated_ranged) if mitigated_ranged > 0.0 else -1,
		"sp_income_at_level_max": float(defender.entity.stat_board.skill_points.value),
		"sp_income_at_level_marginal": marginal_sp,
	}


## Fresh, node-less entity used only to time "turns until the next level-up"
## via the real xp/level-up path — kept separate from the combat fixtures so
## the simulation's level-ups don't corrupt readouts already captured on them.
static func _territory_growth(root: Node, level: int, core_class: CoreClass) -> Dictionary:
	var probe := Entity.new()
	probe.display_name = "XPProbe"
	probe.stat_board = _BOARD.duplicate(true) as StatBoard
	probe.core_class = core_class
	root.add_child(probe)
	await root.get_tree().process_frame

	for _i in range(level - 1):
		probe._on_xp_replenished()

	var sp_before: float = probe.stat_board.skill_points.value
	var start_level: int = int(probe.level)
	var cap := 500
	var turns := 0
	while int(probe.level) == start_level and turns < cap:
		probe._on_turn_started(probe)
		turns += 1

	var sp_minted: float = probe.stat_board.skill_points.value - sp_before
	var levelled: bool = int(probe.level) != start_level
	probe.queue_free()

	return {
		"territory_growth_turns_per_level": turns if levelled else -1,
		"territory_growth_sp_per_level": sp_minted if levelled else 0.0,
		"territory_growth_per_turn": (sp_minted / turns) if levelled and turns > 0 else 0.0,
	}


static func free_fixture(fx: BalanceFixture) -> void:
	if fx.alloc != null:
		fx.alloc.queue_free()
	if fx.graph != null:
		fx.graph.queue_free() # frees the entity + nodes parented under it too
