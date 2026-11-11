class_name HitGather
extends RefCounted

## Stage one of the two-stage hit resolver (#1798; ADR 0082, ADR 0083 §1-§5,
## ADR 0086, ADR 0087, ADR 0091 §1): one beat's land-time gather.
## [method OutcomeApplier.drain] calls [method stage_one] once per
## `schedule_index` group (a beat), over the whole group, before any of it
## lands.
##
## A head ([member HitInstance.is_head]) and the hits after it, up to the next
## head, are one hit. The beat lands in generations: generation 0 is the beat's
## heads; a go-off fired at generation g's read sends its copies to g + 1, and
## each generation starts from the terrain the one before left. At each node of
## a generation, in order:
## [br]- [b]admit[/b]: every copy is asked of the node's bands' [Admits] against
##   the terrain before this generation's riders (a head and a centre copy never
##   are); an admitted copy is an entry, an absorbed one is not;
## [br]- [b]land[/b]: every arrival's element riders (Heat, Cold, Charge), absorbed
##   or not, once per node per hit: a head's own rows land through their own
##   [method StatusInstance.land_on] and are marked [member HitInstance.staged];
##   a copy's are ceil(r × s) of them, summed through [TerrainSettle] (the
##   larger ceil when two channels of one hit meet);
## [br]- [b]read[/b], once per node per hit: each band the node sits in after the
##   riders fires its [GoOff] ([method GoOff.fire]); the spends and transfers of
##   the whole generation commit together through [TerrainSettle], before the
##   next generation's admit.
## [br]The once-per-node set is the hit's: a node it already landed takes a later
## copy as an entry only, and does not go off again. Stage two is the drain:
## every entry is pushed onto the [HitQueue] as a copy of the hit's whole span
## (element riders excluded), [code]paired[/code] to its head, at damage × s +
## own damage and riders ceil(r × s), one row per status id.
##
## The gather is the beat's only terrain writer, and it records the beat's net
## change on its first head ([member HitInstance.terrain_ops]); a re-drained or
## rebuilt beat feeds that instead of gathering ([method feed]).


## One hit of the beat: its head, its span, its once-per-node set.
class _Hit:
	extends RefCounted
	var head: HitInstance = null
	## The whole hit, head first.
	var span: Array[HitInstance] = []
	## `Element -> int`: the stacks its own element riders landed.
	var terrain: Dictionary = {}
	## `SkillNode -> true`: the nodes this hit landed and read.
	var visited: Dictionary = {}


var _world: CombatWorld = null
var _hits: Dictionary = {}  # head HitInstance -> _Hit
var _slices: Dictionary = {}  # SkillNode -> NodeCombat (null: not a node slice)
var _pre: Dictionary = {}  # SkillNode -> [t, charge] before stage one touched it
var _entries: Array[Arrival] = []


## Stage one over one beat, [param group] in land order. Gathers every fresh
## head (marked, not yet [member HitInstance.gathered]); feeds every other hit's
## recorded [member HitInstance.terrain_ops]; pushes the entries onto
## [param queue].
static func stage_one(group: Array[HitInstance], world: CombatWorld, queue: HitQueue) -> void:
	if world == null:
		return
	var gather := HitGather.new()
	gather._world = world
	var order: Array[_Hit] = []
	var current: _Hit = null
	for hit in group:
		if hit == null:
			continue
		var fresh := hit.is_head and not hit.gathered
		if hit.is_head:
			current = null
		if not fresh and not hit.terrain_ops.is_empty():
			feed(hit, world)
		if fresh:
			hit.gathered = true
			current = _Hit.new()
			current.head = hit
			order.append(current)
			gather._hits[hit] = current
		if current != null:
			current.span.append(hit)
	if order.is_empty():
		return
	var arrivals: Array[Arrival] = []
	for h in order:
		var a := Arrival.new()
		a.node = h.head.target
		a.head = h.head
		arrivals.append(a)
	var generation := 0
	while not arrivals.is_empty():
		arrivals = gather._generation(arrivals, generation)
		generation += 1
	order[0].head.terrain_ops = gather._ops()
	gather._push(queue)


## Land [param hit]'s recorded stage-one terrain on [param world]: the replay
## of a gather, never a second one.
static func feed(hit: HitInstance, world: CombatWorld) -> void:
	var heat := TerrainSettle.element_on(Terrain.Axis.HEAT)
	var charge := TerrainSettle.element_on(Terrain.Axis.CHARGE)
	for op: Array in hit.terrain_ops:
		var node: SkillNode = op[0]
		if node == null or not is_instance_valid(node):
			continue
		var slice := world.combat_for(node) as NodeCombat
		if slice == null:
			continue
		slice.add_terrain(heat, int(op[1]))
		slice.add_terrain(charge, int(op[2]))


func _generation(arrivals: Array[Arrival], generation: int) -> Array[Arrival]:
	var nodes: Array[SkillNode] = []
	var at: Dictionary = {}  # SkillNode -> Array of the Arrivals there
	for a in arrivals:
		if a.node == null or not is_instance_valid(a.node) or _slice(a.node) == null:
			continue
		if not at.has(a.node):
			at[a.node] = []
			nodes.append(a.node)
		at[a.node].append(a)
	# Admit, against the terrain this generation starts from.
	for node in nodes:
		var before := TerrainRead.of(_slice(node), node)
		for a: Arrival in at[node]:
			if a.is_copy and _admits(node, before, a):
				_entries.append(a)
	# Land every arrival's element riders, absorbed or not.
	var batch := TerrainSettle.Batch.new()
	var reading: Dictionary = {}  # SkillNode -> Array of the _Hits read there
	for node in nodes:
		var landing: Array = []
		var best: Dictionary = {}  # _Hit -> {Element: int}
		for a: Arrival in at[node]:
			var h: _Hit = _hits[a.head]
			if h.visited.has(node):
				continue
			if not landing.has(h):
				landing.append(h)
			if not a.is_copy:
				_land_riders(h)
				continue
			if not best.has(h):
				best[h] = {}
			var stacks: Dictionary = best[h]
			for e: Element in h.terrain:
				stacks[e] = maxi(int(stacks.get(e, 0)), _scaled(int(h.terrain[e]), a.share))
		for h: _Hit in best:
			for e: Element in best[h]:
				_add(batch, node, e, int(best[h][e]))
		for h: _Hit in landing:
			h.visited[node] = true
		reading[node] = landing
	TerrainSettle.commit(batch)
	# Read once per node per hit; every spend of the generation commits together.
	var spends := TerrainSettle.Batch.new()
	var next: Array[Arrival] = []
	for node in nodes:
		var landing: Array = reading[node]
		if landing.is_empty():
			continue
		var read := TerrainRead.of(_slice(node), node)
		for h: _Hit in landing:
			var hit_load := h.head.hit_load if generation == 0 else 0
			for e: Element in ElementRoster.shared().elements:
				var band := read.band(e)
				if band == null or band.go_off == null:
					continue
				var result := band.go_off.fire(node, read, hit_load)
				if result == null:
					continue
				_spend(spends, node, e, result)
				var reached := false
				for reach in result.reached:
					if reach == null or reach.node == null or not is_instance_valid(reach.node):
						continue
					reached = true
					next.append(_copy(h, reach.node, result, generation + 1))
				if reached and band.go_off.lands_on_own_node:
					var centre := _copy(h, node, result, generation + 1)
					centre.centre = true
					_entries.append(centre)
	TerrainSettle.commit(spends)
	return next


## Land [param h]'s own element riders where they fall, through each row's own
## landing (its fold, its gate), and mark them staged for stage two.
func _land_riders(h: _Hit) -> void:
	var roster := ElementRoster.shared()
	for hit in h.span:
		var status := hit as StatusInstance
		if status == null or status.staged or status.def == null:
			continue
		var e := roster.for_status(status.def)
		if e == null or e.terrain != status.def:
			continue
		if status.target == null or not is_instance_valid(status.target):
			continue
		var slice := _slice(status.target)
		if slice == null:
			continue
		status.land_on(slice, _world)
		status.staged = true
		h.terrain[e] = int(h.terrain.get(e, 0)) + int(status.power)


func _admits(node: SkillNode, before: TerrainRead, a: Arrival) -> bool:
	for e: Element in ElementRoster.shared().elements:
		var band := before.band(e)
		if band != null and band.admits != null and not band.admits.admit(node, before, a):
			return false
	return true


## The spend [param result] returns, on [param node]'s store of [param e]
## (summed, clamped at 0 by the commit), and its transfers onto reached nodes.
func _spend(batch: TerrainSettle.Batch, node: SkillNode, e: Element, result: GoOffResult) -> void:
	var total := result.spend()
	if total > 0:
		match Terrain.axis_of(e):
			Terrain.Axis.HEAT, Terrain.Axis.COLD:
				batch.add_toward_zero_t(_slice(node), total)
			Terrain.Axis.CHARGE:
				batch.add_charge(_slice(node), -total)
	var seen: Dictionary = {}
	for reach in result.reached:
		if reach == null or reach.node == null or seen.has(reach.node):
			continue
		seen[reach.node] = true
		_add(batch, reach.node, e, int(result.transfer.get(reach.node, 0)))


func _add(batch: TerrainSettle.Batch, node: SkillNode, e: Element, n: int) -> void:
	var slice := _slice(node)
	if n == 0 or slice == null:
		return
	match Terrain.axis_of(e):
		Terrain.Axis.HEAT:
			batch.add_net_t(slice, n)
		Terrain.Axis.COLD:
			batch.add_net_t(slice, -n)
		Terrain.Axis.CHARGE:
			batch.add_charge(slice, n)


func _copy(h: _Hit, node: SkillNode, result: GoOffResult, generation: int) -> Arrival:
	var a := Arrival.new()
	a.node = node
	a.head = h.head
	a.generation = generation
	a.is_copy = true
	a.share = result.share
	a.own_damage = result.own_damage
	return a


## [param node]'s slice, its pre-stage-one terrain noted on first touch.
func _slice(node: SkillNode) -> NodeCombat:
	if _slices.has(node):
		return _slices[node]
	var slice: NodeCombat = null
	if node != null and is_instance_valid(node):
		slice = _world.combat_for(node) as NodeCombat
	_slices[node] = slice
	if slice != null:
		_pre[node] = [slice.terrain_t(), slice.charge()]
	return slice


func _ops() -> Array:
	var ops: Array = []
	for node: SkillNode in _pre:
		var slice: NodeCombat = _slices[node]
		if slice == null or not is_instance_valid(node):
			continue
		var dt := slice.terrain_t() - int(_pre[node][0])
		var dc := slice.charge() - int(_pre[node][1])
		if dt != 0 or dc != 0:
			ops.append([node, dt, dc])
	return ops


## Stage two: each entry, a copy of its hit's span (staged element riders and
## non-payload kinds excluded) on the entry's node, pushed onto [param queue].
func _push(queue: HitQueue) -> void:
	if queue == null:
		return
	for a in _entries:
		var h: _Hit = _hits[a.head]
		var rows: Dictionary = {}  # StatusDef -> the entry's one StatusInstance
		var order: Array[StatusInstance] = []
		for src in h.span:
			if src.staged:
				continue
			match src.kind:
				HitInstance.Kind.DAMAGE, HitInstance.Kind.HEAL:
					var c := _clone(src, a)
					c.amount = src.amount * a.share
					if src.kind == HitInstance.Kind.DAMAGE:
						c.amount += a.own_damage
					queue.push(c)
				HitInstance.Kind.STATUS:
					var s := src as StatusInstance
					if s == null:
						continue
					var row: StatusInstance = rows.get(s.def)
					if row == null:
						row = _clone(s, a) as StatusInstance
						row.power = 0.0
						rows[s.def] = row
						order.append(row)
					row.power += s.power
		for row in order:
			if a.share != 1.0:
				row.power = ceilf(row.power * a.share)
			queue.push(row)


## A fresh copy of [param src] for entry [param a]: every script field, then
## the entry's target, the head as [member HitInstance.paired], and every
## landing result reset.
static func _clone(src: HitInstance, a: Arrival) -> HitInstance:
	var c: HitInstance = src.get_script().new()
	for p: Dictionary in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(p.name, src.get(p.name))
	var no_dealloc: Array[DeallocEntry] = []
	c.deallocations = no_dealloc
	var no_settle: Array[CombatWorld.SettleOp] = []
	c.settle = no_settle
	c.terrain_ops = []
	c.target = a.node
	c.paired = a.head
	c.is_head = false
	c.gathered = false
	c.staged = false
	c.hit_load = 0
	c.gated = false
	c.is_crit = false
	c.crit_multiplier = 1.0
	c.crit_tier = 0
	c.crit_decided = false
	c.effective_amount = 0.0
	return c


static func _scaled(stacks: int, share: float) -> int:
	return stacks if share == 1.0 else ceili(stacks * share)
