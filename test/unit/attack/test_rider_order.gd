extends GutTest

## Within a beat (a run of equal structural_key) every hit's damage lands
## first, then every aspect rider, in every mode: a curse floor, a sunder or a
## mark lifts the NEXT beat's hits, never its own, and a node its beat's damage
## depletes takes none of them (ADR 0092). Damage-shaped riders (paired damage,
## splash copies, blast, detonate, cures) land after their hit in list order.
## The hit's land veto is a separate, memoized step the first asker decides
## ([method HitInstance.resolve_gate]). ADR 0067 §2.

const _CURSE := &"curse"
const _MARK := &"mark"
const _POISON_ID := &"poison"
const _SUNDER := &"sunder"
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


func test_a_curse_arrow_deals_the_old_floor_and_lifts_the_next_arrows() -> void:
	await _volley_fixture(100.0)
	_f.attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var outcome := _volley_in({_CURSE: 1, &"arrow": 1}, CombatWorld.live())
	var arrow := _arrow_of(outcome, _CURSE)
	var curse := _status_of(outcome, arrow)
	var next := _arrow_of(outcome, &"arrow")
	assert_not_null(curse, "fixture: the curse arrow carries a status rider")
	assert_gt(_land_index(outcome, curse), _land_index(outcome, arrow),
		"the curse lands after its own arrow")
	assert_lt(_land_index(outcome, curse), _land_index(outcome, next),
		"fixture: the plain arrow lands behind the curse")
	var floor_now: float = _f.target.get_local_value(&"min_damage_taken")
	assert_gt(floor_now, _FLOOR, "fixture: the curse raised the floor")
	assert_almost_eq(arrow.effective_amount, _FLOOR, 0.001,
		"the curse arrow deals the floor as it stood, dealt %s" % arrow.effective_amount)
	assert_true(next.effective_amount >= floor_now,
		"the next arrow deals at least the raised floor %s, dealt %s" % [floor_now, next.effective_amount])


func test_a_sunder_arrow_is_cut_by_the_armor_as_it_stood() -> void:
	await _volley_fixture(20.0, 40.0)
	_f.attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var broke_world := CombatWorld.shadow()
	var broke := _arrow_of(_volley_in({_SUNDER: 1}, broke_world), _SUNDER)
	var ammo := (broke as RangedDamageFormula.RangedHitInstance).ammo_type
	var effects := ammo.on_hit_effects
	ammo.on_hit_effects = [] as Array[OnHitEffect]
	var bare_world := CombatWorld.shadow()
	var bare := _arrow_of(_volley_in({_SUNDER: 1}, bare_world), _SUNDER)
	ammo.on_hit_effects = effects
	assert_almost_eq(broke.effective_amount, bare.effective_amount, 0.001,
		"the sunder lands after its own arrow, which meets the armor as it stood")
	assert_gt(broke_world.combat_for(_f.target).get_status_power(_SUNDER), 0.0,
		"fixture: the shred still lands, after")
	broke_world.free_shadow()
	bare_world.free_shadow()


## The target an earlier arrow of the volley freed (forced here, as that
## arrow's cascade would): the poison arrow is vetoed and its status, landing
## after it, duds.
func test_a_vetoed_arrows_status_lands_after_it_as_a_dud() -> void:
	await _volley_fixture(0.0)
	var poison := RangedDamageFormula.compute(_f.attacker, _f.leaves[1], _f.target,
			load("res://attack/ammo/types/poison.tres") as AmmoType)
	var outcome := AttackOutcome.new()
	outcome.hits.append(poison)
	RangedDamageFormula.ride(poison, outcome.hits)
	var status := _status_of(outcome, poison)
	assert_not_null(status, "fixture: the poison arrow carries its status")
	assert_gt(outcome.hits.find(status), outcome.hits.find(poison), "placed after its arrow")
	_f.alloc.force_deallocate(_f.target)
	outcome.crit_stream = CritRoll.stream_for(1)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_true(poison.gated, "the arrow is vetoed")
	assert_true(status.gated, "its status is a dud")
	assert_eq(status.power, 0.0)


func test_a_mark_rider_lifts_the_next_arrow_never_its_own() -> void:
	await _volley_fixture(100.0)
	_f.attacker.stat_board.get_stat(&"crit_chance").base_value = 0.0
	var world := CombatWorld.shadow()
	var outcome := _volley_in({_MARK: 1, &"arrow": 1}, world)
	var arrow := _arrow_of(outcome, _MARK)
	var mark := _status_of(outcome, arrow)
	var next := _arrow_of(outcome, &"arrow")
	assert_gt(_land_index(outcome, mark), _land_index(outcome, arrow), "the mark lands after its own arrow")
	assert_false(arrow.is_crit, "its own arrow drew before it landed")
	assert_lt(_land_index(outcome, arrow), _land_index(outcome, next),
		"fixture: the plain arrow lands behind the mark")
	assert_gt(CritRoll.chance_for(next, world), 0.0, "the arrow behind the mark reads it")
	world.free_shadow()


func test_a_record_replays_the_damage_first_order_and_the_same_totals() -> void:
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
			> a.find(_arrow_of(outcome, _CURSE)), "the arrow's damage leads its status in the authority's beat")
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


func test_a_toxic_vertexs_status_lands_after_its_contact() -> void:
	var outcome: AttackOutcome = await _swing([_poison_rider()] as Array[OnHitEffect])
	var checked := 0
	for hit in outcome.hits:
		if hit is StatusInstance and hit.paired != null:
			assert_gt(_land_index(outcome, hit), _land_index(outcome, hit.paired),
				"the status lands after its contact")
			checked += 1
	assert_gt(checked, 0, "fixture: the tip's contact carries a status")


## Unit level, against [BladePopResolver.LiveGate] directly (test_spike_pop.gd's
## shape): a contact's gate, and the status the landing places after it.
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
	# The order the landing builder places: the status after its contact.
	landing.place()
	return outcome


func test_a_spike_refused_contacts_status_is_a_dud_and_it_pops_once() -> void:
	var fx: Dictionary = await _gate_fixture()
	var outcome := _contact_with_status(fx.gate, fx.spiked)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	var status := outcome.hits[1] as StatusInstance
	assert_true(status.gated, "the refused contact's status is a dud")
	assert_eq(status.power, 0.0)
	assert_eq((fx.gate as BladePopResolver.LiveGate).result.pops.size(), 1, "the spikes pop once")
	assert_eq(outcome.hits[0].popped_vertex, fx.spiked, "the contact carries the pop")


func test_an_admitted_contacts_status_lands_after_it() -> void:
	var fx: Dictionary = await _gate_fixture()
	var outcome := _contact_with_status(fx.gate, fx.plain)
	OutcomeApplier.apply(outcome, CombatWorld.live())
	assert_true(outcome.hits[0] is BladeDamageInstance, "the contact is placed first")
	var status := outcome.hits[1] as StatusInstance
	assert_false(status.gated, "the contact's gate admitted, so its status lands")
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


## An infusion's status is listed ahead of the spell's own hit at its hop (a
## bare status keeps its ADR 0067 slot) and lands after it: one hop is one
## beat, and the drain holds the beat's aspect riders behind its damage
## (ADR 0092).
func test_an_infusion_status_is_listed_first_and_lands_after_the_spells_own_hit() -> void:
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
	assert_lt(status_at, own_at, "listed ahead of the spell's own hit")
	if status_at < 0 or own_at < 0:
		return
	var status := outcome.hits[status_at]
	var own := outcome.hits[own_at]
	assert_eq(status.structural_key, own.structural_key, "one hop, one beat")
	assert_true(status.is_aspect_rider(), "the infusion status is held behind the beat")
	assert_false(own.is_aspect_rider(), "the spell's own hit is not, so it lands first")


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


# ── Beat order and the depleted skip (ADR 0092) ─────────────────────────────

const _CURSE_DEF := preload("res://effects/status/curse.tres")


## A damage that notes its landing in [member seen], then lands as itself.
class _SeenDamage extends DamageInstance:
	var seen: Array = []

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		seen.append(self)
		super.land_on(node, world)


class _SeenHeal extends HealInstance:
	var seen: Array = []

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		seen.append(self)
		super.land_on(node, world)


class _SeenStatus extends StatusInstance:
	var seen: Array = []

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		seen.append(self)
		super.land_on(node, world)


var _h: SpellTestHelper
var _g: Graph
var _n: Array = []
var _caster: Entity
var _foe: Entity


## The caster on node 0; the foe's core on 2, its plain nodes 1 and 3 behind
## node 1, both at armor 100 over a floor of [constant _FLOOR].
func _beat_fixture() -> void:
	_h = SpellTestHelper.new()
	_g = _h.make_graph([[0, 1], [1, 2], [1, 3]], self)
	_caster = _h.make_entity(_g, "A", Color.RED)
	_foe = _h.make_entity(_g, "D", Color.BLUE)
	_h.give_big_hp(_foe)
	_h.assign_owner(_g, _caster, [0])
	_h.assign_owner(_g, _foe, [2, 1, 3])
	_n = _g.get_skill_nodes()
	for node: SkillNode in [_n[1], _n[3]]:
		VolleyBoardFixture.set_stat(node, &"armor", 100.0 - node.get_local_value(&"armor"),
				StatModifier.Operation.ADD_BASE)
		VolleyBoardFixture.set_stat(node, &"min_damage_taken",
				_FLOOR - node.get_local_value(&"min_damage_taken"), StatModifier.Operation.ADD_BASE)


func _seen_damage(seen: Array, key: float) -> _SeenDamage:
	var hit := _SeenDamage.new()
	hit.seen = seen
	hit.amount = 3.0
	hit.target = _n[1]
	hit.attacker = _caster
	hit.structural_key = key
	return hit


## A curse rider on [param lead], stamped the way an [ApplyStatusEffect] stamps it.
func _seen_curse(seen: Array, lead: HitInstance, hits: Array[HitInstance]) -> _SeenStatus:
	var curse := _SeenStatus.new()
	curse.seen = seen
	StatusInstance.stamp_landing(curse, _CURSE_DEF, HitLanding.riding(lead, hits))
	curse.power = 1.0
	hits.append(curse)
	return curse


## Landings A and B in one beat on one node, A carrying a curse and a bare
## heal listed between them, then C a beat later: the beat's damage and heal
## land in list order and the curse after all of them, so B meets the floor as
## it stood and C the raised one. A rebuilt record replays the same totals.
func test_a_beats_damage_lands_before_its_aspect_riders_and_the_next_beat_reads_them() -> void:
	_beat_fixture()
	var seen: Array = []
	var outcome := AttackOutcome.new()
	var a := _seen_damage(seen, 0.0)
	outcome.hits.append(a)
	var curse := _seen_curse(seen, a, outcome.hits)
	var heal := _SeenHeal.new()
	heal.seen = seen
	heal.amount = 1.0
	heal.target = _n[1]
	heal.attacker = _caster
	outcome.hits.append(heal)
	var b := _seen_damage(seen, 0.0)
	outcome.hits.append(b)
	var c := _seen_damage(seen, 1.0)
	outcome.hits.append(c)
	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	var names := {a: "A", curse: "curse", heal: "heal", b: "B", c: "C"}
	assert_eq(seen.map(func(h: HitInstance) -> String: return names[h]),
		["A", "heal", "B", "curse", "C"],
		"one beat: damage and heal in list order, then its aspect rider; then the next beat")
	assert_gt(world.combat_for(_n[1]).get_status_power(_CURSE), 0.0, "fixture: the curse landed")
	assert_almost_eq(b.effective_amount, a.effective_amount, 0.001,
		"B meets the floor as it stood before the beat")
	assert_gt(c.effective_amount, b.effective_amount, "the next beat's damage reads the curse")
	var twin := AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _g))), _g)
	var replay := CombatWorld.shadow()
	OutcomeApplier.apply(twin, replay)
	assert_eq(replay.combat_for(_n[1]).get_current_hp(), world.combat_for(_n[1]).get_current_hp(),
		"same HP after replay")
	assert_eq(replay.combat_for(_n[1]).get_status_power(_CURSE),
		world.combat_for(_n[1]).get_status_power(_CURSE), "same curse after replay")
	world.free_shadow()
	replay.free_shadow()


## A wave is one beat (magic's key is the hop): its two landings' damage lands
## before either curse, live through the resolver's wave drain and on a rebuilt
## record's replay alike, so every node ends on the same totals.
func test_a_spell_wave_lands_the_same_totals_live_and_on_replay() -> void:
	_beat_fixture()
	var curse := ApplyStatusEffect.new()
	curse.def = _CURSE_DEF
	curse.power = 1.0
	var config := _h.make_config(_h.fan_all(), _h.owner_enemy(), _h.sum_reducer(), {"max_hops": 1})
	var spell := _h.make_spell(config, [DamageEffect.new(), curse] as Array[OnHitEffect], 3.0)
	var authority := CombatWorld.shadow()
	var outcome := SpellResolver.resolve_against(spell, _n[1], _n[0], _caster, _g, authority)
	var wave := outcome.hits.filter(func(h: HitInstance) -> bool: return h.structural_key == 1.0)
	assert_eq(wave.size(), 4, "fixture: hop 1 lands a damage and a curse on nodes 2 and 3")
	var twin := AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _g))), _g)
	var replay := CombatWorld.shadow()
	OutcomeApplier.apply(twin, replay)
	for i in [1, 2, 3]:
		var node: SkillNode = _n[i]
		assert_eq(replay.combat_for(node).get_current_hp(), authority.combat_for(node).get_current_hp(),
			"node %d: the same HP after replay" % i)
		assert_eq(replay.combat_for(node).get_status_power(_CURSE),
			authority.combat_for(node).get_status_power(_CURSE), "node %d: the same curse after replay" % i)
	authority.free_shadow()
	replay.free_shadow()


## A TRUE hit of [param amount] on [param node] carrying a poison rider.
func _poisoned_hit(node: SkillNode, amount: float) -> AttackOutcome:
	var hit := DamageInstance.new()
	hit.amount = amount
	hit.type = DamageInstance.Type.TRUE
	hit.target = node
	hit.attacker = _caster
	var outcome := AttackOutcome.new()
	outcome.hits.append(hit)
	_poison_rider().apply(HitLanding.riding(hit, outcome.hits))
	return outcome


## A node its own beat's damage depletes takes none of that beat's aspect
## riders: the rider duds on the authority (gated, shipped as FLAG_GATED) and
## a rebuilt record replays the dud without reading HP.
func test_a_node_its_beat_depletes_takes_no_aspect_rider() -> void:
	_beat_fixture()
	var outcome := _poisoned_hit(_n[1], _n[1].get_combat().get_current_hp())
	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	var poison := outcome.hits[1] as StatusInstance
	assert_true(world.combat_for(_n[1]).get_current_hp() <= 0.0, "fixture: the hit depletes the node")
	assert_true(poison.gated, "the depleted node's rider is a dud")
	assert_eq(poison.power, 0.0)
	assert_eq(world.combat_for(_n[1]).get_status_power(_POISON_ID), 0.0, "no row")
	var twin := AttackRecord.rebuild(
			bytes_to_var(var_to_bytes(AttackRecord.capture(outcome, _g))), _g)
	var replay := CombatWorld.shadow()
	OutcomeApplier.apply(twin, replay)
	assert_true(twin.hits[1].gated, "the record ships the dud")
	assert_eq(replay.combat_for(_n[1]).get_status_power(_POISON_ID), 0.0, "the replay lands no row")
	world.free_shadow()
	replay.free_shadow()


func test_a_rider_on_a_hit_that_leaves_its_node_standing_lands_its_row() -> void:
	_beat_fixture()
	var outcome := _poisoned_hit(_n[1], 1.0)
	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	assert_false(outcome.hits[1].gated, "the node stands, so its rider lands")
	assert_gt(world.combat_for(_n[1]).get_status_power(_POISON_ID), 0.0)
	world.free_shadow()


## The depleted set is its beat's own: a later beat holding only a rider (a
## bare status, no damage of its own) is not dudded by an earlier beat's kill.
func test_a_rider_only_beat_is_not_dudded_by_an_earlier_beats_kill() -> void:
	_beat_fixture()
	var outcome := _poisoned_hit(_n[1], _n[1].get_combat().get_current_hp())
	var lead := DamageInstance.new()
	lead.target = _n[1]
	lead.attacker = _caster
	lead.structural_key = outcome.hits[0].structural_key + 1.0
	var scratch: Array[HitInstance] = [lead]
	_poison_rider().apply(HitLanding.riding(lead, scratch))
	var late := scratch[1] as StatusInstance
	late.paired = null
	outcome.hits.append(late)
	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	assert_true(outcome.hits[1].gated, "fixture: beat 1's own rider duds on the node it depleted")
	assert_false(late.gated, "beat 2 holds no damage, so beat 1's kill is not its")
	world.free_shadow()


## A cracked core is not depleted for the skip: it never emits `depleted`, and
## its rider still falls through to the entity (ADR 0066, unchanged).
func test_a_cracked_cores_rider_still_falls_through_to_the_entity() -> void:
	_beat_fixture()
	var core: SkillNode = _n[2]
	var outcome := _poisoned_hit(core, core.get_combat().get_current_hp())
	var world := CombatWorld.shadow()
	OutcomeApplier.apply(outcome, world)
	var poison := outcome.hits[1] as StatusInstance
	assert_true(world.combat_for(core).get_current_hp() <= 0.0, "fixture: the core cracks")
	assert_false(poison.gated, "a cracked core is not depleted for the skip")
	assert_eq(poison.host_kind, StatusInstance.HostKind.ENTITY, "its rider falls through to the entity")
	assert_gt(poison.power, 0.0)
	world.free_shadow()
