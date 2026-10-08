class_name CritRoll

## The one crit implementation, shared by all three attack modes (#507).
##
## Before this, `crit_chance` / `crit_multiplier` were advertised as UNIVERSAL
## entity stats but only [SpellResolver] ever read them — a player investing in
## crit got nothing from two thirds of their offense, silently. The fix is not
## "add a roll to melee and one to ranged": that is three implementations of
## one rule, and they drift. It is this file, called from one place per clock.
##
## [b]Both halves at landing.[/b] The owner call of 2026-08-21 settled that a
## crit is decided per HIT; the owner call of 2026-10-07 (#1473) moved the
## decision from resolve to the landing itself:
##
## [codeblock]
## Land   CritRoll.decide(hit, rng, world)   draw + conditions -> is_crit,
##                                           crit_multiplier, crit_tier
##        CritRoll.apply(hit)                amount *= crit_multiplier
## [/codeblock]
##
## [method OutcomeApplier.land_one] draws right before the hit lands, in
## landing order, off the outcome's [member AttackOutcome.crit_stream], reading
## the landing world (the shadow during resolve) — so a status landed earlier
## in the same attack (a hex rider) reaches the chance of the hits behind it.
## A replay never draws: a rebuilt [AttackRecord] carries no stream and lands
## the recorded crit. Every crit reader that runs before a landing (the VFX
## stamping [member Projectile.crit_tier], the floaters) reads a REBUILT
## record on the live replay, i.e. after the shadow resolve settled it.
##
## The multiply stays at the tail of [method HitInstance.land_on], after
## ranged's offense read and melee's spike-pop gate, so whatever number those
## settled on is the number that gets multiplied.

## Salt mixed into [member AttackPlan.resolve_seed] to derive the crit stream.
## Crits must NOT consume the propagation stream (#213) — magic's random hop
## choice draws from the same seed, and a crit roll shifting it would make the
## walk depend on how many things happened to crit. Lifted verbatim from
## [PropagationContext] so magic's existing crit stream is bit-identical.
const CRIT_STREAM_SALT: int = 0xC217


## The crit stream for one attack, armed off its stamped
## [member AttackPlan.resolve_seed]. Seed 0 (an unstamped plan — a preview or
## an AI rollout) is a FIXED stream, not a random one: a tooltip that
## reshuffles its crits on every repaint is worse than one showing a stable
## representative roll.
static func stream_for(resolve_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = resolve_seed ^ CRIT_STREAM_SALT
	return rng


## Roll one hit's universal `crit_chance` and settle its crit fields.
##
## Called by [method OutcomeApplier.land_one] as the hit lands; [param world]
## is the landing world. Any condition-path tier already stamped on the hit
## (magic's [member SpellDef.crit_conditions]) is carried in — this only ADDS
## the universal stat path on top. The draw order is the landing order
## ([method OutcomeApplier.in_arrival_order], the structural index, never
## seconds), which is what keeps one seed reproducing one set of crits.
##
## Consumes exactly one draw from [param rng], and only when the hit's folded
## chance ([method chance_for]) is non-zero — a hit with no crit investment
## behind it must not shift the stream for everyone else. A
## zero/negative-amount hit is skipped entirely (nothing to multiply) — save a
## [StatusInstance], which settles a stamped condition tier without drawing — and so
## is one that carries another hit's crit ([method HitInstance.draws_own_crit]
## false) — it draws nothing, so the stream never shifts for it.
## `crit_multiplier` stays an entity read.
static func decide(hit: HitInstance, rng: RandomNumberGenerator,
		world: CombatWorld = null) -> void:
	if hit == null or not hit.draws_own_crit():
		return
	# A status hit crits on its spell's CONDITION tier only (stamped at
	# resolve) and never rolls `crit_chance`: no draw, so no later hit's crit
	# shifts, and an arrow's or a blade's rider (no tier) never crits. Settled
	# ahead of the amount gate — a status hit's amount is 0 until it lands.
	if hit is StatusInstance:
		_settle(hit)
		return
	if hit.amount <= 0.0:
		return
	if rng != null:
		var cc_val := chance_for(hit, world)
		if cc_val > 0.0 and rng.randf() < cc_val:
			hit.crit_tier += 1
	_settle(hit)


## A hit with any crit tier is a crit, at the attacker's `crit_multiplier`.
static func _settle(hit: HitInstance) -> void:
	if hit.crit_tier > 0:
		var board: StatBoard = hit.attacker.stat_board if hit.attacker != null else null
		hit.is_crit = true
		hit.crit_multiplier = multiplier_for(board)


## The hit's folded crit chance: `crit_chance` read LOCALLY off
## [member HitInstance.read_node]'s slice — the owner's entity value with that
## node's own grants folded in — so a node-local grant crits that node's hits
## only. The slice is looked up in [param world] when given, else the node's
## live slice. No read node, or one with no owner board to fold (a fixture, a
## gate flip), falls back to the attacker's entity board; no attacker folds 0.
##
## Every branch also folds the damage target's
## [method NodeCombat.incoming_overlays] (a hexed target's ADD_BONUS lands after
## the attacker's INCREASE / MORE), which is why the draw gate reads this fold
## rather than the attacker's stat alone. A heal gets no overlays.
static func chance_for(hit: HitInstance, world: CombatWorld = null) -> float:
	var overlays := _target_overlays(hit, world)
	if hit.read_node != null:
		var slice: NodeCombat = world.combat_for(hit.read_node) if world != null \
				else hit.read_node.get_combat()
		# A boardless owner would read the def default (5 %) rather than its
		# absent stat, so it takes the entity fallback, which reads 0.
		if slice != null and slice.owner() != null and slice.owner().board() != null:
			var local: Variant = slice.get_local_value_with(&"crit_chance", overlays)
			if local != null:
				return float(local)
	var cc_stat: Stat = hit.attacker.stat_board.get_stat(&"crit_chance") \
			if hit.attacker != null and hit.attacker.stat_board != null else null
	if cc_stat != null:
		return float(cc_stat.get_value_with(overlays))
	return ModifierBins.compute(0.0, overlays)


## The damage target's incoming `crit_chance` overlays, looked up in
## [param world] when given; `[]` for a heal or a targetless hit.
static func _target_overlays(hit: HitInstance, world: CombatWorld) -> Array[ModifierBins]:
	var none: Array[ModifierBins] = []
	if not (hit is DamageInstance) or hit.target == null:
		return none
	var slice: NodeCombat = world.combat_for(hit.target) if world != null \
			else hit.target.get_combat()
	return slice.incoming_overlays(&"crit_chance") if slice != null else none


## The tail-end arithmetic, called once per hit from [method HitInstance.land_on]
## — after ranged's live offense re-read and after melee's spike-pop gate, so
## whatever number those settled on is the number that gets multiplied.
##
## A no-op for a normal hit ([member HitInstance.crit_multiplier] defaults to
## 1.0), which is why the call sites need no `if is_crit`.
static func apply(hit: HitInstance) -> void:
	if hit == null:
		return
	hit.amount *= hit.crit_multiplier


## Reads `crit_multiplier` from the attacker's board, falling back to
## [param fallback] when the board or the stat is missing (a fixture entity,
## a hit with no attacker).
static func multiplier_for(board: StatBoard, fallback: float = 2.0) -> float:
	if board == null:
		return fallback
	var cm_stat: Stat = board.get_stat(&"crit_multiplier")
	if cm_stat == null:
		return fallback
	return cm_stat.get_value()
