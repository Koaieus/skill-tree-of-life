@tool
class_name HaulEffect
extends SpellOnHitEffect

## Lodestone's return haul, run at a BACK landing on node Q (gate it with a
## [PhaseCondition] on [constant RetractFront.Phase.BACK]). Reads Q's stacks
## BEFORE this wave lands — the world the walk sees — and:
## [br]• records them on the tendril's [member RetractFront.State.seen], per
## [method RetractSpread.hauled] def (what [RetractSpread] subtracts from the
## node's stacks after landing, to pass on what landed plus the load floor);
## [br]• for each cargo piece (P, d, n), clears n of d off P with one
## [CureInstance] per source (a core's entity pile first, as [CureEffect]);
## [br]• lands one [member StatusInstance.raw] [StatusInstance] per d on Q
## with the summed n — one hit key, so one Greed spend doubles them all.
## Nothing moves twice: the counts are decided here and land verbatim.

## The [RetractFront] whose state this reads and writes.
@export var front_id: StringName = RetractFront.ID


func _apply_spell(lctx: LandingContext) -> void:
	var st := RetractFront.state_of(lctx.payload, front_id)
	if st == null or lctx.node == null:
		return
	for d in RetractSpread.hauled():
		st.seen[d] = roundi(lctx.spot_stacks_of(lctx.node, d.id))
	var cures: Dictionary = {}  # SkillNode -> CureInstance, first-seen order
	var totals: Dictionary = {}  # StatusDef -> int
	for piece: RetractFront.Piece in st.cargo:
		if piece.from == null or piece.def == null or piece.amount <= 0:
			continue
		if not cures.has(piece.from):
			cures[piece.from] = _cure_on(piece.from, lctx)
		var core := mini(piece.amount, roundi(lctx.core_stacks_of(piece.from, piece.def.id)))
		if core > 0:
			(cures[piece.from] as CureInstance).add(piece.def, core, true)
		if piece.amount > core:
			(cures[piece.from] as CureInstance).add(piece.def, piece.amount - core)
		totals[piece.def] = int(totals.get(piece.def, 0)) + piece.amount
	for from: SkillNode in cures:
		lctx.emit(cures[from])
	for d in RetractSpread.hauled():
		if int(totals.get(d, 0)) > 0:
			lctx.emit(_status_on(d, totals[d], lctx))


func _cure_on(from: SkillNode, lctx: LandingContext) -> CureInstance:
	var hit := CureInstance.new()
	hit.source = lctx.payload
	hit.target = from
	hit.origin = lctx.node
	hit.read_node = lctx.read_node
	hit.hit_key = lctx.hit_key
	return hit


func _status_on(d: StatusDef, amount: int, lctx: LandingContext) -> StatusInstance:
	var status := StatusInstance.new()
	status.def = d
	status.power = float(amount)
	status.raw = true
	status.attacker = lctx.attacker
	status.source = lctx.source
	status.target = lctx.target
	status.origin = lctx.origin
	status.read_node = lctx.read_node
	status.structural_key = lctx.structural_key
	status.paired = lctx.paired
	status.hit_key = lctx.hit_key
	return status


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	return "Returning, hauls debuffs home."
