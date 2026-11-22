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
##   larger ceil when two channels of one hit meet); then the node's Catalyst
##   converts over everything that landed there, heads' and copies' alike
##   ([method _convert_landing], #1801), the stacks it makes joining the same
##   write and its take committed through the row seat before it; the settle
##   seat reads the node's ints from before the land step ([_LandedFrom]), so
##   a head's riders crossing T convert the leftover as a copy's do;
## [br]- [b]read[/b]: first the node's second [Admits] read, once per node per
##   generation over every arrival there ([method Admits.read]): a breaker
##   shatters the node (one spend, one burst, its extra landings) and walks
##   every path on, else the answer may end the paths there
##   ([member HitInstance.path_ends] on a head); then, once per node per hit,
##   each band the node sits in after the riders fires its [GoOff]
##   ([method GoOff.fire_in], on the gather's world), unless the answer mutes
##   it: a node that holds (Frozen) fires none, a broken one only for the hits
##   that broke it, once each ([method _read_node]). The spends and transfers
##   of the whole generation (the breaks' included) commit together through
##   [TerrainSettle] before the next generation's admit. A Catalyst take the
##   settle seat makes inside either commit goes through the row seat
##   ([method _seat_take]).
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
	## Its head's second store ([method HitInstance.go_off_source]), or null.
	var source: GoOffSource = null
	## Its head's cast shape ([member HitInstance.cast_shape]) and points, read
	## once at the head's own node ([method _shape_at]); null after.
	var shape: Element = null
	var shape_points: int = 0


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
	## `(Element, int) -> void` when a [GoOffSource] pays instead of the
	## node's store ([method _fire_source]); else invalid.
	var spend: Callable = Callable()
	## `(Element, int) -> void`: a second payer, 1 per reached node, beside
	## the one above (a vertex's copy whose arc is one channel with a Shocked
	## node's own: [method _fire_vertex_arc]); else invalid.
	var copy_spend: Callable = Callable()


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
## The beat's Ice cues ([member HitInstance.ice_cues]), SkillNode -> excess or
## [constant HitInstance.ICE_HELD], in first-cue order: a break outranks a hold.
var _cues: Dictionary = {}
## `generation -> [[_Fired, GoOffResult.Reach], ...]`: the depth-d reaches
## parked until that generation's read (g + d − 1), the hop seat.
var _deep: Dictionary = {}
## `Arrival -> BlastMark`: the go-off mark each entry carries into stage two.
var _marks: Dictionary = {}
## `Arrival -> float`: a merged arrival's largest single share, the one its
## terrain riders land at ([method _join]).
var _rider_share: Dictionary = {}


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
## head (marked, not yet [member HitInstance.gathered]), each asked once, before
## generation 0, to stamp its raw amount ([method HitInstance.stamp_at_gather])
## and for its second store ([method HitInstance.go_off_source]); feeds every other hit's
## recorded [member HitInstance.terrain_ops] and [member HitInstance.row_ops];
## pushes the entries onto
## [param queue]. [param crit_rng] is the resolve's crit stream, handed on as
## [method OutcomeApplier.land_one] is handed it: each fresh head still
## undecided draws its crit here, in list order, against [param world] as the
## beat opens ([method _open_head]). Null on a replay: nothing draws. Then its
## gate is asked ([method HitInstance.resolve_gate]): a head its gate refuses keeps its crit and
## stamp but takes no part — no go-off, no spend, no copies. So the gate reads
## the world as the beat opens, before any hit of the beat lands.
static func stage_one(group: Array[HitInstance], world: CombatWorld, queue: HitQueue,
		crit_rng: RandomNumberGenerator = null) -> void:
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
		h.head.stamp_at_gather(world)
		h.source = h.head.go_off_source()
		if h.head.cast_shape != null and h.head.cast_shape_points > 0:
			h.shape = h.head.cast_shape
			h.shape_points = h.head.cast_shape_points
		gather._open_head(h, crit_rng)
		# A head its gate refuses takes no part: no go-off, no spend, no copies.
		h.head.resolve_gate(world)
		if not h.head.landed():
			h.source = null
			continue
		var a := Arrival.new()
		a.node = h.head.target
		a.head = h.head
		a.hops_removed = h.head.hops_removed
		arrivals.append(a)
	var generation := 0
	while not arrivals.is_empty() or not gather._deep.is_empty():
		arrivals = gather._generation(arrivals, generation)
		generation += 1
	order[0].head.terrain_ops = gather._ops()
	gather._push(queue)
	# After the push: a copy clones its head's fields, and only the head feeds.
	order[0].head.row_ops = gather._row_ops
	order[0].head.ice_cues = gather._ice_cues()


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
		a.amount = _amount(a)
	# Admit, against the terrain this generation starts from, each arrival
	# handed its own amount (the second read's number too).
	for node in nodes:
		var before := TerrainRead.of(_slice(node), node)
		for a: Arrival in at[node]:
			if not a.is_copy:
				continue
			if _admits(node, before, a):
				_entries.append(a)
			else:
				_cue_hold(node)
	# Land every arrival's element riders, absorbed or not.
	var batch := TerrainSettle.Batch.new()
	var reading: Dictionary = {}  # SkillNode -> Array of the _Hits read there
	var landed: Dictionary = {}  # SkillNode -> {element id: int} landing there (_convert_landing)
	var pre_land := _LandedFrom.new(TerrainSettle.seat(_seat_take))
	for node in nodes:
		pre_land.note(_slice(node))
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
				_land_riders(h, landed, pre_land)
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
				_landed(landed, node, e, int(best[h][e]))
		for h: _Hit in landing:
			h.visited[node] = true
		reading[node] = landing
	# Catalyst converts over each node's landing, its take committed before the
	# write so the settle seat reads the row after it.
	var land_rows: Dictionary = {}
	for node: SkillNode in landed:
		_convert_landing(node, landed[node], batch, land_rows)
	_commit_rows(land_rows)
	for node: SkillNode in landed:
		if _slice(node) != null:
			batch.sums(_slice(node))
	TerrainSettle.commit_with(batch, pre_land.seat())
	# Read: the node's second Admits answer over every arrival of the
	# generation there, then each hit not yet read there fires its go-offs;
	# every spend of the generation commits together.
	var spends := TerrainSettle.Batch.new()
	var next: Array[Arrival] = []
	var bursts: Array[HitInstance] = []
	for node in nodes:
		var read := TerrainRead.of(_slice(node), node)
		var fires: Variant = _read_node(node, read, at[node], generation, spends, bursts)
		var landing: Array = reading[node]
		for h: _Hit in landing:
			var muted: bool = fires != null and not (fires as Dictionary).has(h)
			var shape := _shape_at(h, node)
			for e: Element in ElementRoster.shared().elements:
				var band := read.band(e)
				if band == null or band.go_off == null or muted:
					continue
				if _vertex_disc(h, node, e) != null and band.go_off is DiscGoOff:
					continue  # adds up with the vertex's shape ([method _fire_vertex_disc])
				if _vertex_arc(h, node, e) != null and band.go_off is EdgeGoOff:
					continue  # one Lightning channel with the vertex's arc ([method _fire_vertex_arc])
				var result: GoOffResult = null
				var shaped: Variant = _shaped_in(e, h.shape_points, band.go_off) if e == shape else null
				if shaped != null:
					result = (shaped as Callable).call(node, read)
					shape = null  # added up: the band's one channel (ADR 0084 §3, ADR 0086 §5)
				else:
					result = band.go_off.fire_in(_world, node, read)
				if result == null:
					continue
				_spend(spends, node, e, result)
				_append_reach(h, node, result, band.go_off, generation + 1, next, e, _named(e, band))
			if shape != null:
				_fire_shape_alone(h, node, shape, generation, next)
			if h.source != null and node == h.head.target:
				_fire_source(h, node, generation, spends, next, muted)
	_release(generation, spends, next)
	TerrainSettle.commit(spends, _seat_take)
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
## [br]Returns the mute (ADR 0081 §4, ADR 0091 §1, ADR 0093 §3): null when no
## answer holds the node (every hit there goes off as usual); else
## `_Hit -> true` over the hits allowed to go off here: none while the node
## holds (Frozen mutes its own go-offs, the Charge stays trapped), and on a
## break only the hits owning a breaking arrival, each releasing once with its
## own payload. A hit the ice absorbed sets nothing off.
func _read_node(node: SkillNode, read: TerrainRead, arrivals: Array, generation: int,
		spends: TerrainSettle.Batch, bursts: Array[HitInstance]) -> Variant:
	var handed: Array[Arrival] = []
	for a: Arrival in arrivals:
		handed.append(a)
	var ends := false
	var broke := false
	var fires: Dictionary = {}  # _Hit -> true: owns a breaking arrival
	for e: Element in ElementRoster.shared().elements:
		var band := read.band(e)
		if band == null or band.admits == null:
			continue
		var answer := band.admits.read_in(_world, node, read, handed)
		if answer == null:
			continue
		if answer.breakers.is_empty():
			ends = ends or answer.paths_end
			continue
		broke = true
		for i in answer.breakers:
			if i >= 0 and i < handed.size():
				fires[_hits[handed[i].head]] = true
		_shatter(node, e, answer, handed, spends, bursts)
	var path_ends := ends and not broke
	if path_ends:
		if not _ended.has(generation):
			_ended[generation] = {}
		_ended[generation][node] = true
		_cue_hold(node)
	for a in handed:
		if not a.is_copy:
			a.head.path_ends = path_ends
	if broke:
		return fires
	if ends:
		return {}
	return null


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
	_cues[node] = maxi(int(_cues.get(node, HitInstance.ICE_HELD)), maxi(answer.excess, 0))
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


## [param node]'s ice held an arrival (an absorbed copy, an ended walk): cued
## once, and never over a break.
func _cue_hold(node: SkillNode) -> void:
	if not _cues.has(node):
		_cues[node] = HitInstance.ICE_HELD


## The beat's [member _cues] as [member HitInstance.ice_cues] pairs.
func _ice_cues() -> Array:
	var out: Array = []
	for node: SkillNode in _cues:
		out.append([node, int(_cues[node])])
	return out


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


## Runs once per head, after its raw amount is stamped and before its admit /
## land / read: the arrival's one crit (ADR 0083 §4, ADR 0092 §2 "crit and load
## already in"). A spell's head arrives decided (its landing's stamper, against
## the pre-hit node: [method SpellResolver._crit_at_head]); an arrow's or a
## blade contact's arrives undecided and draws here off [param crit_rng]
## ([method CritRoll.decide]), against the gather's world as the beat opens, so
## its landing finds it decided and draws nothing. Null [param crit_rng] (a
## replay, a standalone gather) draws nothing and leaves an undecided head to
## its landing. A decided head hands its crit to every hit of its span that
## would otherwise draw or copy at land, its unpaired siblings and its own
## riders, so the arrival draws once and a sibling lands on the head's crit
## without being gated by it; every copy is paired to the head and copies it at
## land. Before the riders land, so the head's terrain stacks take its crit.
func _open_head(h: _Hit, crit_rng: RandomNumberGenerator = null) -> void:
	var head := h.head
	if crit_rng != null:
		CritRoll.decide(head, crit_rng, _world)
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
		generation: int, next: Array[Arrival], e: Element = null, named: Identity = null,
		spend: Callable = Callable(), centre_copy := true, copy_spend: Callable = Callable()) -> void:
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
			fired.spend = spend
			fired.copy_spend = copy_spend
			if go_off != null:
				fired.mark = BlastMark.new()
				fired.mark.centre = node
				fired.mark.attacker = h.head.attacker
				fired.mark.go_off = named
				fired.mark.generation = generation - 1
				fired.mark.reach = result.reach
				fired.mark.power = result.power
				fired.mark.riders = _rider_ids(h)
		if reach.depth <= 1:
			_join(next, _arrive(fired, reach.node, generation))
			continue
		var at := generation + reach.depth - 2
		if not _deep.has(at):
			_deep[at] = []
		_deep[at].append([fired, reach])
	if fired != null and go_off != null and go_off.lands_on_own_node and centre_copy:
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
			var cost := int(fired.result.cost.get(reach.node, 0))
			if fired.spend.is_valid():
				if cost > 0:
					fired.spend.call(fired.element, cost)
			else:
				_spend_stacks(spends, fired.node, fired.element, cost)
			if fired.copy_spend.is_valid():
				fired.copy_spend.call(fired.element, 1)
			_add(spends, reach.node, fired.element, int(fired.result.effect.get(reach.node, 0)))
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


## The identities of the status rows [param h]'s copies carry ([method _push]:
## its span's status riders less the staged element riders), once each in span
## order: the riders a [BlastMark] shows its audience.
static func _rider_ids(h: _Hit) -> Array[Identity]:
	var out: Array[Identity] = []
	for hit in h.span:
		var s := hit as StatusInstance
		if s == null or s.staged or s.def == null or s.def.identity == null:
			continue
		if not out.has(s.def.identity):
			out.append(s.def.identity)
	return out


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
## landing (its fold, its gate), and mark them staged for stage two; each one's
## stacks summed into [param landed] on its node ([method _landed]), its node's
## ints noted in [param pre_land] before the first lands.
func _land_riders(h: _Hit, landed: Dictionary, pre_land: _LandedFrom) -> void:
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
		pre_land.note(slice)
		status.land_on(slice, _world)
		status.staged = true
		h.terrain[e] = int(h.terrain.get(e, 0)) + int(status.power)
		_landed(landed, status.target, e, int(status.power))


## [param n] stacks of [param e] landing on [param node] this generation, summed
## into [param landed] (`SkillNode -> {element id: int}`): a head's riders and
## its copies' alike, what [method _convert_landing] converts over.
static func _landed(landed: Dictionary, node: SkillNode, e: Element, n: int) -> void:
	if n <= 0 or e == null or node == null:
		return
	if not landed.has(node):
		landed[node] = {}
	landed[node][e.id()] = int(landed[node].get(e.id(), 0)) + n


## The land step's Catalyst hook (#1801; Composition's land conversion, ADR
## 0083 §1): once per node per land commit, each [CatalystStatus] row
## [param node]'s slice holds converts over [param landing] (element id → the
## Heat, Cold and Charge stacks landing there this generation) through
## [method CatalystStatus.convert], and the stacks it makes join
## [param batch], the node's one terrain write, so the hit's read counts them.
## The take goes through the row seat into [param rows], which the land step
## commits (and records, [member HitInstance.row_ops]) before the write, so the
## settle seat reads the row after it: nothing converts twice. Only the node's
## own row converts; a bare core's entity-hosted row holds no terrain
## (tentative).
func _convert_landing(node: SkillNode, landing: Dictionary, batch: TerrainSettle.Batch,
		rows: Dictionary) -> void:
	var slice := _slice(node)
	if slice == null or landing.is_empty():
		return
	var roster := ElementRoster.shared()
	var seen: Dictionary = {}
	for row: NodeStatus in slice.get_statuses():
		var def := row.def as CatalystStatus
		if def == null or seen.has(def) or row.power <= 0.0:
			continue
		seen[def] = true
		var take := func(spent: int, made: Dictionary) -> void:
			_row_change(rows, node, def, -float(spent), made)
		var out := def.convert(slice, landing, take)
		for id: Variant in out:
			_add(batch, node, roster.by_id(id), int(out[id]))


## The land commit's seat: the settle seat's readers ([param inner]), each
## handed a noted node's ints from before the generation's land step in place
## of the commit's own. A head's riders land through their rows before the
## batch commits, so the commit's own "before" already holds them; this way a
## crossing of T a head's riders make reads as a crossing, as a copy's does
## (#1801: the priming converts what the land split left). Every node a hit
## landed on is in the batch, so the seat is asked of it.
class _LandedFrom:
	extends TerrainSettle.SettleReader
	var _inner: Array[TerrainSettle.SettleReader]
	var _pre: Dictionary = {}  # NodeCombat -> [terrain_t, charge] before the land step

	func _init(inner: Array[TerrainSettle.SettleReader]) -> void:
		_inner = inner

	## Note [param slice]'s ints now, before any rider lands this generation.
	func note(slice: NodeCombat) -> void:
		if slice != null and not _pre.has(slice):
			_pre[slice] = [slice.terrain_t(), slice.charge()]

	## The readers [method TerrainSettle.commit_with] runs: this one alone.
	func seat() -> Array[TerrainSettle.SettleReader]:
		var out: Array[TerrainSettle.SettleReader] = [self]
		return out

	func read(node: NodeCombat, pre_t: int, pre_charge: int,
			post_t: int, post_charge: int, sums: TerrainSettle.Sums) -> void:
		var pre: Array = _pre.get(node, [pre_t, pre_charge])
		for r in _inner:
			r.read(node, int(pre[0]), int(pre[1]), post_t, post_charge, sums)


## The settle seat's take inside the gather ([method TerrainSettle.commit]'s
## take, bound to the node and def): [param spent] Catalyst off
## [param slice]'s row of [param def], recorded with the stacks it made
## ([param converted]), committed and recorded at once, so the
## rest of the commit and the beat's later commits read the row after it and a
## replay takes it too.
func _seat_take(spent: int, converted: Dictionary, slice: NodeCombat, def: StatusDef) -> void:
	if slice == null:
		return
	var rows: Dictionary = {}
	_row_change(rows, slice.real(), def, -float(spent), converted)
	_commit_rows(rows)


func _admits(node: SkillNode, before: TerrainRead, a: Arrival) -> bool:
	for e: Element in ElementRoster.shared().elements:
		var band := before.band(e)
		if band != null and band.admits != null and not band.admits.admit_in(_world, node, before, a):
			return false
	return true


## [param h]'s head's second store ([member _Hit.source]) going off at the
## head's own [param node], beside the node's bands: each band the source's
## read sits in fires its [GoOff] from [param node] with that read, and the
## spend (its per-reached part: a copy pays no floor) comes off the source
## through its callable, never the node's ints; a transfer still lands on the
## reached nodes. Once per hit, as the node's own
## go-offs are. An inert source sits in no band, fires nothing, spends nothing.
func _fire_source(h: _Hit, node: SkillNode, generation: int, spends: TerrainSettle.Batch,
		next: Array[Arrival], muted := false) -> void:
	var read := h.source.read
	if read == null:
		return
	for e: Element in ElementRoster.shared().elements:
		var band := read.band(e)
		if band == null or band.go_off == null:
			continue
		if band.go_off is DiscGoOff:
			_fire_vertex_disc(h, node, e, band.go_off as DiscGoOff, generation, spends, next)
			continue
		if band.go_off is EdgeGoOff:
			_fire_vertex_arc(h, node, e, band.go_off as EdgeGoOff, generation, spends, next, muted)
			continue
		var result := band.go_off.fire_in(_world, node, read)
		if result == null:
			continue
		var spent := result.spend_at_read() - result.nodeless_cost  # a copy pays no floor
		if spent > 0 and h.source.spend.is_valid():
			h.source.spend.call(e, spent)
		var seen: Dictionary = {}
		for reach in result.reached:
			if reach == null or reach.node == null or reach.depth > 1 or seen.has(reach.node):
				continue
			seen[reach.node] = true
			_add(spends, reach.node, e, int(result.effect.get(reach.node, 0)))
		_append_reach(h, node, result, band.go_off, generation + 1, next, e, _named(e, band),
				h.source.spend)


## [param h]'s cast shape element to read at [param node], or null: once, at
## its head's own node (the seed), then spent ([member _Hit.shape_points]
## stays for the read). A shape whose element has no
## shape-taking go-off ([method _shape_band]) is none here (Ice's is #1813's).
func _shape_at(h: _Hit, node: SkillNode) -> Element:
	if h.shape == null or node != h.head.target:
		return null
	var e := h.shape
	h.shape = null
	return e if _shape_band(e) != null else null


## The band of [param e] whose [GoOff] takes a cast's shape: its first holding
## a [DiscGoOff] (Fire) or an [EdgeGoOff] (Lightning), or null.
static func _shape_band(e: Element) -> ElementBand:
	if e == null:
		return null
	for band in e.bands:
		if band != null and (band.go_off is DiscGoOff or band.go_off is EdgeGoOff):
			return band
	return null


## A cast shape of [param e] × [param points] as an extra input to
## [param go_off] (a primed band of [param e]): `(node, read) -> GoOffResult`, the one combined
## go-off at the node's solo cost (ADR 0084 §3, §4) — the disc at
## [method DiscGoOff.fire_shaped_in] of points × the element's per-point power,
## the arc at [method EdgeGoOff.fire_level_in] of
## [method EdgeGoOff.level_for_points]. Invalid for any other go-off.
func _shaped_in(e: Element, points: int, go_off: GoOff) -> Variant:
	if go_off is DiscGoOff:
		var power := e.shape_power(points)
		return func(node: SkillNode, read: TerrainRead) -> GoOffResult:
			return (go_off as DiscGoOff).fire_shaped_in(_world, node, read, power)
	if go_off is EdgeGoOff:
		var level := EdgeGoOff.level_for_points(points)
		return func(node: SkillNode, read: TerrainRead) -> GoOffResult:
			return (go_off as EdgeGoOff).fire_level_in(_world, node, read, level)
	return null


## A cast's [param e] shape running alone at its seed [param node] (ADR 0086
## §4): the element's shape-taking [GoOff] answered with no read (level N at
## M = 0; the disc of the shape alone), appended as a list with no band behind
## it — no spend, no own damage, no centre copy, so no channel. Its mark names
## that band's identity (tentative: Fire → Burning, Lightning → Shocked).
## Reaching no one is nothing.
func _fire_shape_alone(h: _Hit, node: SkillNode, e: Element, generation: int,
		next: Array[Arrival]) -> void:
	var band := _shape_band(e)
	var shaped: Callable = _shaped_in(e, h.shape_points, band.go_off)
	var result: GoOffResult = shaped.call(node, null)
	if result == null or result.reached.is_empty():
		return
	_append_reach(h, node, result, band.go_off, generation + 1, next, e, _named(e, band),
			Callable(), false)


## The disc [param h]'s go-off source sets off in [param e] at its own head's
## [param node], or null: a vertex copy primed in a [DiscGoOff] band (Fire's
## Burning) is a shape on the node it touches, never a disc of its own.
func _vertex_disc(h: _Hit, node: SkillNode, e: Element) -> DiscGoOff:
	if h.source == null or h.source.read == null or node != h.head.target:
		return null
	var band := h.source.read.band(e)
	return band.go_off as DiscGoOff if band != null else null


## A primed vertex copy's disc as a shape of power copy − T on the contact
## [param node], sized by the node: on a node whose own [param e] band goes
## off by a [DiscGoOff] (Burning) the two add up as ONE channel
## ([method DiscGoOff.fire_shaped_in]): one mark, the centre copy, the node's
## solo spend off its store; on any other node (Frozen included) the shape runs
## alone: a mark, no centre copy, no node spend. Either way the copy pays 1 per
## node the disc reaches, through the source's spend, and no floor; reaching no
## one is no go-off for the copy, while a Burning node still voids its floor.
## The node's own plain go-off is skipped in the go-off loop on the same
## predicate ([method _vertex_disc]).
func _fire_vertex_disc(h: _Hit, node: SkillNode, e: Element, copy_disc: DiscGoOff,
		generation: int, spends: TerrainSettle.Batch, next: Array[Arrival]) -> void:
	var read := TerrainRead.of(_slice(node), node)
	var own := read.band(e)
	var burning := own != null and own.go_off is DiscGoOff
	var disc: DiscGoOff = own.go_off as DiscGoOff if burning else copy_disc
	var shape := float(disc.power_at(null, h.source.read))
	var result := disc.fire_shaped_in(_world, node, read, shape)
	if result == null:
		return
	if result.reached.is_empty():
		if burning:
			_spend(spends, node, e, result)  # the contact node still voids its floor
		return
	if h.source.spend.is_valid():
		h.source.spend.call(e, result.reached.size())
	if burning:
		_spend(spends, node, e, result)
	var band: ElementBand = own if burning else h.source.read.band(e)
	_append_reach(h, node, result, disc, generation + 1, next, e, _named(e, band),
			Callable(), burning)


## The arc [param h]'s go-off source sets off in [param e] at its own head's
## [param node], or null: a vertex copy primed in an [EdgeGoOff] band
## (Lightning's Shocked) is a shape on the node it touches, never a second arc.
func _vertex_arc(h: _Hit, node: SkillNode, e: Element) -> EdgeGoOff:
	if h.source == null or h.source.read == null or node != h.head.target:
		return null
	var band := h.source.read.band(e)
	return band.go_off as EdgeGoOff if band != null else null


## A primed vertex copy's arc from the contact [param node], at the copy's
## level ([method EdgeGoOff.level_of] its read). On a node whose own [param e]
## band arcs (Shocked) the two are ONE Lightning channel: one arc at the node's
## level plus the copy's ([method EdgeGoOff.fire_level_in]), one mark, the
## centre copy, the node paying its solo cost and transfer off its store. On
## any other node the copy's arc runs alone: a mark, no centre copy, no node
## spend, its transfer onto each node reached; a [param muted] node (Frozen
## holding, [method _read_node]) is any other node: its own arc stays trapped.
## Either way the copy pays 1 per node reached, through the source's spend: depth 1 at this read, deeper ones
## as [method _release] lets them on. Reaching no one is no go-off. The node's
## own plain arc is skipped in the go-off loop on [method _vertex_arc].
func _fire_vertex_arc(h: _Hit, node: SkillNode, e: Element, copy_edge: EdgeGoOff,
		generation: int, spends: TerrainSettle.Batch, next: Array[Arrival], muted := false) -> void:
	var read := TerrainRead.of(_slice(node), node)
	var own := read.band(e)
	var shocked := not muted and own != null and own.go_off is EdgeGoOff
	var result: GoOffResult = null
	if shocked:
		var edge := own.go_off as EdgeGoOff
		result = edge.fire_level_in(_world, node, read, edge.level_of(h.source.read))
	else:
		result = copy_edge.fire_level_in(_world, node, h.source.read, 0)
	if result == null or result.reached.is_empty():
		return
	var near := 0
	var seen: Dictionary = {}
	for reach in result.reached:
		if reach == null or reach.node == null or reach.depth > 1 or seen.has(reach.node):
			continue
		seen[reach.node] = true
		near += 1
		if not shocked:
			_add(spends, reach.node, e, int(result.effect.get(reach.node, 0)))
	if near > 0 and h.source.spend.is_valid():
		h.source.spend.call(e, near)
	if shocked:
		_spend(spends, node, e, result)
		_append_reach(h, node, result, own.go_off, generation + 1, next, e, _named(e, own),
				Callable(), true, h.source.spend)
	else:
		_append_reach(h, node, result, copy_edge, generation + 1, next, e,
				_named(e, h.source.read.band(e)), h.source.spend, false)


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
		_add(batch, reach.node, e, int(result.effect.get(reach.node, 0)))


## The gather's one seat for a status-row change: [param delta] on the row of
## [param def] held by [param node]'s slice, summed into [param rows] with
## the generation's other changes on that node, as `[delta, converted]`, keyed
## `[node, HostKind.NODE]` (the recorded op's holder shape). A Catalyst
## take passes [param converted], element id → the stacks it made (the
## landing element the cue tints by), summed alike. Committed and recorded by
## [method _commit_rows], so a replay changes the row too.
func _row_change(rows: Dictionary, node: SkillNode, def: StatusDef, delta: float,
		converted: Dictionary = {}) -> void:
	if delta == 0.0 or def == null or node == null:
		return
	var at := [node, StatusInstance.HostKind.NODE]
	if not rows.has(at):
		rows[at] = {}
	if not rows[at].has(def):
		rows[at][def] = [0.0, {}]
	var entry: Array = rows[at][def]
	entry[0] = float(entry[0]) + delta
	for id: Variant in converted:
		entry[1][id] = int(entry[1].get(id, 0)) + int(converted[id])


## Commit [param rows]: each holder's summed change on its row, a spend clamped
## at 0 (a row spent to 0 or under is removed, [method StatusHost.adjust_power]),
## each change recorded in commit order for the beat's first head
## ([member HitInstance.row_ops]).
func _commit_rows(rows: Dictionary) -> void:
	for at: Array in rows:
		for def: StatusDef in rows[at]:
			var entry: Array = rows[at][def]
			var op := [at[0], at[1], def, float(entry[0]), entry[1]]
			_row_ops.append(op)
			_apply_row(_world, op)


## One recorded row change ([member HitInstance.row_ops]) on [param world]: the
## node's slice; nothing when the node is gone. A Catalyst take on a live world
## also announces [signal SkillNode.catalyst_converted] with the op's converted
## stacks (the replay's cue; a shadow stays silent).
static func _apply_row(world: CombatWorld, op: Array) -> void:
	var node: SkillNode = op[0]
	if node == null or not is_instance_valid(node):
		return
	var slice := world.combat_for(node) as NodeCombat
	if slice == null:
		return
	if op[2] == null:
		return
	slice.adjust_status_power(op[2], float(op[3]))
	if float(op[3]) < 0.0 and op[2] is CatalystStatus and not world.is_shadow():
		node.announce_catalyst_converted(op[4] if op.size() > 4 else {})


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
	var c: HitInstance = src.blank_copy()
	for p: Dictionary in src.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			c.set(p.name, src.get(p.name))
	var no_dealloc: Array[DeallocEntry] = []
	c.deallocations = no_dealloc
	var no_settle: Array[CombatWorld.SettleOp] = []
	c.settle = no_settle
	c.terrain_ops = []
	c.row_ops = []
	c.ice_cues = []
	c.target = a.node
	c.paired = a.head
	c.is_head = false
	c.gathered = false
	c.staged = false
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
	# The pop belongs to the one contact that made it, never to a copy of it.
	c.popped_vertex = null
	c.cast_shape = null
	c.cast_shape_points = 0
	c.hops_removed = 0
	return c


static func _scaled(stacks: int, share: float) -> int:
	return stacks if share == 1.0 else ceili(stacks * share)
