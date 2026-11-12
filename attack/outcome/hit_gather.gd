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
## heads; a go-off fired at generation g's read sends its copies to g + 1 (a
## node it reached at hop depth d to g + d: the hop seat, [method _release]),
## and each generation starts from the terrain the one before left. At each
## node of a generation, in order:
## [br]- [b]admit[/b]: every copy is asked of the node's bands' [Admits] against
##   the terrain before this generation's riders (a head and a centre copy never
##   are); an admitted copy is an entry, an absorbed one is not;
## [br]- [b]land[/b]: every arrival's element riders (Heat, Cold, Charge), absorbed
##   or not, once per node per hit: a head's own rows land through their own
##   [method StatusInstance.land_on] and are marked [member HitInstance.staged];
##   a copy's are ceil(r × s) of them, summed through [TerrainSettle] (the
##   larger ceil when two channels of one hit meet);
## [br]- [b]read[/b]: first the node's second [Admits] read, once per node per
##   generation over every arrival there ([method Admits.read]): a breaker
##   shatters the node (one spend, one burst, its extra landings) and walks
##   every path on, else the answer may end the paths there
##   ([member HitInstance.path_ends] on a head); then, once per node per hit,
##   each band the node sits in after the riders fires its [GoOff]
##   ([method GoOff.fire_in], on the gather's world), and each [Aspect] with a
##   [member Aspect.go_off] fires that, by no band test (go-off zero's seat
##   until the Catalyst retag, #1799; a hit planting the aspect's own row does
##   not set it off). The spends and transfers of the whole generation (the
##   breaks' included) commit together through [TerrainSettle], an aspect
##   go-off's on its holder's row of [member Aspect.status] beside them
##   ([method _spend_row]), before the next generation's admit.
## [br]The once-per-node set is the hit's: a node it already landed takes a later
## copy as an entry only, and does not go off again. Each go-off that reaches a
## node mints one [BlastMark] ([member BlastMark.go_off]: its band's
## [Identity]), stamped on every entry it makes. Two reaches of one hit on one
## node are two entries unless [member HitGatherTunables.dedupe_dual_reach]
## merges them ([method _join]). Stage two is the drain:
## every entry is pushed onto the [HitQueue] as a copy of the hit's whole span
## (element riders excluded), [code]paired[/code] to its head, at damage × s +
## own damage and riders ceil(r × s), one row per status id.
##
## The gather is the beat's only terrain writer, and it records the beat's net
## change on its first head ([member HitInstance.terrain_ops]), beside every
## status-row change it commits ([member HitInstance.row_ops]); a re-drained or
## rebuilt beat feeds those instead of gathering ([method feed]).


## A shatter's burst (ADR 0090 §1): [member amount] HP of TRUE damage on the
## node's holder, landed in stage two through [method DotTick.mint], the path
## [method CorruptionStatus._on_burst] takes, so "a burst lands" stays one
## implementation. Pushed after its generation's entries; draws no crit.
class _Burst:
	extends DamageInstance

	static func at(node: SkillNode, head: HitInstance, hp: float) -> _Burst:
		var b := HitGather.burst(hp) as _Burst
		b.target = node
		b.attacker = head.attacker
		b.schedule_index = head.schedule_index
		b.structural_key = head.structural_key
		b.arrival_time = head.arrival_time
		return b

	func land_on(node: NodeCombat, _world: CombatWorld) -> void:
		var holder := node.owner() if node != null else null
		if holder != null and amount > 0.0:
			effective_amount = amount
			DotTick.mint(holder, amount, basis)


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


## One go-off the gather fired that reached a node: its mark, and what its
## parked deeper reaches need when [method _release] lets them on.
class _Fired:
	extends RefCounted
	var hit: _Hit = null
	## The node it went off from, and the element whose store pays.
	var node: SkillNode = null
	var element: Element = null
	var result: GoOffResult = null
	## Stamped on each of its entries; null for a list no go-off made.
	var mark: BlastMark = null
	## `SkillNode -> true`: the reached nodes whose entries it dropped.
	var dropped: Dictionary = {}


const DEFAULT_TUNABLES := preload("res://attack/outcome/hit_gather_tunables.tres")

## The gather's tunables, [constant DEFAULT_TUNABLES] unless a test hands it
## its own (and puts the default back).
static var tunables: HitGatherTunables = DEFAULT_TUNABLES

var _world: CombatWorld = null
var _hits: Dictionary = {}  # head HitInstance -> _Hit
var _slices: Dictionary = {}  # SkillNode -> NodeCombat (null: not a node slice)
var _pre: Dictionary = {}  # SkillNode -> [t, charge] before stage one touched it
## Every status-row change committed, in order ([member HitInstance.row_ops]).
var _row_ops: Array = []
## Stage two's worklist, in push order: [Arrival] entries, and each generation's
## shatter bursts ([HitInstance]) after that generation's entries.
var _entries: Array = []
## `generation -> {SkillNode: true}`: the nodes whose second read in that
## generation ended the paths through them ([method _ends_at]).
var _ended: Dictionary = {}
## `generation -> [[_Fired, GoOffResult.Reach], ...]`: the depth-d reaches
## parked until that generation's read (g + d − 1), the hop seat.
var _deep: Dictionary = {}
## `Arrival -> BlastMark`: the go-off mark each entry carries into stage two.
var _marks: Dictionary = {}
## `Arrival -> float`: a merged arrival's largest single share, the one its
## terrain riders land at ([method _join]).
var _rider_share: Dictionary = {}
## The aspects whose go-off the read fires ([method _aspect_go_offs]), read
## off the roster once per gather.
var _aspects: Array[Aspect] = []
var _aspects_read := false


## A shatter's burst of [param hp] HP, bare: what [AttackRecord] rebuilds a
## recorded one as, so a replay lands it on the holder's pool as the live
## landing did.
static func burst(hp: float) -> DamageInstance:
	var b := _Burst.new()
	b.type = DamageInstance.Type.TRUE
	b.basis = HitInstance.AmountBasis.FLAT
	b.amount = hp
	b.crit_decided = true
	return b


## Whether [param hit] is a shatter's burst ([method burst]).
static func is_burst(hit: HitInstance) -> bool:
	return hit is _Burst


## Stage one over one beat, [param group] in land order. Gathers every fresh
## head (marked, not yet [member HitInstance.gathered]); feeds every other hit's
## recorded [member HitInstance.terrain_ops] and [member HitInstance.row_ops];
## pushes the entries onto
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
		if not fresh and not (hit.terrain_ops.is_empty() and hit.row_ops.is_empty()):
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
		gather._open_head(h)
		var a := Arrival.new()
		a.node = h.head.target
		a.head = h.head
		arrivals.append(a)
	var generation := 0
	while not arrivals.is_empty() or not gather._deep.is_empty():
		arrivals = gather._generation(arrivals, generation)
		generation += 1
	order[0].head.terrain_ops = gather._ops()
	gather._push(queue)
	# After the push: a copy clones its head's fields, and only the head feeds.
	order[0].head.row_ops = gather._row_ops


## Land [param hit]'s recorded stage-one terrain on [param world], then its
## recorded status-row changes ([member HitInstance.row_ops]) in commit order
## (terrain and rows are separate stores, so the beat's net change on each is
## what a replay needs): the replay of a gather, never a second one.
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
	for op: Array in hit.row_ops:
		_apply_row(world, op)


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
				stacks[e] = maxi(int(stacks.get(e, 0)),
						_scaled(int(h.terrain[e]), float(_rider_share.get(a, a.share))))
		for h: _Hit in best:
			for e: Element in best[h]:
				_add(batch, node, e, int(best[h][e]))
		for h: _Hit in landing:
			h.visited[node] = true
		reading[node] = landing
	TerrainSettle.commit(batch)
	# Read: the node's second Admits answer over every arrival of the
	# generation there, then each hit not yet read there fires its go-offs;
	# every spend of the generation commits together.
	var spends := TerrainSettle.Batch.new()
	var rows: Dictionary = {}  # [SkillNode, HostKind] -> {StatusDef: delta}: the row changes (_row_change)
	var next: Array[Arrival] = []
	var bursts: Array[HitInstance] = []
	for node in nodes:
		var read := TerrainRead.of(_slice(node), node)
		_read_node(node, read, at[node], generation, spends, bursts)
		var landing: Array = reading[node]
		for h: _Hit in landing:
			var hit_load := h.head.hit_load if generation == 0 else 0
			for e: Element in ElementRoster.shared().elements:
				var band := read.band(e)
				if band == null or band.go_off == null:
					continue
				var result := band.go_off.fire_in(_world, node, read, hit_load)
				if result == null:
					continue
				_spend(spends, node, e, result)
				_append_reach(h, node, result, band.go_off, generation + 1, next, e, _named(e, band))
			for aspect: Aspect in _aspect_go_offs():
				if _plants(h, aspect.status):
					continue
				var result := aspect.go_off.fire_in(_world, node, read, hit_load)
				if result == null:
					continue
				_spend_row(rows, node, aspect.status, result.spend_at_read())
				_append_reach(h, node, result, aspect.go_off, generation + 1, next, null, aspect.identity)
	_release(generation, spends, next)
	TerrainSettle.commit(spends)
	_commit_rows(rows)
	_entries.append_array(bursts)
	return next


## The node's second [Admits] read (ADR 0083 §2; ADR 0091 §1, §4), once per node
## per generation, before its go-offs: each band the node sits in after the
## riders ([param read]) is asked over [param arrivals], every arrival of the
## generation at the node (absorbed ones included), each handed its own
## [member Arrival.amount]. A breaker shatters the node ([method _shatter]) and
## walks every path through it on; else an answer's "paths end" ends them. The
## verdict is kept per node per generation ([method _ends_at], the seat a
## depth-d entry asks of its ring nodes) and rides a head arriving here
## ([member HitInstance.path_ends]).
func _read_node(node: SkillNode, read: TerrainRead, arrivals: Array, generation: int,
		spends: TerrainSettle.Batch, bursts: Array[HitInstance]) -> void:
	var handed: Array[Arrival] = []
	for a: Arrival in arrivals:
		a.amount = _amount(a)
		handed.append(a)
	var ends := false
	var broke := false
	for e: Element in ElementRoster.shared().elements:
		var band := read.band(e)
		if band == null or band.admits == null:
			continue
		var answer := band.admits.read(node, read, handed)
		if answer == null:
			continue
		if answer.breakers.is_empty():
			ends = ends or answer.paths_end
			continue
		broke = true
		_shatter(node, e, answer, handed, spends, bursts)
	var path_ends := ends and not broke
	if path_ends:
		if not _ended.has(generation):
			_ended[generation] = {}
		_ended[generation][node] = true
	for a in handed:
		if not a.is_copy:
			a.head.path_ends = path_ends


## Whether [param node]'s second read in [param generation] ended the paths
## through it: no arrival broke it and an answer said "paths end". A node not
## read in that generation ended nothing.
func _ends_at(node: SkillNode, generation: int) -> bool:
	return _ended.has(generation) and _ended[generation].has(node)


## A break (ADR 0090 §1; ADR 0091 §1, §2): [param answer]'s spend once, on
## [param e]'s store with the generation's go-off spends; for each breaking
## arrival only, the answer's count of extra entries on the node, each a copy
## of that arrival's own landing (damage and aspect riders only, as every
## entry); and one burst, pushed for stage two, when the node has a holder.
## Several breakers still spend and burst once.
func _shatter(node: SkillNode, e: Element, answer: AdmitsAnswer, arrivals: Array[Arrival],
		spends: TerrainSettle.Batch, bursts: Array[HitInstance]) -> void:
	_spend_stacks(spends, node, e, answer.spend)
	var seen: Dictionary = {}
	for i in answer.breakers:
		if i < 0 or i >= arrivals.size() or seen.has(i):
			continue
		seen[i] = true
		for _n in maxi(answer.extra_landings, 0):
			_entries.append(_extra(arrivals[i]))
	var slice := _slice(node)
	if answer.burst > 0.0 and slice != null and slice.owner() != null:
		bursts.append(_Burst.at(node, arrivals[0].head, answer.burst))


## An arrival's own landing's damage, before mitigation: each damage row of its
## hit at × share, plus its own damage once per entry on the first damage row
## (as [method _push] lands it), × the head's crit multiplier (1 without a crit).
func _amount(a: Arrival) -> float:
	var h: _Hit = _hits[a.head]
	var sum := 0.0
	var own := true
	for src in h.span:
		if src.kind == HitInstance.Kind.DAMAGE and not src.staged:
			sum += src.amount * a.share
			if own:
				sum += a.own_damage
				own = false
	return sum * a.head.crit_multiplier


## A break's extra landing: [param a]'s own landing again on its node, at its
## share and own damage, paired to its head. Never asked of [Admits].
func _extra(a: Arrival) -> Arrival:
	var x := Arrival.new()
	x.node = a.node
	x.head = a.head
	x.generation = a.generation
	x.is_copy = true
	x.share = a.share
	x.own_damage = a.own_damage
	x.amount = a.amount
	if _marks.has(a):
		_marks[x] = _marks[a]
	return x


## Runs once per head, before its admit / land / read: the arrival's one crit
## (ADR 0083 §4). A head whose crit is already decided (a spell's, by its
## landing's stamper against the pre-hit node: [method SpellResolver._crit_at_head])
## hands it to every hit of its span that would otherwise draw or copy at land,
## its unpaired siblings and its own riders, so the arrival draws once and a
## sibling lands on the head's crit without being gated by it; every copy is
## paired to the head and copies it at land. Before the riders land, so the
## head's terrain stacks take its crit. An undecided head (an arrow's, a
## blade's) is left to draw at land.
func _open_head(h: _Hit) -> void:
	var head := h.head
	if not head.crit_decided:
		return
	for hit in h.span:
		if hit == head or hit.crit_decided or (hit.paired != null and hit.paired != head):
			continue
		hit.copy_crit_from(head)
		hit.crit_decided = true


## The one seat a reach list enters by: [param result]'s depth-1 nodes become
## [param h]'s arrivals of [param generation] (g + 1), a depth-d one is parked
## for [method _release] at g + d − 1, and, when the list holds a node and
## [param go_off] lands on its own node, [param node] takes the centre copy as
## an entry. A [param go_off] that reaches a node mints one [BlastMark] naming
## [param named], stamped on every entry it makes, its
## [member BlastMark.generation] the read it fired at (g, one before
## [param generation]; ADR 0091 §1), its reach and power the result's
## ([member GoOffResult.reach], [member GoOffResult.power]); [param e] is the
## element whose store pays a parked node's cost (none for an aspect's go-off,
## whose reaches are depth 1). The go-off reaches by shape alone; the hit's
## own [member HitInstance.target_mask] then decides who takes a copy: a
## reached node whose ownership to the attacker on the gather's world (its
## slice's [method NodeCombat.ownership_bit], a cast's shadow included) misses
## it is skipped, takes no entry and does not chain (as a [SplashEffect]
## gathers; mask 0 skips none). Every reached node joins its
## generation through [method _join], the dedupe switch; a cast's shape adds
## its list through this seat (#1812).
func _append_reach(h: _Hit, node: SkillNode, result: GoOffResult, go_off: GoOff,
		generation: int, next: Array[Arrival], e: Element = null, named: Identity = null) -> void:
	var fired: _Fired = null
	var mask := h.head.target_mask
	for reach in result.reached:
		if reach == null or reach.node == null or not is_instance_valid(reach.node):
			continue
		if mask != 0:
			var at := _slice(reach.node)
			if at != null and (at.ownership_bit(h.head.attacker) & mask) == 0:
				continue
		if fired == null:
			fired = _Fired.new()
			fired.hit = h
			fired.node = node
			fired.element = e
			fired.result = result
			if go_off != null:
				fired.mark = BlastMark.new()
				fired.mark.centre = node
				fired.mark.attacker = h.head.attacker
				fired.mark.go_off = named
				fired.mark.generation = generation - 1
				fired.mark.reach = result.reach
				fired.mark.power = result.power
		if reach.depth <= 1:
			_join(next, _arrive(fired, reach.node, generation))
			continue
		var at := generation + reach.depth - 2
		if not _deep.has(at):
			_deep[at] = []
		_deep[at].append([fired, reach])
	if fired != null and go_off != null and go_off.lands_on_own_node:
		var centre := _arrive(fired, node, generation)
		centre.centre = true
		_entries.append(centre)


## The hop seat (#1798, tentative; ADR 0091 §1, ADR 0093 §5): each depth-d
## reach parked for [param generation], g + d − 1 of the go-off fired at g, now
## that its ring nodes have had this generation's second read. It drops when
## every ring node it hangs behind ended its paths here ([method _ends_at]) or
## had its own entry from this go-off dropped: it never arrives, costs nothing
## and takes no transfer, and what hangs behind it drops with it. Else its cost
## and transfer join [param spends], so they are in before its admit, and it
## arrives in generation + 1. An empty ring hangs behind nothing and never drops.
func _release(generation: int, spends: TerrainSettle.Batch, next: Array[Arrival]) -> void:
	var parked: Array = _deep.get(generation, [])
	_deep.erase(generation)
	for p: Array in parked:
		var fired: _Fired = p[0]
		var reach: GoOffResult.Reach = p[1]
		if _behind_ended(fired, reach, generation):
			fired.dropped[reach.node] = true
			continue
		if fired.element != null:
			_spend_stacks(spends, fired.node, fired.element, int(fired.result.cost.get(reach.node, 0)))
			_add(spends, reach.node, fired.element, int(fired.result.transfer.get(reach.node, 0)))
		_join(next, _arrive(fired, reach.node, generation + 1))


func _behind_ended(fired: _Fired, reach: GoOffResult.Reach, generation: int) -> bool:
	if reach.ring.is_empty():
		return false
	for ring in reach.ring:
		if not fired.dropped.has(ring) and not _ends_at(ring, generation):
			return false
	return true


## The dedupe switch ([member HitGatherTunables.dedupe_dual_reach]; ADR 0084 §5,
## ADR 0086 §3), the one place reached nodes join [param next]. Off, [param a]
## is its own entry (concatenate). On, a copy of the same hit already in
## [param next] on the same node in the same generation takes [param a] in: one
## arrival at the summed share and own damage, admitted and read once (the
## merged landing is the arrival, ADR 0093 §1), its terrain riders still at the
## largest single share (once per node per hit), its mark the first list's.
## Never the hit node's landings: a centre copy never comes through here, and a
## copy back on its head's own node is never merged. Tentative: entries of
## different generations stay apart, the own damages sum.
func _join(next: Array[Arrival], a: Arrival) -> void:
	if tunables != null and tunables.dedupe_dual_reach and a.node != a.head.target:
		for b: Arrival in next:
			if b.head == a.head and b.node == a.node and b.generation == a.generation \
					and b.is_copy and not b.centre:
				_rider_share[b] = maxf(float(_rider_share.get(b, b.share)), a.share)
				b.share += a.share
				b.own_damage += a.own_damage
				_marks.erase(a)
				return
	next.append(a)


## [param fired]'s copy on [param node] in [param generation], carrying its mark.
func _arrive(fired: _Fired, node: SkillNode, generation: int) -> Arrival:
	var a := _copy(fired.hit, node, fired.result, generation)
	if fired.mark != null:
		_marks[a] = fired.mark
	return a


## The [Identity] a go-off held by [param band] is named by: the band's own,
## or the nearest band below it with one (#1793's fallback, which
## `TerrainBars.shown_band` displays by; tentative). Null when none has one.
static func _named(e: Element, band: ElementBand) -> Identity:
	if band == null:
		return null
	if band.identity != null or e == null:
		return band.identity
	var i := e.bands.find(band) - 1
	while i >= 0:
		var b := e.bands[i]
		if b != null and b.identity != null:
			return b.identity
		i -= 1
	return null


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


## The spend [param result] returns at its own read, on [param node]'s store
## of [param e] (summed, clamped at 0 by the commit), and its transfers onto
## the depth-1 nodes; a deeper node's wait for [method _release].
func _spend(batch: TerrainSettle.Batch, node: SkillNode, e: Element, result: GoOffResult) -> void:
	_spend_stacks(batch, node, e, result.spend_at_read())
	var seen: Dictionary = {}
	for reach in result.reached:
		if reach == null or reach.node == null or reach.depth > 1 or seen.has(reach.node):
			continue
		seen[reach.node] = true
		_add(batch, reach.node, e, int(result.transfer.get(reach.node, 0)))


## The aspects whose [member Aspect.go_off] the read fires beside the bands:
## go-off zero's seat until the Catalyst retag deletes it (#1799, #1801).
func _aspect_go_offs() -> Array[Aspect]:
	if _aspects_read:
		return _aspects
	_aspects_read = true
	var roster := AspectRoster.shared()
	if roster == null:
		return _aspects
	for aspect in roster.aspects:
		if aspect != null and aspect.go_off != null and aspect.status != null:
			_aspects.append(aspect)
	return _aspects


## Whether [param h] plants [param def]'s row: a hit landing that aspect's own
## status does not set it off (today's PlantUse skip, ported as go-off zero's;
## #1801 deletes it with the aspect seat).
static func _plants(h: _Hit, def: StatusDef) -> bool:
	for hit in h.span:
		var s := hit as StatusInstance
		if s != null and s.def != null and s.def.id == def.id:
			return true
	return false


## [param total] stacks off the row of [param def] that [param node] holds,
## summed into [param rows] with the generation's other spends on that holder:
## the node's slice, or on a core with none its owner's entity-hosted row
## ([method DiscGoOff.present_on]'s rule), resolved at the read.
func _spend_row(rows: Dictionary, node: SkillNode, def: StatusDef, total: int) -> void:
	if total <= 0 or def == null:
		return
	var slice := _slice(node)
	if slice == null:
		return
	var kind := StatusInstance.HostKind.NODE
	if slice.get_status_power(def.id) <= 0.0 and slice.is_core() and slice.owner() != null:
		kind = StatusInstance.HostKind.ENTITY
	_row_change(rows, node, kind, def, -float(total))


## The gather's one seat for a status-row change: [param delta] on the row of
## [param def] held by [param node]'s slice, or by its owner's entity rows when
## [param kind] is [code]ENTITY[/code] (the caller resolves which), summed into
## [param rows] with the generation's other changes on that node and kind.
## Committed and recorded by [method _commit_rows], so a replay changes the row
## too.
func _row_change(rows: Dictionary, node: SkillNode, kind: StatusInstance.HostKind,
		def: StatusDef, delta: float) -> void:
	if delta == 0.0 or def == null or node == null:
		return
	var at := [node, kind]
	if not rows.has(at):
		rows[at] = {}
	rows[at][def] = float(rows[at].get(def, 0.0)) + delta


## Commit [param rows]: each holder's summed change on its row, a spend clamped
## at 0 (a row spent to 0 or under is removed, [method StatusHost.adjust_power]),
## each change recorded in commit order for the beat's first head
## ([member HitInstance.row_ops]).
func _commit_rows(rows: Dictionary) -> void:
	for at: Array in rows:
		for def: StatusDef in rows[at]:
			var op := [at[0], at[1], def, float(rows[at][def])]
			_row_ops.append(op)
			_apply_row(_world, op)


## One recorded row change ([member HitInstance.row_ops]) on [param world]: the
## node's slice, or its owner's entity rows; nothing when the node or the
## owner is gone (a replay whose node lost its owner to an earlier cascade).
static func _apply_row(world: CombatWorld, op: Array) -> void:
	var node: SkillNode = op[0]
	if node == null or not is_instance_valid(node):
		return
	var slice := world.combat_for(node) as NodeCombat
	if slice == null:
		return
	var holder: Object = slice
	if int(op[1]) == StatusInstance.HostKind.ENTITY:
		holder = slice.owner()
	if holder == null or op[2] == null:
		return
	holder.adjust_status_power(op[2], float(op[3]))


## [param total] stacks off [param node]'s store of [param e]: summed with the
## generation's other spends, clamped at 0 by the commit.
func _spend_stacks(batch: TerrainSettle.Batch, node: SkillNode, e: Element, total: int) -> void:
	if total <= 0:
		return
	match Terrain.axis_of(e):
		Terrain.Axis.HEAT, Terrain.Axis.COLD:
			batch.add_toward_zero_t(_slice(node), total)
		Terrain.Axis.CHARGE:
			batch.add_charge(_slice(node), -total)


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
## non-payload kinds excluded) on the entry's node, pushed onto [param queue];
## its go-off's own damage lands once per entry, on the first damage row.
func _push(queue: HitQueue) -> void:
	if queue == null:
		return
	for e in _entries:
		if e is HitInstance:
			queue.push(e)
			continue
		var a: Arrival = e
		var h: _Hit = _hits[a.head]
		var mark: BlastMark = _marks.get(a)
		var rows: Dictionary = {}  # StatusDef -> the entry's one StatusInstance
		var order: Array[StatusInstance] = []
		var own := true
		for src in h.span:
			if src.staged:
				continue
			match src.kind:
				HitInstance.Kind.DAMAGE, HitInstance.Kind.HEAL:
					var c := _clone(src, a)
					if mark != null:
						c.blast_mark = mark
					c.amount = src.amount * a.share
					if src.kind == HitInstance.Kind.DAMAGE and own:
						c.amount += a.own_damage
						own = false
					queue.push(c)
				HitInstance.Kind.STATUS:
					var s := src as StatusInstance
					if s == null:
						continue
					var row: StatusInstance = rows.get(s.def)
					if row == null:
						row = _clone(s, a) as StatusInstance
						if mark != null:
							row.blast_mark = mark
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
	c.row_ops = []
	c.target = a.node
	c.paired = a.head
	c.is_head = false
	c.gathered = false
	c.staged = false
	c.hit_load = 0
	# The head's mask, rechecked at land as a splash copy's is (#1799).
	if a.head.target_mask != 0:
		c.land_mask = a.head.target_mask
	c.target_mask = 0
	c.gated = false
	c.is_crit = false
	c.crit_multiplier = 1.0
	c.crit_tier = 0
	c.crit_decided = false
	c.effective_amount = 0.0
	return c


static func _scaled(stacks: int, share: float) -> int:
	return stacks if share == 1.0 else ceili(stacks * share)
