class_name BladePopResolver
extends RefCounted

## Defensive spike "pop" resolution (#170, budget model #778). Given the raw
## BladeHitEvents from a swing scan, decides which of the ATTACKER's own blade
## vertices are killed — and which are then severed from the driven handle and
## disintegrated.
##
## The model (see the #170 design comment, budget rule per #778):
##   - A blade vertex that sweeps into a spiked, allocated enemy node drains
##     that node's remaining `spikes` pool by the vertex's own `blunting`.
##     Remaining >= blunting: the pool depletes by blunting and the vertex
##     POPS — the vertex itself dies. Remaining < blunting: the remainder
##     drains to 0 and the vertex is NOT popped, passing through to deal
##     damage as an ordinary contact (owner: "pop only if full amount is
##     removed"). Either way the contact deals damage to NOBODY BUT the
##     defender it pops against — the spiked node itself takes none, and a
##     popping vertex's own hit never lands: [method BladeDamageInstance.land_on]
##     returns as soon as [method admit] refuses the contact, before
##     `super.land_on` (the only place damage is ever applied) runs.
##   - Killing a vertex disconnects everything downstream of it from the pivot /
##     handle. Every vertex no longer reachable from the pivot through surviving
##     edges is recorded as a SEVERANCE (#801) — it keeps coasting in the same
##     trajectory, because nothing is pulling on it any more; it is not killed.
##   - The pivot is exempt — popping the wielder's own handle is out of scope.
##   - An unspiked node (no `spikes` pool minted — only [SpikeRingAddon] ever
##     mints one) never pops anything, at any stake level.
##
## Result is a RECORD, not a solver: it marks each dead vertex with the time it
## died (so callers drop that vertex's hits from then on) and each severance
## with the set it orphaned. Re-baking the trajectory around those facts is
## [method MeleeAttackPlan.resolve_against]'s job, not this file's — see
## docs/domain/attack-timeline.md.
##
## [b]There is exactly one implementation of these predicates: [LiveGate].[/b]
## There used to be two — a pure `resolve()` batch pass for the AI/preview
## estimate and [LiveGate] for the real swing — and they did not agree (the
## batch pass ran its whole kill pass before its disconnection pass, so a vertex
## that disintegrated at t1 could still be recorded as a pop at t2 > t1).
## #498 step 3 retired the batch pass exactly as this file's own comment
## promised it would: the estimate now runs THIS gate against a shadow
## [CombatWorld], so the AI's shape-risk signal
## ([member AttackOutcome.popped_nodes]) is produced by the same code that
## produces the real one, against a detached copy of the same world.

## Per-pop record. `t` is the contact time; `defender` is the spiked node that
## popped `particle_idx`; `position` is where to play the pop VFX.
## `blunting_spent` is how much of the defender's `spikes` pool this contact
## drained — always the popping vertex's full `blunting` (a partial drain
## never pops, so it never reaches [method LiveGate._kill] / mints a Pop).
class Pop extends RefCounted:
	var particle_idx: int
	## The severed EDGE's index into [member BladeState.edges] when this record
	## is an edge break, else -1. Exactly one of `particle_idx` / `edge_idx` is
	## set, mirroring [BladeHitEvent]'s own convention.
	##
	## [b]Nothing produces one today[/b] — [method LiveGate._sever_edge] is #781's
	## seam and has no caller until the bunker lands. Under ADR 0005 a spike
	## never breaks an edge, so a spike drain can no longer mint an edge Pop; the
	## record shape is kept because a bunker break needs exactly it, and needs to
	## reach the replay as a cue the same way a vertex pop does.
	var edge_idx: int = -1
	var t: float
	var defender: SkillNode
	var position: Vector2
	var blunting_spent: float

	func _init(
			particle_idx_: int,
			t_: float,
			defender_: SkillNode,
			blunting_spent_: float,
			edge_idx_: int = -1) -> void:
		particle_idx = particle_idx_
		edge_idx = edge_idx_
		t = t_
		defender = defender_
		blunting_spent = blunting_spent_
		position = defender_.global_position if defender_ != null else Vector2.ZERO


## One SEVERANCE EVENT: the set of vertices that stopped being reachable from
## the pivot at [member t], recorded the moment it happened (#801).
##
## [b]These vertices are COASTING, not dead.[/b] Nothing is pulling on them any
## more, so plain Verlet keeps carrying them through the rest of the same
## trajectory — armed, still landing #779-scaled hits, still poppable. They are
## deliberately NOT in [member Result.dead_at]; the only thing this record
## drives is [method MeleeAttackPlan.resolve_against] writing
## [member BladeState.damping] for exactly this set before it re-bakes the tail.
## (Under #186 they were a second BODY, which is the model this replaced.)
##
## [b]Trigger-agnostic on purpose.[/b] A severance is described by "which
## vertices left the handle, and when" and by nothing about WHY — a spike pop
## today, #781's bunker break tomorrow. Whatever severs feeds
## [method LiveGate._disintegrate_unreachable], and there is one continuation.
##
## `vertices` are indices into [BladeState] — index-stable for the whole swing
## (#785), never compacted — and are ascending, so a consumer's iteration is
## deterministic without re-sorting.
class Severance extends RefCounted:
	var t: float
	var vertices: PackedInt32Array

	func _init(t_: float, vertices_: PackedInt32Array) -> void:
		t = t_
		vertices = vertices_


## One explosive blade contact's two sides, as the gate decided them: the
## striker's side (the piece's load plus the shared chunk) blasts the board,
## the node's side (the node's charges plus the shared chunk) reaches the
## blade pieces around the struck node. Recorded so the swing's replay draws
## it as a pure function of time, like [member Result.dead_at]; nothing reads
## it to decide anything.
class Contact extends RefCounted:
	## What the node's-side pass did to one piece it considered.
	enum Verdict { POPPED, SPENT, SHRUGGED }
	## The contact time.
	var t: float
	var struck: SkillNode
	## The struck node's position: the bomb is the node.
	var centre: Vector2
	## The node's-side reach in px; 0.0 when the node held no charges.
	var piece_reach: float
	var striker_power: int
	var node_power: int
	## particle_idx -> [enum Verdict], for every piece the pass considered,
	## the contact's own piece included.
	var verdicts: Dictionary = {}

	func _init(t_: float, struck_: SkillNode) -> void:
		t = t_
		struck = struck_
		centre = struck_.global_position if struck_ != null else Vector2.ZERO


## One explosive charge spend a blade contact decided (#1595): [member count]
## charges off [member node] at [member t]. Recorded, never written: the
## resolve lands it as a 1-stack-per-charge cleanse on the attack record.
class Spend extends RefCounted:
	var node: SkillNode
	var count: int
	var t: float

	func _init(node_: SkillNode, count_: int, t_: float) -> void:
		node = node_
		count = count_
		t = t_


## The [member HitInstance.paired] of a blade contact's blast landing: it
## "landed" iff the gate decided this contact's [member blast_kind] of blast when
## the contact itself landed (same beat, earlier index). Never in a hit list —
## only [method HitInstance.rider_gated] ever reads it. Carries the contact's
## crit so a [PairedDamageInstance] riding it inherits the contact's.
class BlastToken extends HitInstance:
	var _gate: LiveGate
	var _event: BladeHitEvent
	var blast_kind: StringName
	var _contact: HitInstance

	func _init(gate: LiveGate, event: BladeHitEvent, kind_: StringName, contact: HitInstance) -> void:
		_gate = gate
		_event = event
		blast_kind = kind_
		_contact = contact

	func landed() -> bool:
		if _contact != null:
			is_crit = _contact.is_crit
			crit_multiplier = _contact.crit_multiplier
			crit_tier = _contact.crit_tier
		return _gate.blast_of(_event) == blast_kind


## `dead_at`: particle_idx -> time a spike DESTROYED it. A hit by that vertex
## at `ev.t >= dead_at[idx]` must be dropped. Since #801 this holds destroyed
## vertices only — a vertex that merely lost its path to the handle coasts on
## and is recorded in `severances` instead, so `dead_at.size()` and
## [method vertex_pop_count] now agree by construction rather than by filter.
## `pops`: the killing contacts only (drive VFX / hit tracking), in time order.
class Result extends RefCounted:
	var dead_at: Dictionary = {}
	## edge_idx -> time it was severed. The edge counterpart of `dead_at`; the
	## vertices it orphaned land in `dead_at` as usual. Written only by
	## [method LiveGate._sever_edge], i.e. by #781's bunker break once it exists.
	var severed_at: Dictionary = {}
	var pops: Array[Pop] = []
	## Severance events in the order they happened (#801). Each entry is one
	## call to [method LiveGate._disintegrate_unreachable] that actually
	## orphaned something. The vertices are deliberately NOT in `dead_at`: they
	## are coasting, not destroyed, and they go on hitting things in the same
	## trajectory. Each vertex appears in at most one entry.
	var severances: Array[Severance] = []
	## Every explosive contact in time order, one row each.
	var contacts: Array[Contact] = []

	func is_dead(particle_idx: int, t: float) -> bool:
		return dead_at.has(particle_idx) and t >= dead_at[particle_idx]

	## How many of the attacker's own VERTICES a defender actually destroyed
	## (#799) — [member AttackOutcome.popped_nodes]'s one source.
	##
	## [b]Kept as a `pops` walk, not switched to `dead_at.size()`.[/b] Since
	## #801 an orphan never enters `dead_at` at all, so the two agree — but they
	## agree for a reason that lives in `_disintegrate_unreachable`, and the
	## EDGE exclusion below is this method's own. #799 filed the conflation
	## (#186 put orphans in `dead_at`, which made the AI's shape-risk term
	## over-avoid spiked defenders); #801 removed the premise.
	##
	## Edge [Pop]s (#781's bunker seam, no caller today) are excluded by the
	## `particle_idx >= 0` test: a broken edge destroys structure, not matter.
	func vertex_pop_count() -> int:
		var n := 0
		for pop in pops:
			if pop.particle_idx >= 0:
				n += 1
		return n


## The pop/disconnect gate for one swing (#502): the kill/disconnect predicates
## fed one [BladeHitEvent] at a time, in true land order, by
## [method BladeDamageInstance.land_on] as [OutcomeApplier] walks the swing's
## hits — so an earlier-in-time hit's cascade is visible to a later event's
## `is_allocated()` / ownership read. See docs/domain/attack-timeline.md.
##
## [b]Which world it reads is an argument, not a mode.[/b] Handed
## [method CombatWorld.live] it gates a live swing; handed a
## [method CombatWorld.shadow] it gates the authority's compute pass or an AI
## rollout against detached slices, running the identical predicates. There is
## no preview flag anywhere below — see [method admit].
class LiveGate extends RefCounted:
	## Accepted pops so far, in the same shape [method resolve] returns —
	## [MeleePreview] replays this post-application (#502's "Watch": the
	## preview replays the applier's ACCEPTED set, never a fresh rescan).
	var result := Result.new()
	var _state: BladeState
	var _attacker: Entity
	## The [Pop] the LAST [method admit] made, or null if it made none. Cleared
	## on entry to every [method admit], so it answers "did THIS contact pop?" —
	## which is the one thing a false return cannot say on its own (a dead
	## target and a spike pop both refuse). [BladeDamageInstance] reads it to
	## stamp [member HitInstance.popped_vertex]; see that member for why the cue
	## is recorded rather than emitted from here (#536).
	var _last_pop: Pop = null
	## particle_idx -> true for every vertex currently in `result.dead_at`
	## (killed OR disintegrated). Maintained incrementally by [method _kill]
	## (#795) rather than rebuilt from `result.dead_at` every call — it only
	## ever grows within a swing.
	var _removed: Dictionary = {}
	## particle_idx -> true for every vertex already reported in
	## `result.severances`. Separate from `_removed` precisely because a coasting
	## vertex is still THERE — it is not removed from the sim, it is only no
	## longer pulled — so it must not enter the BFS's removed set. This dict only
	## stops the same vertex being reported twice (#801).
	var _orphaned: Dictionary = {}
	## vertex index -> Array[int] of neighbour indices, over `_state.edges`.
	## Built lazily on first use and cached for the rest of this swing (#795):
	## one O(E) build instead of one O(E) rescan per dequeued BFS vertex.
	var _adjacency: Dictionary = {}
	var _adjacency_built: bool = false
	## Melee's reach share (owner: "just a bit for fun"): both sides of a
	## contact reach this share of [method ExplosiveSpread.radius_for] on the
	## struck node at that side's power. Tentative, easy to change.
	@export_range(0.0, 2.0, 0.05) var warhead_reach: float = 0.5
	## The share of the contact's raw damage the board blast's shrapnel deals
	## (the power sizes the reach, not the damage). Tentative, easy to change.
	@export_range(0.0, 2.0, 0.05) var shrapnel_fraction: float = 0.5
	## BladeHitEvent -> [constant BLAST]: the contact set its board blast off,
	## decided in [method admit] and read by its [BlastToken]s.
	var _blasts: Dictionary = {}
	## Real SkillNode -> charges this swing already spent off it. A struck
	## node's charges are its world power minus this, until the resolve lands
	## the recorded [Spend]s.
	var _node_spent: Dictionary = {}
	## Spends decided and not yet handed to the resolve ([method take_spends]).
	var _spends: Array[Spend] = []
	## Finder per warhead reach, so one reach gathers once per landing cache.
	var _finders: Dictionary = {}

	## `vertex_blunting` is an OPTIONAL particle_idx -> blunting override
	## (#778), consulted BEFORE the state's own
	## [member BladeState.vertex_blunting] array. Production never passes it:
	## both blade-build call sites fill the array from each source node's
	## `get_local_value(&"blunting")`, so the [SpikeRingAddon] raise to 2
	## reaches [method admit] end to end. The dict stays as the seam for a
	## fixture that wants to pin one vertex's blunting against a hand-built
	## state it never populated. See [method _blunting_for] for the full chain.
	var _vertex_blunting: Dictionary

	func _init(state: BladeState, attacker: Entity, vertex_blunting: Dictionary = {}) -> void:
		_state = state
		_attacker = attacker
		_vertex_blunting = vertex_blunting

	## The [Pop] this gate's most recent [method admit] produced, or null.
	func last_pop() -> Pop:
		return _last_pop

	## True if `ev`'s damage should actually land right now. Call exactly
	## once per event, in true time order — mutates `result` when a contact
	## turns out to be a live pop.
	##
	## [param world] selects which world the allocation / ownership / spike
	## reads come from (#535). Required, not defaulted, for the same reason
	## [method OutcomeApplier.apply]'s is — a nullable world hides an implicit
	## live branch inside a gate whose whole job is to read one specific world.
	func admit(ev: BladeHitEvent, world: CombatWorld) -> bool:
		var w := world
		_last_pop = null
		if ev.is_edge_hit():
			return _admit_edge(ev, w)
		if result.is_dead(ev.particle_idx, ev.t):
			return false  # already popped or disintegrated by an earlier LIVE kill
		var real_node := ev.target as SkillNode
		var node: NodeCombat = w.combat_for(real_node) if real_node != null else null
		if node == null or not node.is_allocated():
			return false  # #502: dead target, no dud — indistinguishable from a miss
		# The pivot / handle is exempt from popping — popping the wielder's own
		# grip is out of scope. Since #801 there is exactly one state per swing
		# and exactly one pivot in it, so this is unconditional: a coasting
		# vertex has no handle of its own to be exempt by, and pops like any
		# other (#186 acceptance: "its root is not exempt", now true because
		# there is no second root).
		if ev.particle_idx == _state.pivot_index:
			return true
		if _attacker != null and node.ownership_bit(_attacker) == SkillNode.Ownership.MINE:
			return true  # your own spike can't pop your own blade
		match _admit_explosive(ev, real_node, node):
			_EXPLOSIVE_REFUSE:
				return false  # the piece spent its last life on this contact
		var pool := _spikes_pool(node)
		var remaining := float(pool.current) if pool != null else 0.0
		if remaining <= 0.0:
			return true  # unspiked, or already fully spent this swing
		var blunting := _blunting_for(ev.particle_idx)
		if remaining >= blunting:
			pool.deplete(blunting)
			_mark_spent(node, w)
			_kill(ev.particle_idx, ev.t, real_node, blunting)
			return false  # the popping contact itself deals no damage
		# Remaining < blunting: drain the remainder and let the vertex THROUGH —
		# "pop only if full amount is removed" (#778). No Pop record: the vertex
		# survives and its hit lands normally.
		pool.deplete(remaining)
		_mark_spent(node, w)
		return true

	const _EXPLOSIVE_NONE := 0
	const _EXPLOSIVE_REFUSE := 1
	const EXPLOSIVE := &"explosive"
	const BLAST := &"blast"

	## The explosive cause: one contact, two sides. With the piece's charges
	## N (the swing's working copy), the struck node's M and
	## `shared = min(N, M)`, each side that holds charges spends
	## `max(1, shared)`; the striker's side `N + r·shared` blasts the board
	## ([method arm_blasts]), the node's side `M + r·shared` reaches the blade
	## pieces ([method _piece_pass]). One [Contact] row per explosive contact.
	## REFUSE when the contact's own piece ends at 0; NONE lets the spike
	## ladder run on.
	func _admit_explosive(ev: BladeHitEvent, real_node: SkillNode, node: NodeCombat) -> int:
		var spread := explosive_spread()
		if spread == null:
			return _EXPLOSIVE_NONE
		var idx := ev.particle_idx
		var n := piece_charges(idx)
		var m := node_charges(node)
		if n <= 0 and m <= 0:
			return _EXPLOSIVE_NONE
		var shared := mini(n, m)
		var row := Contact.new(ev.t, real_node)
		row.striker_power = side_power(n, shared, spread)
		row.node_power = side_power(m, shared, spread)
		if n > 0:
			_blasts[ev] = BLAST
			_spend_piece(idx, maxi(1, shared), ev.t)
		if m > 0:
			_spend_node(real_node, maxi(1, shared), ev.t)
		result.contacts.append(row)
		if row.node_power > 0:
			row.piece_reach = warhead_reach * spread.radius_for(real_node.radius, row.node_power)
			_piece_pass(ev, real_node, row)
		if piece_charges(idx) <= 0:
			row.verdicts[idx] = Contact.Verdict.POPPED
			_kill(idx, ev.t, real_node, 0.0)
			return _EXPLOSIVE_REFUSE
		row.verdicts[idx] = Contact.Verdict.SPENT
		return _EXPLOSIVE_NONE

	## One side's power: its own charges plus the shared chunk weighted by
	## [member ExplosiveSpread.resonance]; 0 for a side that holds none.
	static func side_power(own: int, shared: int, spread: ExplosiveSpread) -> int:
		return own + spread.resonance * shared if own > 0 else 0

	## The node's side: every live blade piece within [member Contact.piece_reach]
	## of the struck node — a plain one pops, a charged one is armed, not
	## fragile, and shrugs. The contact's own piece is the caller's.
	func _piece_pass(ev: BladeHitEvent, struck: SkillNode, row: Contact) -> void:
		for v in _state.positions.size():
			if v == ev.particle_idx or v == _state.pivot_index or _removed.has(v):
				continue
			if _state.positions[v].distance_to(row.centre) > row.piece_reach:
				continue
			if piece_charges(v) > 0:
				row.verdicts[v] = Contact.Verdict.SHRUGGED
			else:
				row.verdicts[v] = Contact.Verdict.POPPED
				_kill(v, ev.t, struck, 0.0)

	## The piece's charges left this swing.
	func piece_charges(idx: int) -> int:
		if _state == null or idx < 0 or idx >= _state.vertex_charges.size():
			return 0
		return _state.vertex_charges[idx]

	## [param node]'s charges on its own world, minus what this swing spent.
	func node_charges(node: NodeCombat) -> int:
		if node == null:
			return 0
		return maxi(0, int(node.get_status_power(EXPLOSIVE)) - int(_node_spent.get(node.real(), 0)))

	## The blast [param ev] set off: [constant BLAST] or &"" — what each
	## [BlastToken] gates on.
	func blast_of(ev: BladeHitEvent) -> StringName:
		return _blasts.get(ev, &"")

	## Every [Spend] decided since the last call, in decision order; clears.
	## The caller lands them on this gate's world before the next
	## [method admit], so from here the world's own power carries them and
	## the in-swing ledger lets go.
	func take_spends() -> Array[Spend]:
		var out := _spends
		_spends = []
		for spend in out:
			if _node_spent.has(spend.node):
				_node_spent[spend.node] = maxi(0, int(_node_spent[spend.node]) - spend.count)
		return out

	func _spend_piece(idx: int, count: int, t: float) -> void:
		_state.vertex_charges[idx] = maxi(0, _state.vertex_charges[idx] - count)
		var source: SkillNode = _state.vertex_node[idx] if idx < _state.vertex_node.size() else null
		if source != null:
			_spends.append(Spend.new(source, count, t))

	func _spend_node(node: SkillNode, count: int, t: float) -> void:
		_node_spent[node] = int(_node_spent.get(node, 0)) + count
		_spends.append(Spend.new(node, count, t))

	## The explosive status's spread, or null if the roster has none.
	static func explosive_spread() -> ExplosiveSpread:
		var def := explosive_def()
		return def.spread as ExplosiveSpread if def != null else null

	static func explosive_def() -> StatusDef:
		var roster := StatusRoster.shared()
		return roster.by_concept(EXPLOSIVE) if roster != null else null

	## Arm [param ev]'s board blast on a landing riding [param contact],
	## appended to [param hits]: the striker's side `N + r·min(N, M)` (M read
	## on [param world] now), centred on the struck node, landing only if
	## [method admit] decides it ([BlastToken]). Inners are shrapnel plus the
	## piece's [param riders] with explosive stripped, armed with a load-0
	## [DetonateEffect] so the blast chains like any blast — a charged board
	## node in reach goes off once. [param read_overlays] is copied onto the
	## landing.
	func arm_blasts(
			ev: BladeHitEvent,
			contact: HitInstance,
			hits: Array[HitInstance],
			world: CombatWorld,
			riders: Array,
			read_overlays: Callable = Callable()) -> void:
		var n := piece_charges(ev.particle_idx)
		var struck := ev.target as SkillNode
		var spread := explosive_spread() if n > 0 and struck != null else null
		if spread == null:
			return
		var plain: Array[OnHitEffect] = []
		for r in riders:
			var effect := r as OnHitEffect
			if effect != null and not effect is DetonateEffect:
				plain.append(effect)
		var armed := DetonateEffect.arm(DetonateEffect.strip(plain))
		var m := node_charges(world.combat_for(struck))
		var power := side_power(n, mini(n, m), spread)
		var blast := BlastEffect.new()
		blast.inners = _with_shrapnel(armed, shrapnel_fraction)
		blast.power = power
		blast.range_finder = _finder(warhead_reach * spread.radius_for(struck.radius, power))
		_ride(blast, BLAST, ev, contact, hits, read_overlays)

	func _ride(
			blast: BlastEffect,
			kind: StringName,
			ev: BladeHitEvent,
			contact: HitInstance,
			hits: Array[HitInstance],
			read_overlays: Callable) -> void:
		var landing := HitLanding.riding(contact, hits)
		landing.paired = BlastToken.new(self, ev, kind, contact)
		landing.target_mask = SkillNode.Ownership.HOSTILE
		if read_overlays.is_valid():
			landing.read_overlays = read_overlays
		blast.apply(landing)

	static func _with_shrapnel(plain: Array[OnHitEffect], fraction: float) -> Array[OnHitEffect]:
		var shrapnel := PairedDamageEffect.new()
		shrapnel.fraction = fraction
		var out: Array[OnHitEffect] = [shrapnel]
		out.append_array(plain)
		return out

	func _finder(reach: float) -> EuclideanRangeFinder:
		var finder: EuclideanRangeFinder = _finders.get(reach)
		if finder == null:
			finder = EuclideanRangeFinder.new()
			finder.max_distance = reach
			_finders[reach] = finder
		return finder

	## The edge branch of [method admit]. Under [b]ADR 0005[/b] an edge is not a
	## blunting element at all — [b]spikes pop vertices, bunkers break edges[/b] —
	## so this branch reads liveness and nothing else: it never touches the
	## defender's `spikes` pool, never depletes it, and never severs. An edge
	## sweeping over a spiked node leaves `pool.current` exactly where it was.
	##
	## [b]This is an explicit SKIP of the spike gate, and it has to be.[/b] The
	## tempting one-liner — give an edge blunting 0 and let the ladder run — is a
	## bug, not a shortcut: `remaining >= blunting` is then trivially true, so
	## every edge contact would `deplete(0)` and sever, which is #778's "zero
	## means unfilled" gotcha inverted. Hence there is no `_blunting_for_edge`
	## anywhere in this file, and no pool read below.
	##
	## Liveness still applies — "neither endpoint has died and the edge itself is
	## intact", since an edge hanging off a popped vertex is no longer swinging —
	## and a de-allocated target is still #502's "no dud for melee".
	func _admit_edge(ev: BladeHitEvent, w: CombatWorld) -> bool:
		if _state == null or ev.edge_idx < 0 or ev.edge_idx >= _state.edges.size():
			return false
		if _state.is_edge_removed(ev.edge_idx):
			return false
		var e := _state.edges[ev.edge_idx]
		if result.is_dead(e.x, ev.t) or result.is_dead(e.y, ev.t):
			return false
		var real_node := ev.target as SkillNode
		var node: NodeCombat = w.combat_for(real_node) if real_node != null else null
		if node == null or not node.is_allocated():
			return false
		return true


	## Sever [param edge_idx] and disintegrate whatever it was the only path to.
	## The vertex-kill twin of [method _kill]: same record, same reachability
	## sweep, same "recorded, never announced from here" rule (#536) — only the
	## thing that died differs. [method BladeState.remove_edge] drops the
	## distance constraint too.
	##
	## [b]This is #781's seam, and it currently has no caller.[/b] Its one caller
	## used to be a full spike drain on an edge contact; ADR 0005 retired that —
	## [b]a spike destroys matter, a bunker destroys structure[/b], so the thing
	## that breaks an edge is a rigid blade shattering against a bunker, not a
	## spike ring. Everything a bunker break needs is already here: the record,
	## the orphan sweep, and the index-stability invariant below.
	##
	## [b]It deliberately does NOT invalidate the adjacency cache.[/b] Severance
	## is recorded in [member BladeState.removed_edges] rather than spliced out
	## of `edges`, so every edge index stays stable and the cached map stays
	## correct — [method _reachable_from_pivot] skips the severed edge by index
	## as it walks. Rebuilding here would put an O(E) pass back on every
	## severance and undo #795 (acceptance 7: no per-severance rescan).
	## [method invalidate_adjacency] remains for a caller that mutates
	## `_state.edges` itself.
	func _sever_edge(edge_idx: int, t: float, defender: SkillNode, blunting_spent: float) -> void:
		_state.remove_edge(edge_idx)
		result.severed_at[edge_idx] = minf(result.severed_at.get(edge_idx, INF), t)
		var pop := Pop.new(-1, t, defender, blunting_spent, edge_idx)
		result.pops.append(pop)
		_last_pop = pop
		_disintegrate_unreachable(t)

	## The defender's node-local `spikes` [PoolStat], or null if it never
	## minted one — i.e. an unspiked node ([SpikeRingAddon] is the only source,
	## see spike_ring_addon.gd). Reads through [method NodeCombat.board], so it
	## resolves to the SHADOW's own cloned board on a shadow [param node], same
	## as every other per-world board read in this file (#778 — mirrors how
	## [method NodeCombat.take_damage] already deletes per-world HP with no
	## special-casing for which world it's handed).
	static func _spikes_pool(node: NodeCombat) -> PoolStat:
		var b := node.board()
		return b.get_stat(&"spikes") as PoolStat if b != null else null

	## This gate's blunting for [param particle_idx], in priority order:
	## the caller-supplied override dict, then the state's own
	## [member BladeState.vertex_blunting] slot (what production fills), then
	## the `blunting` [StatDef]'s authored default (currently 1) for a
	## hand-built state that filled neither. A zero slot counts as unfilled —
	## blunting 0 would drain nothing and pop nothing, so no authored build
	## can produce it.
	static func _blunting_for_dict(vertex_blunting: Dictionary, particle_idx: int) -> float:
		if vertex_blunting.has(particle_idx):
			return float(vertex_blunting[particle_idx])
		var def: StatDef = StatRegistry.get_def(&"blunting")
		return float(def.default_value) if def != null else 1.0

	func _blunting_for(particle_idx: int) -> float:
		if _vertex_blunting.has(particle_idx):
			return float(_vertex_blunting[particle_idx])
		if _state != null and particle_idx < _state.vertex_blunting.size():
			var from_state := _state.vertex_blunting[particle_idx]
			if from_state > 0.0:
				return from_state
		return _blunting_for_dict({}, particle_idx)

	## Registers [param node]'s real [SkillNode] on its owner's sparse
	## turn-start refresh set (#778 — Entity._on_turn_started sweeps exactly
	## this set, never all owned nodes; see entity.gd). Gated to the LIVE world
	## ONLY: a shadow's owner is the same real [Entity] the live world would
	## resolve to, and marking through a shadow (AI scoring / preview, or the
	## authority's own compute-record pass ahead of its live replay) would leak
	## a real mutation out of a world that must not touch reality — see
	## docs/domain/attack-timeline.md. The pool DEPLETE above still runs on
	## whichever world's board [param node] resolves to; only this bookkeeping
	## step is world-gated.
	static func _mark_spent(node: NodeCombat, world: CombatWorld) -> void:
		if world.is_shadow():
			return
		var owner := node.owner()
		var entity := owner.real_entity() if owner != null else null
		if entity != null:
			entity.mark_spikes_spent(node.real())

	func _kill(particle_idx: int, t: float, defender: SkillNode, blunting_spent: float) -> void:
		result.dead_at[particle_idx] = t
		var pop := Pop.new(particle_idx, t, defender, blunting_spent)
		result.pops.append(pop)
		# #504: a spike pop is a MODEL event, announced on the mutation clock —
		# the same clock the damage, the health bar and the shatter are on. It
		# is not announced from HERE, though (#536): under #498 step 3 the
		# authority runs this gate against a SHADOW world, where an emit would
		# have no audience, and then replays its own record on the live world
		# like any peer. So the pop is RECORDED — [BladeDamageInstance] reads
		# `_last_pop` onto the hit, [AttackRecord] carries it, and
		# [method OutcomeApplier.land_one] emits it as that hit lands.
		#
		# That also gives a peer the cue, which it never used to get: the
		# animation-replay emitter this replaced could only ever fire on the
		# machine that swung.
		_last_pop = pop
		_removed[particle_idx] = true
		_disintegrate_unreachable(t)

	## Mark every vertex no longer reachable from the pivot as dead at [param t].
	## Shared by [method _kill] and [method _sever_edge]: losing a vertex and
	## losing an edge orphan a fragment by exactly the same criterion, and the
	## BFS reads both `_removed` and [member BladeState.removed_edges].
	func _disintegrate_unreachable(t: float) -> void:
		# The BFS root is always the pinned handle, and it cannot die (the
		# exemption in `admit`). #186's re-rooting is gone with the second body
		# it existed for: there is one state, one pivot, one trajectory.
		var root := _state.pivot_index
		var reachable := BladePopResolver._reachable_from_pivot(
				_state, _removed, _ensure_adjacency(), null, root)
		# Ascending by construction (the loop counts up), which is the order
		# Severance promises its consumer.
		var orphaned := PackedInt32Array()
		for v in _state.positions.size():
			if v == root or _removed.has(v) or _orphaned.has(v):
				continue
			if not reachable.has(v):
				_orphaned[v] = true
				orphaned.append(v)
		if not orphaned.is_empty():
			# RECORDED here, simulated elsewhere (#801). This gate stays a pure
			# predicate over one swing — it does not own a solver, a physics
			# query or a second AttackOutcome, and it must not, because it is
			# also the AI-rollout and preview path. The RESOLVE loop reads this
			# and does the state mutation.
			result.severances.append(Severance.new(t, orphaned))

	## Lazily builds, then caches, this swing's adjacency map (#795) — one
	## O(E) build total instead of one per [method _kill]/[method admit].
	func _ensure_adjacency() -> Dictionary:
		if not _adjacency_built:
			_adjacency = BladePopResolver._build_adjacency(_state)
			_adjacency_built = true
		return _adjacency

	## Explicit invalidation seam (#795, for #781): nothing in this file
	## mutates `_state.edges` mid-swing today, but #781 (bunker edge breaks)
	## will remove edges from it mid-swing. Whatever does that MUST call this
	## before the next [method admit]/[method _kill], or the cached adjacency
	## goes stale and the BFS walks edges that no longer exist. Discards the
	## cache; the next [method _kill] rebuilds it from the mutated
	## `_state.edges` on demand.
	func invalidate_adjacency() -> void:
		_adjacency = {}
		_adjacency_built = false


## `state.edges` as an undirected adjacency map: vertex index -> Array[Vector2i]
## of (neighbour index, EDGE index), in the same order those neighbours would be
## discovered by a linear rescan of `state.edges` for that vertex (#795 —
## preserves [method _reachable_from_pivot]'s traversal order exactly, so
## caching this instead of rescanning is behaviour-preserving, not just
## complexity-preserving).
##
## The edge index rides along so the BFS can skip a SEVERED edge (#785/#781)
## without a second lookup — pairing it into the same Vector2i keeps the walk
## O(V + E) and adds no per-vertex rescan of `state.edges`, which is exactly
## what #785 acceptance 7 forbids. Removed edges are NOT pruned at build time:
## the map is built once per swing and edges are severed during it, so the skip
## has to happen at traversal, and [method LiveGate.invalidate_adjacency] stays
## available for a caller that mutates `state.edges` itself.
static func _build_adjacency(state: BladeState) -> Dictionary:
	var adjacency: Dictionary = {}
	for e_idx in state.edges.size():
		var e := state.edges[e_idx]
		if not adjacency.has(e.x):
			adjacency[e.x] = [] as Array[Vector2i]
		if not adjacency.has(e.y):
			adjacency[e.y] = [] as Array[Vector2i]
		(adjacency[e.x] as Array[Vector2i]).append(Vector2i(e.y, e_idx))
		(adjacency[e.y] as Array[Vector2i]).append(Vector2i(e.x, e_idx))
	return adjacency


## BFS from the pivot over an adjacency map, skipping any vertex in `removed`
## and any EDGE in `removed_edges` (#785 — a bunker that snaps an edge, #781,
## orphans whatever hung off it just as surely as a popped vertex does).
## Returns a set (Dictionary) of reachable particle indices.
##
## `adjacency` defaults to null (untyped so a caller can omit it, as the
## characterization test does): when omitted, this builds a fresh map from
## `state.edges` — still O(V + E) for THIS call, just not amortized across a
## whole swing. [method LiveGate._kill] passes its cached map instead, so a
## swing's repeated pops share the one O(E) build (#795's actual fix; see
## [method LiveGate._ensure_adjacency]).
##
## `removed_edges` defaults to the state's own [member BladeState.removed_edges]
## when omitted (`null`), which is where severance is recorded — an explicit
## `{}` therefore means "walk every edge", not "ask the state".
## `root` defaults to -1, meaning [member BladeState.pivot_index] — the handle,
## for every driven blade. A free fragment (#186) whose root vertex has itself
## died passes an explicit surviving one instead; see
## [method LiveGate._disintegrate_unreachable].
static func _reachable_from_pivot(
		state: BladeState,
		removed: Dictionary,
		adjacency: Variant = null,
		removed_edges: Variant = null,
		root: int = -1) -> Dictionary:
	var adj: Dictionary = adjacency if adjacency != null else _build_adjacency(state)
	var cut: Dictionary = removed_edges if removed_edges != null else state.removed_edges
	var reach: Dictionary = {}
	var pivot := root if root >= 0 else state.pivot_index
	reach[pivot] = true
	var queue: Array[int] = [pivot]
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		var neighbours: Array = adj.get(cur, [])
		for link in neighbours:
			var other: int = (link as Vector2i).x
			if cut.has((link as Vector2i).y):
				continue
			if removed.has(other) or reach.has(other):
				continue
			reach[other] = true
			queue.append(other)
	return reach
