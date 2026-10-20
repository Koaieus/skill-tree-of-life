@tool
class_name RetractFront
extends PayloadExtension

## The out-and-back tendril's carried state — Lodestone's walk, read and
## written by [RetractSpread] (which decides every fact) and [HaulEffect]
## (which records [member State.seen]). A tendril walks OUT as a BFS, hops in
## place ([constant Phase.WAIT]) until the returns are in sync, then walks
## BACK the way it came, carrying [member State.cargo]. Nodes keep nothing:
## the tendril and its per-cast [Walk] ledger do.

enum Phase { OUT, WAIT, BACK }

## The id a reader looks this state up by when none is authored.
const ID := &"retract_front"


## One hauled piece: [member amount] stacks of [member def] leaving [member from].
class Piece extends RefCounted:
	var from: SkillNode = null
	var def: StatusDef = null
	var amount: int = 0

	static func of(from_: SkillNode, def_: StatusDef, amount_: int) -> Piece:
		var p := Piece.new()
		p.from = from_
		p.def = def_
		p.amount = amount_
		return p


## The per-cast trail map, built at the OUT landings and shared by reference
## by every state of one cast: each node's parents (the nodes its OUT incidents
## came from) and its trail count, the number of BFS paths from the seed (the
## seed's is 1, a node's the sum of its parents'). On the way back a merged
## tendril no longer knows where it came from — this does.
class Walk extends RefCounted:
	var graph: Graph = null
	var parents: Dictionary = {}  ## SkillNode -> Array[SkillNode], stable-id order
	var trails: Dictionary = {}  ## SkillNode -> int

	## Records [param node]'s OUT arrival from [param from] (null entries =
	## the seed). Once per node: a later call is a no-op.
	func record(node: SkillNode, from: Array) -> void:
		if trails.has(node):
			return
		var ps: Array[SkillNode] = []
		var count := 0
		for p: SkillNode in from:
			if p == null or ps.has(p):
				continue
			ps.append(p)
			count += trails_of(p)
		ps.sort_custom(func(a: SkillNode, b: SkillNode) -> bool: return _sid(a) < _sid(b))
		parents[node] = ps
		trails[node] = count if not ps.is_empty() else 1

	func trails_of(node: SkillNode) -> int:
		return int(trails.get(node, 0))

	func parents_of(node: SkillNode) -> Array[SkillNode]:
		var out: Array[SkillNode] = []
		out.assign(parents.get(node, []))
		return out

	func _sid(node: SkillNode) -> int:
		return graph.get_stable_id(node) if graph != null else node.get_instance_id()


## The state on each payload.
class State extends PayloadState:
	var phase: Phase = Phase.OUT
	## Hops from the seed of the node this payload lands on.
	var depth: int = 0
	## What the landed node held of each debuff before this wave landed —
	## StatusDef -> int, written at a BACK landing by [HaulEffect].
	var seen: Dictionary = {}
	## What this tendril hauls into the node it lands on.
	var cargo: Array[Piece] = []
	var walk: Walk = null


## A [PropagationPick] that also names the child's phase, depth and cargo —
## [RetractSpread] decides them, [method mint] copies them verbatim.
class Pick extends PropagationPick:
	var phase: Phase = Phase.OUT
	var depth: int = 0
	var cargo: Array[Piece] = []

	static func at(node_: SkillNode, phase_: Phase, depth_: int) -> Pick:
		var p := Pick.new()
		p.node = node_
		p.phase = phase_
		p.depth = depth_
		return p


func _init() -> void:
	id = ID


## [param payload]'s front state under [param front_id], or null.
static func state_of(payload: CastSpell, front_id: StringName = ID) -> State:
	return payload.extra(front_id) as State if payload != null else null


func seed(ctx: PropagationContext) -> PayloadState:
	var s := _state()
	s.walk = Walk.new()
	s.walk.graph = ctx.graph
	return s


func mint(parent: PayloadState, pick: PropagationPick, _lctx: LandingContext,
		_hop_index: int) -> PayloadState:
	var s := _state()
	var from := parent as State
	s.walk = from.walk if from != null else Walk.new()
	var p := pick as Pick
	if p != null:
		s.phase = p.phase
		s.depth = p.depth
		s.cargo = p.cargo.duplicate()
	else:
		s.depth = (from.depth if from != null else 0) + 1
	return s


## Fronts meeting at a node share their phase and depth ([RetractReducer] has
## already dropped a mismatched BACK); their cargo concatenates, sorted by
## source node then status so the hits it becomes land in a replay-stable order.
func merge(states: Array[PayloadState]) -> PayloadState:
	var first := states[0] as State
	var s := _state()
	s.phase = first.phase
	s.depth = first.depth
	s.walk = first.walk
	for st: PayloadState in states:
		s.cargo.append_array((st as State).cargo)
	var walk := s.walk
	s.cargo.sort_custom(func(a: Piece, b: Piece) -> bool:
		var sa := walk._sid(a.from) if walk != null and a.from != null else 0
		var sb := walk._sid(b.from) if walk != null and b.from != null else 0
		return sa < sb or (sa == sb and String(a.def.id) < String(b.def.id)))
	return s


func _state() -> State:
	var s := State.new()
	s.template = self
	return s
