extends GutTest

## The terrain bars (#1796): the block layout, the one label per element, the
## show gate, the live-only change signal, the band glow and the world-turn
## spread cue. Every expected number is computed from [TerrainRules] and the
## node's own T and cap — never a default.

var _w: TestWorld
var _hub: SkillNode  ## degree 3
var _leaf: SkillNode  ## degree 1
var _fire: Element
var _ice: Element
var _lightning: Element
var _worlds: Array[CombatWorld] = []


func before_each() -> void:
	CombatWorld.reset_live()
	_worlds = []
	_w = TestWorld.create(self)
	_hub = _w.add_node(&"Hub")
	_leaf = _w.add_node(&"Leaf")
	_w.link(_hub, _leaf)
	_w.link(_hub, _w.add_node(&"L2"))
	_w.link(_hub, _w.add_node(&"L3"))
	await get_tree().process_frame
	var roster := ElementRoster.shared()
	_fire = roster.by_id(&"fire")
	_ice = roster.by_id(&"ice")
	_lightning = roster.by_id(&"lightning")


func after_each() -> void:
	for w in _worlds:
		w.free_shadow()
	CombatWorld.reset_live()


func _label(n: SkillNode, e: Element, name: String) -> String:
	var c := n.get_combat()
	return "%s %d/%d" % [name, c.terrain_count(e), c.terrain_threshold()]


func _composite(n: SkillNode) -> Node2D:
	return n.get_node(^"Visuals/NodeVisualsComposite")


# ── 1. The layout ─────────────────────────────────────────────────────────

func test_layout_sweep_one_block_is_degree_stacks() -> void:
	var per := TerrainRules.shared().t_per_degree
	var bad: Array[String] = []
	for max_over in [0, 3]:
		for degree in range(1, 5):
			for k in range(2, 5):
				var t := per * degree
				var cap := k * t
				for count in range(0, cap + 5 * degree + 1):
					var l := TerrainBars.layout(count, degree, k, max_over)
					var over := ceili(float(count - cap) / degree) if count > cap else 0
					var got := [l.frame_blocks * degree, l.inert_blocks * degree,
							l.fill_blocks * degree, l.overflow_blocks]
					var want := [cap, t, float(mini(count, cap)), mini(over, max_over)]
					if not (got[0] == want[0] and got[1] == want[1]
							and is_equal_approx(got[2], want[2]) and got[3] == want[3]):
						bad.append("count %d degree %d k %d max %d: %s != %s"
								% [count, degree, k, max_over, got, want])
	assert_eq(bad, [] as Array[String], "frame = cap, inert = T, fill = count/degree, tail = ceil(past cap/degree) capped")


func test_a_leaf_counts_stacks_exactly() -> void:
	var per := TerrainRules.shared().t_per_degree
	for count in range(0, 4 * per + 1):
		assert_eq(TerrainBars.layout(count, 1, 4, 3).fill_blocks, float(count))


func test_the_sign_of_t_picks_fire_or_ice() -> void:
	assert_ne(_fire.identity.tint, _ice.identity.tint, "precondition: red and blue differ")
	assert_eq(TerrainBars.temperature_element(1), _fire)
	assert_eq(TerrainBars.temperature_element(-1), _ice)
	assert_null(TerrainBars.temperature_element(0))
	var c := _hub.get_combat()
	c.add_terrain(_ice, 2)
	var bars := TerrainBars.bars_for(_hub, 3)
	assert_eq(bars.size(), 1)
	if bars.size() == 1:
		assert_eq(bars[0].element, _ice)
		assert_eq(bars[0].color, _ice.identity.tint, "cold paints the bar blue")
	c.add_terrain(_fire, 4)
	bars = TerrainBars.bars_for(_hub, 3)
	if bars.size() == 1:
		assert_eq(bars[0].color, _fire.identity.tint, "the sign flips it red")


# ── 2. The label ──────────────────────────────────────────────────────────

func test_heat_reads_heat_burning_blaze_inferno() -> void:
	_hub.stake_level = 2
	var c := _hub.get_combat()
	var t := c.terrain_threshold()
	var cap := c.terrain_cap()
	assert_gt(cap, 2 * t + 1, "precondition: the blaze name has room below the cap")
	var primed := _fire.bands[0]
	var burning := primed.identity.noun
	var blaze: String = primed.excess_names.get(2, "")
	var inferno: String = primed.excess_names.get(ElementBand.EXCESS_AT_CAP, "")
	assert_false(blaze.is_empty(), "fire.tres authors the blaze name past 2 × T")
	assert_false(inferno.is_empty(), "fire.tres authors the inferno name past the cap")
	c.add_terrain(_fire, t)
	assert_eq(TerrainBars.label_for(_hub, _fire), _label(_hub, _fire, _fire.terrain.display_name), "at T: the StatusDef's name")
	c.add_terrain(_fire, 1)
	assert_eq(TerrainBars.label_for(_hub, _fire), _label(_hub, _fire, burning), "T + 1: Burning")
	c.add_terrain(_fire, 2 * t - c.terrain_count(_fire))
	assert_eq(TerrainBars.label_for(_hub, _fire), _label(_hub, _fire, burning), "2T: still Burning")
	c.add_terrain(_fire, 1)
	assert_eq(TerrainBars.label_for(_hub, _fire), _label(_hub, _fire, blaze), "past 2T: the blaze name")
	c.add_terrain(_fire, cap - c.terrain_count(_fire))
	assert_eq(TerrainBars.label_for(_hub, _fire), _label(_hub, _fire, blaze), "the cap: still blaze")
	c.add_terrain(_fire, 1)
	assert_eq(TerrainBars.label_for(_hub, _fire), _label(_hub, _fire, inferno), "past the cap: the inferno name")
	assert_eq(TerrainBars.shown_band(_fire, c.terrain_band(_fire)), primed,
			"the overflow band has no Identity: it shows as Burning (colour, icon)")


func test_cold_reads_frozen_then_deep_freeze() -> void:
	var c := _hub.get_combat()
	var t := c.terrain_threshold()
	var cap := c.terrain_cap()
	c.add_terrain(_ice, t + 1)
	assert_eq(TerrainBars.label_for(_hub, _ice), _label(_hub, _ice, _ice.bands[0].identity.noun))
	c.add_terrain(_ice, cap - t)
	assert_eq(c.terrain_band(_ice), _ice.bands[_ice.bands.size() - 1], "precondition: past the cap")
	assert_eq(TerrainBars.label_for(_hub, _ice), _label(_hub, _ice, _ice.bands[_ice.bands.size() - 1].identity.noun),
			"Deep freeze has an Identity of its own")


func test_charge_reads_shocked_past_t_and_past_the_cap() -> void:
	var c := _hub.get_combat()
	var t := c.terrain_threshold()
	var cap := c.terrain_cap()
	var shocked := _lightning.bands[0].identity.noun
	c.add_terrain(_lightning, t)
	assert_eq(TerrainBars.label_for(_hub, _lightning), _label(_hub, _lightning, _lightning.terrain.display_name))
	c.add_terrain(_lightning, 1)
	assert_eq(TerrainBars.label_for(_hub, _lightning), _label(_hub, _lightning, shocked))
	c.add_terrain(_lightning, cap - t)
	assert_eq(TerrainBars.label_for(_hub, _lightning), _label(_hub, _lightning, shocked), "the overflow band reads Shocked")


func test_one_label_per_element() -> void:
	var c := _hub.get_combat()
	c.add_terrain(_fire, c.terrain_cap() + 1)
	c.add_terrain(_lightning, c.terrain_threshold() + 1)
	var bars := TerrainBars.bars_for(_hub, 3)
	var labels := {}
	for b in bars:
		labels[b.element] = labels.get(b.element, 0) + 1
	assert_eq(labels, {_fire: 1, _lightning: 1}, "one entry per nonzero element, updated in place")
	for b in bars:
		assert_eq(b.label, TerrainBars.label_for(_hub, b.element), "the bar's label is the one name read")


# ── 3. The show gate and the change signal ───────────────────────────────

func test_bars_show_on_hover_and_pin_on_an_unowned_node() -> void:
	assert_false(_leaf.is_allocated(), "precondition: unowned")
	var bars := _leaf.terrain_bars
	assert_false(bars.is_shown())
	_leaf.hover_changed.emit(true)
	assert_true(bars.is_shown(), "hover shows")
	_leaf.hover_changed.emit(false)
	assert_false(bars.is_shown(), "unhover hides")
	_leaf.pin_health_bar = true
	assert_true(bars.is_shown(), "the bench pin shows")


func test_a_live_write_that_moves_an_int_emits_one_terrain_changed() -> void:
	var c := _leaf.get_combat()
	watch_signals(_leaf)
	c.add_terrain(_fire, c.terrain_threshold() + 1)
	assert_signal_emit_count(_leaf, "terrain_changed", 1, "one per call, band crossing or not")
	c.add_terrain(_lightning, -1)
	assert_signal_emit_count(_leaf, "terrain_changed", 1, "Charge already at 0 written down: none")
	c.add_terrain(_lightning, 2)
	assert_signal_emit_count(_leaf, "terrain_changed", 2)


func test_a_shadow_write_emits_no_terrain_changed() -> void:
	var world := CombatWorld.shadow()
	_worlds.append(world)
	var shadow := _leaf.get_combat().snapshot(world)
	watch_signals(_leaf)
	shadow.add_terrain(_fire, 5)
	assert_signal_emit_count(_leaf, "terrain_changed", 0)


# ── 4. Frozen holding Charge ──────────────────────────────────────────────

func test_a_frozen_node_holding_charge_draws_both_bars() -> void:
	var c := _hub.get_combat()
	var t := c.terrain_threshold()
	c.add_terrain(_ice, t + 1)
	c.add_terrain(_lightning, 2)
	assert_eq(c.terrain_band(_ice), _ice.bands[0], "precondition: Frozen")
	var bars := TerrainBars.bars_for(_hub, 3)
	assert_eq(bars.size(), 2, "both bars draw")
	for b in bars:
		if b.element == _lightning:
			var degree := _hub.get_graph_degree(_hub.get_graph())
			assert_almost_eq(b.layout.fill_blocks * degree, 2.0, 0.0001, "the Charge count stays readable")
			assert_eq(b.label, _label(_hub, _lightning, _lightning.terrain.display_name))


# ── 6. The band glow ──────────────────────────────────────────────────────

func test_a_band_crossing_sets_the_glow_and_keeps_the_status_tint() -> void:
	var comp := _composite(_hub)
	comp.set_status_tint(Color(0.5, 0.8, 0.3), 1.0)
	var status: Color = comp.status_tint
	var c := _hub.get_combat()
	var t := c.terrain_threshold()
	var tint := _fire.identity.tint
	assert_eq(comp.terrain_glow(false), Color.WHITE, "precondition: no glow")
	c.add_terrain(_fire, t + 1)
	assert_eq(comp.terrain_glow(false), Emissive.at(tint, Emissive.stops(comp.terrain_primed_tier)), "primed tier")
	assert_eq(comp.status_tint, status)
	c.add_terrain(_fire, c.terrain_cap() - t)
	assert_eq(comp.terrain_glow(false), Emissive.at(tint, Emissive.stops(comp.terrain_overflow_tier)), "at-cap tier")
	assert_eq(comp.status_tint, status)
	c.add_terrain(_fire, -c.terrain_count(_fire))
	assert_eq(comp.terrain_glow(false), Color.WHITE, "below T restores it")
	assert_eq(comp.status_tint, status, "the status tint survives both")


func test_two_bands_at_once_hold_both_glows() -> void:
	var comp := _composite(_hub)
	var c := _hub.get_combat()
	var t := c.terrain_threshold()
	c.add_terrain(_ice, t + 1)
	c.add_terrain(_lightning, t + 1)
	var cold: Color = Emissive.at(_ice.identity.tint, Emissive.stops(comp.terrain_primed_tier))
	var charge: Color = Emissive.at(_lightning.identity.tint, Emissive.stops(comp.terrain_primed_tier))
	assert_eq(comp.terrain_glow(false), cold)
	assert_eq(comp.terrain_glow(true), charge)
	assert_eq(comp.modulate, comp.feedback_tint * comp.status_tint * comp.subtype_tint * cold * charge,
			"both glows compose into the one modulate")


# ── 7's mechanism: the world-turn signal and the spread cue ──────────────

func test_a_world_turn_emits_terrain_settled_once_with_each_changed_node_once() -> void:
	var c := _hub.get_combat()
	c.add_terrain(_fire, 3 * c.terrain_threshold())
	var world := CombatWorld.live()
	watch_signals(world)
	world.flow_temperature(1)
	assert_signal_emit_count(world, "terrain_settled", 1)
	var params = get_signal_parameters(world, "terrain_settled")
	var changed: Array = params[0] if params != null else []
	assert_eq(changed.count(c), 1, "the hub, once: diffusion and decay both moved it")
	assert_eq(changed.count(_leaf.get_combat()), 1, "heat reached the leaf")


func test_the_spread_cue_flashes_changed_nodes_and_fades() -> void:
	var far := _w.add_node(&"Far")
	await get_tree().process_frame
	for n in [_hub, _leaf, far]:
		n.terrain_bars.clock.manual = true
	var c := _hub.get_combat()
	c.add_terrain(_fire, 3 * c.terrain_threshold())
	CombatWorld.live().flow_temperature(1)
	assert_true(_leaf.terrain_bars.is_shown(), "a changed node's bars flash")
	assert_false(far.terrain_bars.is_shown(), "an unchanged node's do not")
	_leaf.terrain_bars.clock.advance(30.0)
	assert_false(_leaf.terrain_bars.is_shown(), "the flash fades out")
