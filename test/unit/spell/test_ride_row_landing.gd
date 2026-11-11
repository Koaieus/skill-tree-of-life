extends GutTest

## #1800 acceptance 6: a spell with a Heat ride row (identity Fire, `plants`
## Heat) lands its load as Heat terrain in the node's `t` and plants no status
## row — the rider is the same one Poison's row emits, the terrain writer is
## the landing's.

const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _HEAT := preload("res://effects/status/heat.tres")

var _graph: Graph
var _alloc: AllocationSystem
var _node: SkillNode


func before_each() -> void:
	_graph = TestWorld.create(self).graph
	_alloc = TestWorld.around(_graph).allocator()
	var entity := autofree(Entity.new()) as Entity
	_graph.add_child(entity)
	_node = _SKILL_NODE_SCENE.instantiate() as SkillNode
	_graph.skill_nodes_container.add_child(_node)
	await get_tree().process_frame
	_alloc.force_allocate(entity, _node)


func test_a_heat_ride_row_writes_heat_into_t_and_plants_no_status_row() -> void:
	var spell := SpellDef.new()
	var row := AspectIntake.new()
	row.identity = ElementRoster.shared().by_id(&"fire").identity
	row.plants = _HEAT
	row.innate = 4
	spell.intakes = [row]
	var fire := ElementRoster.shared().by_id(&"fire")
	var landing := HitLanding.new()
	landing.target = _node
	for rider in Infusion.innate(spell).riders(spell):
		rider.apply(landing)
	for h in landing.hits:
		var inst := h as StatusInstance
		inst.land_on(inst.target.get_combat(), CombatWorld.live())
	var combat := _node.get_combat()
	assert_eq(combat.terrain_count(fire), 4, "Heat 4 lands in the node's t")
	assert_eq(combat.get_status_power(&"heat"), 0.0, "and no status row holds it")
