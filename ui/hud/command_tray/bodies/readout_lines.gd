class_name ReadoutLines
extends RefCounted

## The crucible readout's aspect lines — one per aspect a cast lands, phrased
## as a behaviour change: `+ applies 95 poison stacks per hit (15 innate + 80
## infused)`. Socketed aspects first, in socket order (the insertion order of
## [member Infusion.points]), then the spell's innate-only aspects in authored
## order. Pure statics: the plan owns the points, [method Infusion.load_of]
## the load, [method StatusDef.stacks_per_hit] the per-hit fold and
## [InfusionExchange] the exchange text — nothing here derives a second number.


## One aspect in play.
class ReadoutLine extends RefCounted:
	## The concept id (`&"poison"`).
	var aspect_id: StringName = &""
	## Index of the socket holding this aspect, −1 for an innate-only aspect.
	var socket: int = -1
	## Points the cast spends on this aspect (0 when innate-only).
	var points: int = 0
	## The spell's innate load of the concept, summed over its listed rows.
	var innate: int = 0
	## The load the spent points add: [method Infusion.gained].
	var infused: int = 0
	## Stacks one hit lands: `innate + infused` through the status's fold.
	var per_hit: float = 0.0
	## The status the concept lands.
	var status: StatusDef = null

	## `innate + infused` — the plan's [method Infusion.load_of] entry.
	func total() -> int:
		return innate + infused

	## The behaviour-change line, as [BadgeText] (`{poison:4}` is the hoverable
	## concept token).
	func text() -> String:
		var parts: PackedStringArray = []
		if innate > 0:
			parts.append("%d innate" % innate)
		if infused > 0 or socket >= 0:
			parts.append("%d infused" % infused)
		return "+ applies {%s:%s} stacks per hit (%s)" % [aspect_id, NumFmt.num(per_hit),
				" + ".join(parts)]

	## The socket's exchange line ([method InfusionExchange.line]); "" innate-only.
	func exchange(spell: SpellDef) -> String:
		if socket < 0:
			return ""
		return InfusionExchange.line(spell, aspect_id, points)

	## The listed [AspectIntake] of [param spell] for this concept, or null.
	func intake_of(spell: SpellDef) -> AspectIntake:
		return Infusion.intake_of(spell, aspect_id)


## [param plan]'s lines as configured.
static func lines(plan: MagicAttackPlan) -> Array[ReadoutLine]:
	if plan == null or plan.spell == null:
		return for_infusion(null, null, null)
	return for_infusion(plan.spell, _board_of(plan), plan.infusion)


## [param plan]'s lines were [param aspect_id] socketed at [param socket] —
## the write [method MagicAttackPlan.set_socket] would make, displacement and
## depth re-walk included, without making it.
static func preview(plan: MagicAttackPlan, socket: int, aspect_id: StringName) -> Array[ReadoutLine]:
	if plan == null or plan.spell == null:
		return for_infusion(null, null, null)
	var points := plan.socket_points(plan.socket_order_with(socket, aspect_id))
	return for_infusion(plan.spell, _board_of(plan), Infusion.for_cast(plan.spell, points))


## The lines [param infusion] lands for [param spell] on [param board]'s fold.
## Aspects landing nothing, or with no status, are dropped.
static func for_infusion(spell: SpellDef, board: StatBoard, infusion: Infusion) -> Array[ReadoutLine]:
	var out: Array[ReadoutLine] = []
	if spell == null:
		return out
	if infusion == null:
		infusion = Infusion.innate(spell)
	var counts := infusion.load_of(spell)
	var innate_of: Dictionary[StringName, int] = {}
	for intake in spell.intakes:
		if intake != null and intake.identity != null:
			var id := intake.aspect_id()
			innate_of[id] = innate_of.get(id, 0) + intake.innate
	var order: Array[StringName] = []
	order.assign(infusion.points.keys())
	for id in counts:
		if not order.has(id):
			order.append(id)
	var sockets := infusion.points.keys()
	for id in order:
		var total: int = counts.get(id, 0)
		var status := status_of(spell, id)
		if total <= 0 or status == null:
			continue
		var line := ReadoutLine.new()
		line.aspect_id = id
		line.socket = sockets.find(id)
		line.points = infusion.points.get(id, 0)
		line.innate = innate_of.get(id, 0)
		line.infused = total - line.innate
		line.status = status
		line.per_hit = status.stacks_per_hit(board, float(total))
		out.append(line)
	return out


## The status concept [param id] lands for [param spell]: the concept's roster
## status — the lookup [method Infusion.riders] makes.
static func status_of(_spell: SpellDef, id: StringName) -> StatusDef:
	return StatusRoster.shared().by_concept(id)


static func _board_of(plan: MagicAttackPlan) -> StatBoard:
	return plan.attacker.stat_board if plan.attacker != null else null
