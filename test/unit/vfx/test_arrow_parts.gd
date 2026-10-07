extends GutTest

## The arrow-look kit (#1474): a [StatusArrow] drives every [ArrowPart] child
## through one lifecycle — launch, stop at arrival, the impact with its
## [ArrowImpactContext], the dud and absorb beats — and [ArrowVolleyCoordinator]
## builds that context from the landing's own hits.

const _STATUS_ARROW := preload("res://ui/vfx/projectile/visual/status_arrow.tscn")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _GRAPH_SCENE := preload("res://graph/graph.tscn")
const _TINT := Color(0.3, 0.9, 0.2, 1.0)
const _STUB_DRAIN := 7.5


class StubPart extends ArrowPart:
	var launched := 0
	var stopped := 0
	var arrivals: Array[ArrowImpactContext] = []
	var last_dud := false
	var last_absorbed := false

	func paint(tint: Color, dud: bool, absorbed: bool) -> void:
		super.paint(tint, dud, absorbed)
		last_dud = dud
		last_absorbed = absorbed

	func launch() -> void:
		launched += 1

	func arrive(ctx: ArrowImpactContext) -> void:
		arrivals.append(ctx)

	func stop() -> void:
		stopped += 1

	func drain_seconds() -> float:
		return _STUB_DRAIN


func _arrow(tint: Color = _TINT) -> Array:
	var arrow: StatusArrow = _STATUS_ARROW.instantiate()
	var stub := StubPart.new()
	arrow.add_child(stub)
	add_child_autofree(arrow)
	arrow.status_tint = tint
	return [arrow, stub]


func test_launch_arrival_and_impact_are_forwarded_with_the_context() -> void:
	var pair := _arrow()
	var arrow: StatusArrow = pair[0]
	var stub: StubPart = pair[1]
	arrow._on_launch()
	assert_eq(stub.launched, 1, "launch reaches the part")
	arrow._on_arrival()
	assert_eq(stub.stopped, 1, "arrival stops the part")
	var ctx := ArrowImpactContext.new()
	arrow._on_impact(ctx)
	assert_eq(stub.arrivals.size(), 1, "the impact reaches the part")
	assert_same(stub.arrivals[0] if not stub.arrivals.is_empty() else null, ctx,
			"with the coordinator's own context")


func test_drain_is_the_longest_parts() -> void:
	var arrow: StatusArrow = _arrow()[0]
	assert_almost_eq(arrow.drain_seconds(), _STUB_DRAIN, 0.0001, "the longest-lived part sets the drain")


func test_a_dud_is_forwarded_and_never_plays_an_impact() -> void:
	var pair := _arrow()
	var arrow: StatusArrow = pair[0]
	var stub: StubPart = pair[1]
	arrow._on_launch()
	arrow._on_arrival()
	arrow._on_dud()
	assert_true(stub.last_dud, "the part repaints as a dud")
	assert_gt(stub.stopped, 0, "a dud stops the part")
	arrow._on_impact(ArrowImpactContext.new())
	assert_eq(stub.arrivals.size(), 0, "a dud never plays an impact")


func test_an_absorbed_shot_hides_the_status_parts_and_plays_no_impact() -> void:
	var pair := _arrow()
	var arrow: StatusArrow = pair[0]
	var stub: StubPart = pair[1]
	arrow._on_launch()
	arrow._on_arrival()
	assert_true(stub.visible, "precondition: a status part shows")
	arrow._on_absorbed(false)
	assert_true(stub.last_absorbed, "the part repaints as absorbed")
	assert_false(stub.visible, "an absorbed shot hides the status parts")
	arrow._on_impact(ArrowImpactContext.new())
	assert_eq(stub.arrivals.size(), 0, "and plays no status impact")


func test_no_status_hides_and_never_launches_the_parts() -> void:
	var pair := _arrow(Color(0, 0, 0, 0))
	var arrow: StatusArrow = pair[0]
	var stub: StubPart = pair[1]
	assert_false(stub.visible, "a plain arrow shows no status part")
	arrow._on_launch()
	assert_eq(stub.launched, 0, "and launches none")


func test_the_coordinator_hands_only_this_arrows_non_dud_rider_targets() -> void:
	var graph: Graph = _GRAPH_SCENE.instantiate()
	add_child_autofree(graph)
	var nodes: Array[SkillNode] = []
	for p in [Vector2(0, 0), Vector2(300, 0), Vector2(300, 200), Vector2(600, 0)]:
		var n := _SKILL_NODE_SCENE.instantiate() as SkillNode
		graph.add_skill_node(n)
		n.global_position = p
		nodes.append(n)
	var origin := nodes[0]
	var target := nodes[1]
	var arrow := DamageInstance.new()
	arrow.origin = origin
	arrow.target = target
	var landed := StatusInstance.new()
	landed.target = nodes[2]
	var dud := StatusInstance.new()
	dud.target = nodes[3]
	dud.gated = true
	var next_arrow := DamageInstance.new()
	next_arrow.origin = origin
	next_arrow.target = target
	var next_rider := StatusInstance.new()
	next_rider.target = nodes[3]
	var hits: Array[HitInstance] = [arrow, landed, dud, next_arrow, next_rider]
	var coord := ArrowVolleyCoordinator.new()
	add_child_autofree(coord)
	var ctx := coord.impact_context_for(hits, 0)
	assert_not_null(ctx, "the coordinator builds a context")
	if ctx == null:
		return
	assert_eq(ctx.position, target.global_position, "the impact is at the target")
	assert_almost_eq(ctx.radius, target.radius, 0.0001, "with the target's radius")
	assert_eq(ctx.rider_positions, PackedVector2Array([nodes[2].global_position]),
			"exactly this arrow's non-dud riders' targets")
	var bare := coord.impact_context_for(hits, 3)
	assert_eq(bare.rider_positions, PackedVector2Array([nodes[3].global_position]),
			"the next arrow's riders are its own")


func test_impact_emitter_delay_holds_the_burst_and_grows_the_drain() -> void:
	var burst: ArrowImpactEmitter = autofree(load("res://ui/vfx/projectile/visual/arrow_parts/arrow_impact_emitter.tscn").instantiate())
	add_child(burst)
	var base := burst.drain_seconds()
	burst.set("delay", 0.2)
	assert_almost_eq(burst.drain_seconds(), base + 0.2, 0.001, "drain grows by the delay")
	burst.arrive(ArrowImpactContext.new())
	assert_false(burst.particles().emitting, "held until the delay elapses")
	await get_tree().create_timer(0.5).timeout
	assert_true(burst.particles().emitting, "bursts once the delay elapsed")


func test_impact_emitter_stop_cancels_a_pending_burst() -> void:
	var burst: ArrowImpactEmitter = autofree(load("res://ui/vfx/projectile/visual/arrow_parts/arrow_impact_emitter.tscn").instantiate())
	add_child(burst)
	burst.set("delay", 0.2)
	burst.arrive(ArrowImpactContext.new())
	burst.stop()
	await get_tree().create_timer(0.5).timeout
	assert_false(burst.particles().emitting, "stop cancelled the pending burst")
