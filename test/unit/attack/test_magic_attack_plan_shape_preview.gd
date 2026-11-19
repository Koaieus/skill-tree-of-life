extends GutTest

## A cast shape in the aim-time range preview: [MagicAttackPlan] draws the
## shaped seed off the gather's own pure functions, never the shadow walk's
## timeline (which carries no shape landing). A Fire shape adds one
## [RangeVisual.Ring] at the seed, radius [method DiscGoOff.shape_disc_radius]
## of the shape alone off the seed's radius; a Lightning shape paints every
## seen node within [method EdgeGoOff.level_for_points] hops of the seed
## PROPAGATION. The shape's own reach only: a primed seed draws the same.
##
## Fixture: a chain S-1-T-3-4-5 (S the attacker's caster, the rest hostile),
## a hop-finder targeting (no ring of its own) and a walk of max_hops 0, so
## the spell's walk lands on T alone and every PROPAGATION paint past T is
## the shape's.

const _PROPAGATION := HighlightProvider.HighlightRole.PROPAGATION

var h: SpellTestHelper
var _fire: Element
var _light: Element


## A fog stub: every node in [member hidden] is unseen.
class _Fog extends VisionSystem:
	var hidden: Dictionary = {}

	func is_visible(node: SkillNode) -> bool:
		return not hidden.has(node)


func before_each() -> void:
	h = SpellTestHelper.new()
	_fire = ElementRoster.shared().by_id(&"fire")
	_light = ElementRoster.shared().by_id(&"lightning")


## Returns [graph, plan, nodes] with T = nodes[2] committed.
func _fixture() -> Array:
	var graph := h.make_graph([[0, 1], [1, 2], [2, 3], [3, 4], [4, 5]], self)
	graph.navigator.wire_to(graph)
	var attacker := h.make_entity(graph, "ATK", Color.RED)
	var defender := h.make_entity(graph, "DEF", Color.BLUE)
	h.give_big_hp(defender)
	h.assign_owner(graph, attacker, [0])
	h.assign_owner(graph, defender, [1, 2, 3, 4, 5])
	var config := h.make_config(h.fan_all(), h.owner_enemy(), h.max_reducer(), {max_hops = 0})
	var effects: Array[OnHitEffect] = [DamageEffect.new()]
	var spell := h.make_spell(config, effects, 1.0)
	var t := NodeTargeting.new()
	t.ownership_filter = SkillNode.Ownership.HOSTILE
	var finder := HopRangeFinder.new()
	finder.max_hops = 10
	t.range_finder = finder
	spell.targeting = t
	spell.min_degree = 0
	var plan := MagicAttackPlan.new()
	plan.attacker = attacker
	plan.spell = spell
	var nodes := graph.get_skill_nodes()
	assert_true(plan.set_target(nodes[2]), "fixture: T is a legal target")
	assert_eq(plan.source, nodes[0], "fixture: S casts")
	return [graph, plan, nodes]


func _disc() -> DiscGoOff:
	for band in _fire.bands:
		if band != null and band.go_off is DiscGoOff:
			return band.go_off
	return null


func _roles(plan: MagicAttackPlan, nodes: Array) -> Array:
	var out := []
	for n: SkillNode in nodes:
		out.append(plan.get_node_role(n))
	return out


func _rings(plan: MagicAttackPlan) -> Array:
	var visual := plan.get_range_visual()
	return [] if visual == null else visual.rings


# ── Fire ────────────────────────────────────────────────────────────────

func test_no_shape_draws_no_ring() -> void:
	var f := _fixture()
	assert_eq(_rings(f[1]).size(), 0, "a hop finder and no shape draw no ring")


func test_a_fire_shape_adds_one_ring_at_the_seed() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var tn: SkillNode = f[2][2]
	plan.set_shape(&"fire", 3)
	assert_eq(plan.infusion.shape_points, 3, "fixture: 3 points of Fire forged")
	var rings := _rings(plan)
	assert_eq(rings.size(), 1, "exactly one ring")
	if rings.size() != 1:
		return
	var want := _disc().shape_disc_radius(_fire.shape_power(3), 0.0, tn.radius)
	assert_eq((rings[0] as RangeVisual.Ring).position, tn.global_position, "centred on T")
	assert_almost_eq((rings[0] as RangeVisual.Ring).radius, want, 0.001,
			"radius shape_disc_radius(3 × per-point, 0, R)")
	assert_eq(_rings(plan).size(), 1, "a repaint still draws exactly one ring")


func test_a_burning_seed_draws_the_shape_alone() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var tn: SkillNode = f[2][2]
	var c := tn.get_combat()
	c.add_terrain(_fire, c.terrain_threshold() + 4)
	assert_not_null(c.terrain_band(_fire), "fixture: T is Burning")
	plan.set_shape(&"fire", 3)
	var rings := _rings(plan)
	assert_eq(rings.size(), 1, "exactly one ring")
	if rings.size() == 1:
		assert_almost_eq((rings[0] as RangeVisual.Ring).radius,
				_disc().shape_disc_radius(_fire.shape_power(3), 0.0, tn.radius), 0.001,
				"no add-up with T's own excess")


# ── Lightning ───────────────────────────────────────────────────────────

func test_a_lightning_shape_paints_within_its_level() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var nodes: Array = f[2]
	var before := _roles(plan, [nodes[1], nodes[3], nodes[4], nodes[5]])
	assert_false(_PROPAGATION in before, "control: the walk alone paints no neighbour")
	plan.set_shape(&"lightning", 3)
	assert_eq(plan.infusion.shape_points, 3, "fixture: 3 points (level 2) of Lightning")
	assert_eq(plan.get_node_role(nodes[1]), _PROPAGATION, "1 hop, toward S")
	assert_eq(plan.get_node_role(nodes[3]), _PROPAGATION, "1 hop")
	assert_eq(plan.get_node_role(nodes[4]), _PROPAGATION, "2 hops")
	assert_ne(plan.get_node_role(nodes[5]), _PROPAGATION, "3 hops is past level 2")
	assert_eq(plan.get_node_role(nodes[0]), HighlightProvider.HighlightRole.ORIGIN, "S stays the origin")
	assert_eq(plan.get_node_role(nodes[2]), HighlightProvider.HighlightRole.HOSTILE_TARGET,
			"T stays the target")
	assert_eq(_rings(plan).size(), 0, "Lightning draws no ring")


func test_a_fogged_node_stays_unpainted() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var nodes: Array = f[2]
	var fog := _Fog.new()
	fog.hidden[nodes[4]] = true
	autofree(fog)
	plan.viewer_vision = fog
	plan.set_shape(&"lightning", 3)
	assert_eq(plan.get_node_role(nodes[3]), _PROPAGATION, "a seen node paints")
	assert_ne(plan.get_node_role(nodes[4]), _PROPAGATION, "a fogged one does not")


func test_a_shocked_seed_draws_the_shape_alone() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var nodes: Array = f[2]
	var c := (nodes[2] as SkillNode).get_combat()
	c.add_terrain(_light, c.terrain_threshold() * 20)
	assert_not_null(c.terrain_band(_light), "fixture: T is Shocked")
	assert_ne(plan.get_node_role(nodes[4]), _PROPAGATION, "control: unshaped, 2 hops is unpainted")
	plan.set_shape(&"lightning", 3)
	assert_eq(plan.get_node_role(nodes[4]), _PROPAGATION, "level 2 reaches 2 hops")
	assert_ne(plan.get_node_role(nodes[5]), _PROPAGATION, "no add-up with T's own level")


func test_a_hovered_target_previews_the_shape_and_keeps_the_caster() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var nodes: Array = f[2]
	plan.reset()
	plan.set_shape(&"lightning", 3)
	plan.set_hover_target(nodes[2])
	assert_null(plan.target, "fixture: nothing committed")
	assert_eq(plan.get_node_role(nodes[4]), _PROPAGATION, "the hover previews the shape")
	assert_eq(plan.get_node_role(nodes[0]), HighlightProvider.HighlightRole.CASTER,
			"the would-be caster keeps its role")


# ── purity ──────────────────────────────────────────────────────────────

func test_a_shaped_preview_mutates_nothing() -> void:
	var f := _fixture()
	var plan: MagicAttackPlan = f[1]
	var nodes: Array = f[2]
	var watched: Array[SkillNode] = [nodes[2], nodes[3], nodes[4]]
	var before := []
	for n in watched:
		var c := n.get_combat()
		before.append([n.get_current_hp(), n.owned_by, c.terrain_t(), c.charge()])
	var ap: float = plan.attacker.stat_board.action_points.current
	for id: StringName in [&"fire", &"lightning"]:
		plan.set_shape(id, 3)
		_roles(plan, nodes)
		plan.get_range_visual()
	for i in watched.size():
		var c := watched[i].get_combat()
		assert_eq([watched[i].get_current_hp(), watched[i].owned_by, c.terrain_t(), c.charge()],
				before[i], "node %d: HP, owner, heat, charge unchanged" % i)
	assert_eq(plan.attacker.stat_board.action_points.current, ap, "no AP spent")
