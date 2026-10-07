class_name CritRoll

## The one crit implementation, shared by all three attack modes (#507).
##
## Before this, `crit_chance` / `crit_multiplier` were advertised as UNIVERSAL
## entity stats but only [SpellResolver] ever read them — a player investing in
## crit got nothing from two thirds of their offense, silently. The fix is not
## "add a roll to melee and one to ranged": that is three implementations of
## one rule, and they drift. It is this file, called from one place per clock.
##
## [b]Two clocks, deliberately.[/b] The owner call of 2026-08-21 settled that a
## crit is decided per HIT (not per swing / per volley) and that landing is the
## tail end of resolution, so:
##
## [codeblock]
## Resolve   CritRoll.decide_all(outcome, rng)   draw + conditions -> is_crit,
##                                               crit_multiplier, crit_tier
##                                               (amount is NOT touched)
## Land      CritRoll.apply(hit)                 amount *= crit_multiplier
## [/codeblock]
##
## Why the split rather than doing both at either end:
##
## - The DECISION cannot wait for land. [MagicBounceCoordinator] stamps
##   [member Projectile.crit_tier] when it spawns the bolt and [Projectile]
##   fires `_on_crit` at flight start — both strictly BEFORE the applier lands
##   that wave. A land-time decision makes every magic projectile read tier 0.
##   Magic's [member SpellDef.crit_conditions] are resolve-bound anyway: they
##   read [CastSpell] propagation state that only exists inside
##   [SpellResolver]'s wave loop.
## - The MULTIPLY cannot happen at resolve. [RangedDamageFormula]'s
##   `RangedHitInstance.land_on` overwrites `amount` with a LIVE
##   `ranged_damage` read (#503), so anything resolve multiplied in is thrown
##   away. Putting the multiply at the tail is also what
##   `docs/domain/attack-timeline.md` asks for — "set frozen, all arithmetic
##   live".
##
## The residual: `crit_chance` / `crit_multiplier` are read at resolve, so a
## mid-attack change to either is not seen by hits already in flight. That is
## the whole delta, and it is smaller than the VFX regression the alternative
## buys.

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


## Decide the crit for every hit in [param outcome], drawing from [param rng]
## in LANDING order — [member HitInstance.schedule_index], the structural entry
## index, never seconds (#543 D2).
##
## [b]The order is load-bearing.[/b] One stream serves the whole attack, so if
## two modes consumed it in different orders the same `resolve_seed` would stop
## reproducing the same crits and the determinism contract
## (`docs/domain/multiplayer-sync-model.md`) would be lost. Arrival order is
## the order landings apply (#499/#503), so it is the one order every mode
## already agrees on. Reuses [method OutcomeApplier.in_arrival_order] rather
## than re-sorting, so the two can never disagree.
##
## [b]That order had to stop being a float[/b] the moment #543 made seconds
## tempo-dependent and tempo a per-peer [member GameSettings.combat_time_scale]:
## two players at different combat speeds hold different `arrival_time`s for the
## same landing, so a stream drawn in seconds order would deal different crits
## on each machine off the same seed — a desync no test sorting on the same
## wrong key could see. The structural index is identical on every peer by
## construction.
##
## Any condition-path tier already stamped on a hit (magic's
## [member SpellDef.crit_conditions], see [method SpellResolver._stamp_crit_conditions])
## is carried in — this only ADDS the universal stat path on top.
static func decide_all(outcome: AttackOutcome, rng: RandomNumberGenerator,
		world: CombatWorld = null) -> void:
	if outcome == null:
		return
	for hit in OutcomeApplier.in_arrival_order(outcome.hits):
		decide(hit, rng, world)


## Roll one hit's universal `crit_chance` and settle its crit fields.
##
## Consumes exactly one draw from [param rng], and only when the hit's folded
## chance ([method chance_for]) is non-zero — a hit with no crit investment
## behind it must not shift the stream for everyone else. A
## zero/negative-amount hit is skipped entirely (nothing to multiply).
## `crit_multiplier` stays an entity read.
static func decide(hit: HitInstance, rng: RandomNumberGenerator,
		world: CombatWorld = null) -> void:
	if hit == null or hit.amount <= 0.0:
		return
	var board: StatBoard = hit.attacker.stat_board if hit.attacker != null else null
	if rng != null:
		var cc_val := chance_for(hit, world)
		if cc_val > 0.0 and rng.randf() < cc_val:
			hit.crit_tier += 1
	if hit.crit_tier > 0:
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
