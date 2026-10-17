extends GutTest

## A status rider lands BEFORE its paired hit, in every mode, so a curse
## floor, an armor break or a hex lifts its own hit; damage-shaped riders
## (paired damage, splash copies, blast, detonate, cures) stay after it. The
## hit's land veto is a separate, memoized step the first asker decides
## ([method HitInstance.resolve_gate]). ADR 0067.

const _CURSE := &"curse"
const _HEX := &"hex"
const _POISON_ID := &"poison"
const _ARMOR_BREAK := &"armor_break"
const _FLOOR := 1.0

const _BOARD := preload("res://entity/default_entity_board.tres")
const _SKILL_NODE_SCENE := preload("res://skill_node/skill_node.tscn")
const _POISON := preload("res://effects/status/poison.tres")
const _BARE_SCENE := preload("res://test/support/addons/bare_addon.tscn")
const _CLAMP_SCENE := preload("res://skill_node/addons/defs/clamp_addon.tscn")
const _SPIKE_SCENE := preload("res://skill_node/addons/defs/spike_ring_addon.tscn")
const _VENOM: SpellDef = preload("res://attack/spell/defs/venom_burst.tres")
const _HEALING_BEAM: SpellDef = preload("res://attack/spell/defs/healing_beam.tres")
const _SPACING := 150.0
const _TURNS := 0.15


# ── Ranged ───────────────────────────────────────────────────────────────────

var _f: VolleyBoardFixture


func _volley_fixture(armor: float, damage := 3.0) -> void:
	_f = await VolleyBoardFixture.build(self, true)
	for leaf in _f.leaves:
		VolleyBoardFixture.set_stat(leaf, &"ranged_damage", damage)
	VolleyBoardFixture.set_stat(_f.target, &"armor",
			armor - _f.target.get_local_value(&"armor"), StatModifier.Operation.ADD_BASE)
	VolleyBoardFixture.set_stat(_f.target, &"min_damage_taken",
			_FLOOR - _f.target.get_local_value(&"min_damage_taken"), StatModifier.Operation.ADD_BASE)


func _volley_in(counts: Dictionary, world: CombatWorld) -> AttackOutcome:
	for id in counts:
		_f.attacker.stat_board.arrows.add(id, counts[id])
	var p := RangedAttackPlan.new()
	autofree(p)
	p.attacker = _f.attacker
	p.set_target(_f.target)
	for id in counts:
		p.ammo.append({"type": StringName(id), "count": int(counts[id])})
	return p.resolve_against(world)


func _arrow_of(outcome: AttackOutcome, ammo: StringName) -> HitInstance:
	for hit in outcome.hits:
		if hit.kind == HitInstance.Kind.DAMAGE and hit.ammo_type_id == ammo and hit.paired == null:
			return hit
	return null


func _status_of(outcome: AttackOutcome, paired: HitInstance) -> StatusInstance:
	for hit in outcome.hits:
		if hit is StatusInstance and hit.paired == paired:
			return hit
	return null


func _land_index(outcome: AttackOutcome, hit: HitInstance) -> int:
	return OutcomeApplier.in_arrival_order(outcome.hits).find(hit)


func test_a_curse_arrows_status_lands_before_it_and_lifts_its_own_floor() -> void:
	await _volley_fixture(100.0)
	var outcome := _volley_in({_CURSE: 1}, CombatWorld.live())
	var arrow := _arrow_of(outcome, _CURSE)
	var curse := _status_of(outcome, arrow)
	assert_not_null(curse, "fixture: the curse arrow carries a status rider")
	assert_lt(_land_index(outcome, curse), _land_index(outcome, arrow),
		"the curse lands before its own arrow")
	var floor_now: float = _f.target.get_local_value(&"min_damage_taken")
	assert_gt(floor_now, _FLOOR, "fixture: the curse raised the floor")
	assert_true(arrow.effective_amount >= floor_now,
		"the curse arrow deals at least its raised floor %s, dealt %s" % [floor_now, arrow.effective_amount])


func test_an_armor_break_arrow_reads_its_own_shred() -> void:
	await _volley_fixture(20.0, 40.0)
	var broke_world := CombatWorld.shadow()
	var broke := _arrow_of(_volley_in({_ARMOR_BREAK: 1}, broke_world), _ARMOR_BREAK)
	var ammo := (broke as RangedDamageFormula.RangedHitInstance).ammo_type
	var effects := ammo.on_hit_effects
	ammo.on_hit_effects = [] as Array[OnHitEffect]
	var bare_world := CombatWorld.shadow()
	var bare := _arrow_of(_volley_in({_ARMOR_BREAK: 1}, bare_world), _ARMOR_BREAK)
	ammo.on_hit_effects = effects
	assert_gt(broke.effective_amount, bare.effective_amount,
		"the armor break shreds before its own arrow lands")
	broke_world.free_shadow()
	bare_world.free_shadow()


## The target an earlier arrow of the volley freed (forced here, as that
## arrow's cascade would): the poison arrow's status, landing ahead of it,
## decides the arrow's veto and duds.
func test_a_vetoed_arrows_earlier_landing_status_is_a_dud() -> void:
	await _volley_fixture(0.0)
	var poison := RangedDamageFormula.compute(_f.attacker, _f.leaves[1], _f.target,
			load("res://attack/ammo/types/poison.tres") as AmmoType)
	var outcome := AttackOutcome.new()
	outcome.hits.append(poison)
	RangedDamageFormula.ride(poison, outcome.hits)
	var status := _status_of(outcome, poison)
	assert_not_null(status, "fixture: the poison arrow carries its status")
	assert_lt(outcome.hits.find(status), outcome.hits.find(poison), "placed ahead of its arrow")
	_f.alloc.force_deallocate(_f.target)
	outcome.crit_stream = CritRoll.stream_for(1)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_true(poison.gated, "the arrow is vetoed")
	assert_true(status.gated, "its earlier-landing status is a dud")
	assert_eq(status.power, 0.0)


func test_a_hex_rider_raises_its_own_arrows_crit_chance() -> void:
	await _volley_fixture(100.0)
	_f.attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var world := CombatWorld.shadow()
	var outcome := _volley_in({_HEX: 1}, world)
	var arrow := _arrow_of(outcome, _HEX)
	var hex := _status_of(outcome, arrow)
	assert_lt(_land_index(outcome, hex), _land_index(outcome, arrow), "the hex lands first")
	assert_true(arrow.is_crit or CritRoll.chance_for(arrow, world) > 0.0,
		"the hex was on the node when its own arrow drew its crit")
	world.free_shadow()


func test_a_record_replays_the_status_first_order_and_the_same_totals() -> void:
	await _volley_fixture(100.0)
	var authority := CombatWorld.shadow()
	var outcome := _volley_in({_CURSE: 1, &"arrow": 2}, authority)
	var wired: Dictionary = bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _f.graph)))
	var twin := AttackRecord.rebuild(wired, _f.graph)
	var a := OutcomeApplier.in_arrival_order(outcome.hits)
	var b := OutcomeApplier.in_arrival_order(twin.hits)
	assert_eq(b.size(), a.size())
	for i in mini(a.size(), b.size()):
		assert_eq(b[i].kind, a[i].kind, "row %d keeps its kind" % i)
		assert_eq(b[i].target, a[i].target, "row %d keeps its target" % i)
	assert_true(a.find(_status_of(outcome, _arrow_of(outcome, _CURSE))) \
			< a.find(_arrow_of(outcome, _CURSE)), "a status leads in the authority's beat")
	var replay := CombatWorld.shadow()
	OutcomeApplier.apply(twin, replay)
	assert_eq(replay.combat_for(_f.target).get_current_hp(),
			authority.combat_for(_f.target).get_current_hp(), "same HP after replay")
	assert_eq(replay.combat_for(_f.target).get_status_power(_CURSE),
			authority.combat_for(_f.target).get_status_power(_CURSE), "same curse after replay")
	authority.free_shadow()
	replay.free_shadow()


# ── Melee ────────────────────────────────────────────────────────────────────

var _graph: Graph
var _attacker: Entity
var _pivot: SkillNode
var _mid: SkillNode
var _tip: SkillNode
var _plate: SkillNode


func _spawn(nm: String, pos: Vector2) -> SkillNode:
	var sn := _SKILL_NODE_SCENE.instantiate() as SkillNode
	sn.name = nm
	_graph.add_skill_node(sn)
	sn.global_position = pos
	return sn


func _make_entity() -> Entity:
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = _BOARD.duplicate(true)
	entity.stat_board.get_stat(&"crit_chance").base_value = 0.0
	entity.turns_taken = 1
	_graph.add_child(entity)
	return entity


## test_temp_overlay_status_landing.gd's spine: pivot, mid, tip in a line,
## a hostile plate on the tip's arc; [param effects] ride the tip's contact.
func _swing(effects: Array[OnHitEffect]) -> AttackOutcome:
	_graph = TestWorld.create(self).graph
	_attacker = _make_entity()
	var defender := _make_entity()
	var camp_faction := Faction.new()
	camp_faction.id = &"rider_order_enemy"
	defender.faction = camp_faction
	_pivot = _spawn("Pivot", Vector2.ZERO)
	_mid = _spawn("Mid", Vector2(_SPACING, 0.0))
	_tip = _spawn("Tip", Vector2(_SPACING * 2.0, 0.0))
	_graph.add_edge(_pivot, _mid)
	_graph.add_edge(_mid, _tip)
	_plate = _spawn("Plate", Vector2.from_angle(_TURNS * TAU) * _SPACING * 2.0)
	await get_tree().process_frame
	var alloc := TestWorld.allocator_for(_graph)
	alloc.force_allocate(_attacker, _pivot)
	alloc.force_allocate(_attacker, _mid)
	alloc.force_allocate(_attacker, _tip)
	_attacker.core_location = _pivot
	var camp := _spawn("Camp", Vector2(-_SPACING * 4.0, _SPACING * 4.0))
	_graph.add_edge(camp, _plate)
	alloc.force_allocate(defender, camp)
	defender.core_location = camp
	alloc.force_allocate(defender, _plate)
	var sharp := StatModifier.new()
	sharp.stat_id = &"blade_damage"
	sharp.operation = StatModifier.Operation.ADD_BONUS
	sharp.value = 20.0
	_tip.add_local_modifier(sharp)
	_mid.add_child(_CLAMP_SCENE.instantiate())
	var addon := _BARE_SCENE.instantiate() as SkillNodeAddon
	addon.on_hit_effects = effects
	_tip.add_child(addon)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_plate.get_combat().refill(true)
	var plan := MeleeAttackPlan.new()
	plan.attacker = _attacker
	plan.source = _pivot
	plan.blade_nodes = [_mid, _tip]
	return plan.resolve_against(CombatWorld.live())


func _poison_rider() -> ApplyStatusEffect:
	var rider := ApplyStatusEffect.new()
	rider.def = _POISON
	rider.power = 1.0
	return rider


func test_a_toxic_vertexs_status_lands_before_its_contact() -> void:
	var outcome: AttackOutcome = await _swing([_poison_rider()] as Array[OnHitEffect])
	var checked := 0
	for hit in outcome.hits:
		if hit is StatusInstance and hit.paired != null:
			assert_lt(_land_index(outcome, hit), _land_index(outcome, hit.paired),
				"the status lands before its contact")
			checked += 1
	assert_gt(checked, 0, "fixture: the tip's contact carries a status")


func test_a_damage_rider_still_lands_after_its_contact_and_copies_its_crit() -> void:
	var paired := PairedDamageEffect.new()
	paired.fraction = 0.5
	var outcome: AttackOutcome = await _swing([_poison_rider(), paired] as Array[OnHitEffect])
	var checked := 0
	for hit in outcome.hits:
		if hit is PairedDamageInstance and hit.paired != null:
			assert_gt(_land_index(outcome, hit), _land_index(outcome, hit.paired),
				"a damage rider lands after its contact")
			assert_eq(hit.is_crit, hit.paired.is_crit, "and copies its crit")
			checked += 1
	assert_gt(checked, 0, "fixture: the tip's contact carries a paired damage rider")
	for hit in outcome.hits:
		if hit is StatusInstance and hit.paired != null:
			assert_lt(_land_index(outcome, hit), _land_index(outcome, hit.paired))


## Unit level, against [BladePopResolver.LiveGate] directly (test_spike_pop.gd's
## shape): a status ordered ahead of its contact decides the contact's gate.
func _gate_fixture() -> Dictionary:
	_graph = TestWorld.create(self).graph
	_attacker = _make_entity()
	var defender := _make_entity()
	var spiked := _spawn("Spiked", Vector2.ZERO)
	var plain := _spawn("Plain", Vector2(_SPACING, 0.0))
	await get_tree().process_frame
	var alloc := TestWorld.allocator_for(_graph)
	alloc.force_allocate(defender, spiked)
	alloc.force_allocate(defender, plain)
	var spike := _SPIKE_SCENE.instantiate() as SpikeRingAddon
	var mod := StatModifier.new()
	mod.stat_id = &"blade_damage"
	mod.operation = StatModifier.Operation.ADD_BONUS
	mod.value = 5.0
	spike.local_modifiers = [mod]
	spiked.add_child(spike)
	var positions: Array[Vector2] = [Vector2.ZERO, Vector2(50, 0), Vector2(100, 0)]
	var radii: Array[float] = [16.0, 16.0, 16.0]
	var edges: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2)]
	var gate := BladePopResolver.LiveGate.new(BladeState.build(positions, 0, edges, radii), _attacker)
	return {"gate": gate, "spiked": spiked, "plain": plain}


func _contact_with_status(gate: BladePopResolver.LiveGate, target: SkillNode) -> AttackOutcome:
	var di := BladeDamageInstance.new(BladeHitEvent.new(0.3, 1, -1, target), gate)
	di.amount = 1.0
	di.target = target
	di.attacker = _attacker
	var outcome := AttackOutcome.new()
	outcome.hits.append(di)
	var landing := HitLanding.riding(di, outcome.hits)
	_poison_rider().apply(landing)
	# The order the landing builder places: the status ahead of its contact.
	outcome.hits.reverse()
	return outcome


func test_a_spike_refused_contact_leaves_its_earlier_status_a_dud_and_pops_once() -> void:
	var fx: Dictionary = await _gate_fixture()
	var outcome := _contact_with_status(fx.gate, fx.spiked)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var status := outcome.hits[0] as StatusInstance
	assert_true(status.gated, "the refused contact's status is a dud")
	assert_eq(status.power, 0.0)
	assert_eq((fx.gate as BladePopResolver.LiveGate).result.pops.size(), 1, "the spikes pop once")
	assert_eq(outcome.hits[1].popped_vertex, fx.spiked, "the contact carries the pop")


func test_an_admitted_contacts_earlier_status_lands() -> void:
	var fx: Dictionary = await _gate_fixture()
	var outcome := _contact_with_status(fx.gate, fx.plain)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var status := outcome.hits[0] as StatusInstance
	assert_false(status.gated, "the status asked the gate, which admitted")
	assert_gt((fx.plain as SkillNode).get_combat().get_status_power(_POISON_ID), 0.0)


# ── Spell ────────────────────────────────────────────────────────────────────

func _cast(spell: SpellDef, infusion: Infusion, enemy: bool) -> Array:
	var h := SpellTestHelper.new()
	var graph := h.make_graph([[0, 1]], self)
	var atk := h.make_entity(graph, "A", Color.RED)
	var def := h.make_entity(graph, "D", Color.BLUE)
	h.give_big_hp(def)
	h.assign_owner(graph, atk, [0])
	h.assign_owner(graph, def if enemy else atk, [1])
	var n := graph.get_skill_nodes()
	return [n, SpellResolver.resolve(spell, n[1], n[0], atk, graph, null, infusion)]


func test_an_infusion_status_lands_before_the_spells_own_hits_at_its_hop() -> void:
	var r: Array = _cast(_VENOM, null, true)
	var outcome: AttackOutcome = r[1]
	var status_at := -1
	var own_at := -1
	for i in outcome.hits.size():
		var hit := outcome.hits[i]
		if hit.target != r[0][1]:
			continue
		if hit is StatusInstance and status_at < 0:
			status_at = i
		elif hit.kind == HitInstance.Kind.DAMAGE and own_at < 0:
			own_at = i
	assert_gt(status_at, -1, "fixture: venom's innate poison rides the seed")
	assert_gt(own_at, -1, "fixture: venom's burst hits the seed")
	assert_lt(status_at, own_at, "the infusion rider lands before the spell's own hit")


func test_a_heal_spells_rider_still_pairs_the_heal() -> void:
	var r: Array = _cast(_HEALING_BEAM, Infusion.for_cast(_HEALING_BEAM, {_POISON_ID: 2}), false)
	var outcome: AttackOutcome = r[1]
	var checked := 0
	for hit in outcome.hits:
		if hit is StatusInstance:
			assert_true(hit.paired is HealInstance, "the rider pairs the spell's heal")
			checked += 1
	if checked == 0:
		pending("healing beam takes no poison infusion here — pairing unexercised")
