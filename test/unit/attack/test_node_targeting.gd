extends GutTest

## NodeTargeting.ownership_filter (#384): the four mutually-exclusive
## ownership buckets (Neutral/Mine/Ally/Hostile, see [SkillNode.Ownership])
## and the composite flags (Friendly, Allocated, Any) that OR them together.
## `range_finder` is left null throughout — unlimited reach, so these tests
## isolate the ownership predicate.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _PLAYER_FACTION := preload("res://entity/factions/player.tres")
const _NPC_FACTION := preload("res://entity/factions/npc.tres")

var _attacker: Entity
var _ally: Entity
var _hostile: Entity

var _neutral_node: SkillNode
var _mine_node: SkillNode
var _ally_node: SkillNode
var _hostile_node: SkillNode

var _plan: RangedAttackPlan
var _source: SkillNode


func before_each() -> void:
	_attacker = autofree(Entity.new())
	_attacker.faction = _PLAYER_FACTION
	_ally = autofree(Entity.new())
	_ally.faction = _PLAYER_FACTION
	_hostile = autofree(Entity.new())
	_hostile.faction = _NPC_FACTION

	_neutral_node = autofree(_SKILL_NODE_SCENE.instantiate())
	_mine_node = autofree(_SKILL_NODE_SCENE.instantiate())
	_mine_node.owned_by = _attacker
	_ally_node = autofree(_SKILL_NODE_SCENE.instantiate())
	_ally_node.owned_by = _ally
	_hostile_node = autofree(_SKILL_NODE_SCENE.instantiate())
	_hostile_node.owned_by = _hostile

	_plan = autofree(RangedAttackPlan.new())
	_plan.attacker = _attacker
	_source = autofree(_SKILL_NODE_SCENE.instantiate())
	_source.owned_by = _attacker


func _targeting(filter: int) -> NodeTargeting:
	var t := NodeTargeting.new()
	t.ownership_filter = filter
	return t


# ── The four mutually exclusive buckets ──────────────────────────────────────

func test_neutral_bucket_accepts_only_unowned() -> void:
	var t := _targeting(SkillNode.Ownership.NEUTRAL)
	assert_true(t.is_valid_target(_plan, _source, _neutral_node))
	assert_false(t.is_valid_target(_plan, _source, _mine_node))
	assert_false(t.is_valid_target(_plan, _source, _ally_node))
	assert_false(t.is_valid_target(_plan, _source, _hostile_node))


func test_mine_bucket_accepts_only_own_node() -> void:
	var t := _targeting(SkillNode.Ownership.MINE)
	assert_false(t.is_valid_target(_plan, _source, _neutral_node))
	assert_true(t.is_valid_target(_plan, _source, _mine_node))
	assert_false(t.is_valid_target(_plan, _source, _ally_node))
	assert_false(t.is_valid_target(_plan, _source, _hostile_node))


func test_ally_bucket_accepts_only_an_allied_owner() -> void:
	var t := _targeting(SkillNode.Ownership.ALLY)
	assert_false(t.is_valid_target(_plan, _source, _neutral_node))
	assert_false(t.is_valid_target(_plan, _source, _mine_node))
	assert_true(t.is_valid_target(_plan, _source, _ally_node))
	assert_false(t.is_valid_target(_plan, _source, _hostile_node))


func test_hostile_bucket_rejects_an_ally_node() -> void:
	# The concrete regression this issue exists to fix: a Hostile-filtered
	# spell (the default, e.g. a damage bolt) must not be castable on a
	# same-faction ally just because it isn't the caster's own node.
	var t := _targeting(SkillNode.Ownership.HOSTILE)
	assert_false(t.is_valid_target(_plan, _source, _neutral_node))
	assert_false(t.is_valid_target(_plan, _source, _mine_node))
	assert_false(t.is_valid_target(_plan, _source, _ally_node))
	assert_true(t.is_valid_target(_plan, _source, _hostile_node))


# ── Composite flags ───────────────────────────────────────────────────────────

func test_friendly_composite_accepts_both_mine_and_ally() -> void:
	# Friendly:6 = Mine(2) | Ally(4).
	var t := _targeting(6)
	assert_false(t.is_valid_target(_plan, _source, _neutral_node))
	assert_true(t.is_valid_target(_plan, _source, _mine_node))
	assert_true(t.is_valid_target(_plan, _source, _ally_node))
	assert_false(t.is_valid_target(_plan, _source, _hostile_node))


func test_allocated_composite_excludes_only_neutral() -> void:
	# Allocated:14 = Mine(2) | Ally(4) | Hostile(8).
	var t := _targeting(14)
	assert_false(t.is_valid_target(_plan, _source, _neutral_node))
	assert_true(t.is_valid_target(_plan, _source, _mine_node))
	assert_true(t.is_valid_target(_plan, _source, _ally_node))
	assert_true(t.is_valid_target(_plan, _source, _hostile_node))


func test_any_composite_accepts_all_four() -> void:
	var t := _targeting(SkillNode.Ownership.NEUTRAL | SkillNode.Ownership.MINE
			| SkillNode.Ownership.ALLY | SkillNode.Ownership.HOSTILE)
	assert_true(t.is_valid_target(_plan, _source, _neutral_node))
	assert_true(t.is_valid_target(_plan, _source, _mine_node))
	assert_true(t.is_valid_target(_plan, _source, _ally_node))
	assert_true(t.is_valid_target(_plan, _source, _hostile_node))


## --- get_range_finder: the ONE way to ask a Targeting for its reach model ---
##
## Three call sites used to spell this three different ways — a reflective
## `targeting.get(&"range_finder")` in SpellSections, a bare `.range_finder`
## property read in EdgeHighlightOverlay (a runtime crash the day a second
## Targeting subclass exists), and a `as NodeTargeting` cast in
## SpellTargetUnion. One virtual on the base is the whole answer.

func test_base_targeting_has_no_range_finder() -> void:
	# The contract that makes the overlay's read safe: asking ANY Targeting is
	# legal and answers null when the subclass has no reach model.
	var bare := _BareTargeting.new()
	assert_null(bare.get_range_finder(),
			"Targeting.get_range_finder must answer null on a subclass with no finder")


func test_node_targeting_returns_its_own_finder() -> void:
	var t := NodeTargeting.new()
	var finder := HopRangeFinder.new()
	t.range_finder = finder
	assert_eq(t.get_range_finder(), finder,
			"NodeTargeting.get_range_finder must hand back its authored range_finder")


func test_node_targeting_without_a_finder_answers_null() -> void:
	assert_null(NodeTargeting.new().get_range_finder(),
			"An unbounded NodeTargeting (no range_finder authored) answers null")


## A minimal non-NodeTargeting subclass — the case the overlay's property read
## would have crashed on.
class _BareTargeting extends Targeting:
	func is_valid_target(_plan: AttackPlan, _source: SkillNode, _candidate: SkillNode) -> bool:
		return true
