class_name RangedDamageFormula

## Pure-function damage formula for a single ranged shot. One hit per firing
## position; RangedAttackPlan.resolve() loops the authored firing schedule
## and accumulates DamageInstances.
##
## Per-shot model deliberately: lets future flat armour reduce each impact
## instead of one big number, and supports staggered VFX hits.
##
## Reads `ranged_damage` from the firing node's local stat board — the
## entity board intrinsic formula (`floor(DEX / 10.0)`) plus any node-local
## addons contribute to the value, so the UI and resolver stay dumb.
##
## Timing is NOT this function's job — see docs/domain/attack-timeline.md
## "The ranged volley ramp". `arrival_time` used to be `distance /
## PROJECTILE_SPEED`, which let allocation order leak into combat outcome
## (a near leaf firing third could still land before a far leaf firing
## first). The ramp is authored against the volley's own distance span
## instead: RangedAttackPlan.resolve_against() normalizes each reaching
## leaf's distance to target into 0..1 across [d_min, d_max] and stamps it
## onto `HitInstance.structural_key` — seconds are assigned later, by
## `OutcomeSchedule.compile()`'s `Cadence.RAMP` branch, off
## `PresentationTempo.volley_draw_time` / `volley_stagger_span` /
## `volley_flight_time` (#543). `compute()` itself leaves `arrival_time` at
## the HitInstance default (0.0) — it never had seconds to stamp.

## [param ammo_type] is the arrow this shot spends (#957) — stamped onto the
## hit so the landing knows what it was, and (#495) scaling the loosed amount
## by [member AmmoType.damage_scale] BEFORE mitigation (owner 2026-09-18:
## "reduced raw damage + added poison status stacks"). Null is a plain base
## shot. The type's status, if any, is a second hit — see [method status_for].
static func compute(attacker: Entity, firing_node: SkillNode, target: SkillNode,
		ammo_type: AmmoType = null) -> DamageInstance:
	var hit := RangedHitInstance.new()
	hit.attacker = attacker
	hit.ammo_type = ammo_type
	hit.type = DamageInstance.Type.PHYSICAL
	hit.target = target
	hit.origin = firing_node
	hit.amount = _read_offense(firing_node.get_combat() if firing_node != null else null)
	if ammo_type != null:
		hit.amount *= ammo_type.damage_scale
	return hit


## The status a typed arrow applies on landing (#495), as a second hit for
## the SAME landing as [param hit] — null when the arrow carries no
## [member AmmoType.status_def]. Same construction as
## [method ApplyStatusEffect.apply] (magic's on-hit), deliberately NOT routed
## through the spell stub (owner 2026-09-18: "magic will most likely NOT have
## anything to do with poison arrows"). The caller appends it right after its
## arrow: [member HitInstance.structural_key] is copied so both land on one
## beat, and the later original index keeps the arrow first
## ([method OutcomeSchedule.compile]). A volley's many arrows on one node
## therefore re-apply under the def's [member StatusDef.reapply] rule —
## `ACCUMULATE` on poison is what makes ranged the poison specialist.
##
## Rides the wire for free: [AttackRecord] serialises any `Kind.STATUS` hit by
## its def's `resource_path`, and a gated dud replays as power 0, which
## [method NodeCombat.apply_status] ignores.
static func status_for(hit: DamageInstance) -> StatusInstance:
	var arrow := hit as RangedHitInstance
	if arrow == null or arrow.ammo_type == null:
		return null
	var def := arrow.ammo_type.status_def as StatusDef
	if def == null:
		return null
	var status := RangedStatusInstance.new()
	status.def = def
	status.power = arrow.ammo_type.status_power
	status.attacker = arrow.attacker
	status.source = arrow.source
	status.target = arrow.target
	status.origin = arrow.origin
	status.structural_key = arrow.structural_key
	return status


## Ranged's land-time GATE (#503), shared by the arrow and its status (#495)
## so the two never disagree on whether a landing is a dud: false if the
## target is no longer allocated/hostile to [param attacker], or the firing
## node's slice ([param origin_slice], looked up in the landing world) is
## gone. A veto is a veto, not a re-plan — callers mark
## [member HitInstance.gated] and mutate nothing.
static func passes_gate(attacker: Entity, node: NodeCombat, origin_slice: NodeCombat) -> bool:
	if origin_slice == null or not origin_slice.is_allocated():
		return false
	if node == null or not node.is_allocated():
		return false
	return node.ownership_bit(attacker) == SkillNode.Ownership.HOSTILE


## The firing node's slice in the world this hit is landing in — the gate's
## allocation check must come from THAT world, or a shadow would ask the real
## board whether a node this volley already cost the firer is still theirs.
static func _origin_slice_of(hit: HitInstance, world: CombatWorld) -> NodeCombat:
	if hit.origin != null and is_instance_valid(hit.origin):
		return world.combat_for(hit.origin)
	return null


## The one read of "what does this firing node's shot deal", called by
## [method compute] as each shot is scheduled — i.e. at LAUNCH, before any
## arrow in the volley has landed.
##
## [b]There is no land-time re-read any more (owner call 2026-08-23).[/b] #503
## added one here; it is gone. An arrow is loosed with the damage it was loosed
## with, and a shot already in flight does not consult the archer again:
##
## [i]"recalculating while arrows are mid-flight makes no sense... if the first
## 2 arrows kill the target, it'd be for the remaining 3 arrows, which do
## nothing"[/i]
##
## That last clause is why nothing is lost: a volley that overkills its target
## does not need stale damage corrected, because [method
## RangedHitInstance._passes_gate] vetoes those arrows outright. The GATE stays
## live; only the arithmetic froze. See docs/domain/attack-timeline.md, "Offense
## is snapshotted at commit time".
##
## Takes the firing node's [NodeCombat] rather than the [SkillNode] (#498 step
## 3) because [method NodeCombat.get_local_value] is the same merge
## [method SkillNode.get_local_value] delegates to — same value, one spelling.
static func _read_offense(firing_slice: NodeCombat) -> float:
	if firing_slice == null:
		return 0.0
	return float(firing_slice.get_local_value(&"ranged_damage"))


## Ranged's land-time GATE (#503) — the ranged sibling of [BladeDamageInstance]
## (#502, `attack/melee/sim/blade_damage_instance.gd`). [method land_on] is
## called once per hit by [OutcomeApplier] in [member HitInstance.arrival_time]
## order (docs/domain/attack-timeline.md).
##
## The gate is the ONLY live read here. The `amount` [method compute] stamped at
## launch is the amount that lands — see [method RangedDamageFormula._read_offense]
## for the owner call that removed the land-time re-read.
class RangedHitInstance extends DamageInstance:
	## The [AmmoType] this arrow was (#957); null for a plain base shot.
	var ammo_type: AmmoType = null
	## The attacker this shot was fired for is [member HitInstance.attacker] —
	## promoted to the base class in #507 so the shared [CritRoll] can read its
	## board. Needed here at land time to re-check the target is still HOSTILE
	## to them, not just still allocated (a node can be captured by a third
	## party mid-volley).

	## Veto — no mutation at all, per the contract's "gate is a veto, not a
	## re-plan" — if the target is no longer allocated/hostile, or the firing
	## node ([member HitInstance.origin]) is no longer allocated. A mid-volley
	## cascade can deallocate either: the target (this volley's own overkill)
	## or the origin (a DIFFERENT attack, or this volley's own forced-dealloc
	## cascade, islanding the firing leaf). A veto marks [member
	## HitInstance.gated] so VFX can render the dud beat distinctly from a
	## hit that landed and fully mitigated to zero.
	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		if not RangedDamageFormula.passes_gate(attacker, node,
				RangedDamageFormula._origin_slice_of(self, world)):
			gated = true
			return
		super.land_on(node, world)


## The status half of a typed arrow's landing (#495), built by [method
## RangedDamageFormula.status_for]. Same gate as [RangedHitInstance] — a dud
## arrow applies no status — and a vetoed one lands as power 0 so the record
## carries a zero that [method NodeCombat.apply_status] ignores on replay.
class RangedStatusInstance extends StatusInstance:
	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		if not RangedDamageFormula.passes_gate(attacker, node,
				RangedDamageFormula._origin_slice_of(self, world)):
			gated = true
			power = 0.0
			amount = 0.0
			effective_amount = 0.0
			return
		super.land_on(node, world)
