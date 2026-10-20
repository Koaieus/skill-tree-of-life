@tool
class_name CleanseEffect
extends SpellOnHitEffect

## A load-capped cleanse on-hit: clears up to [member caps] stacks per status
## off the landed spot — no dose, no drain; the cap is the whole budget. One
## [CureInstance] carries the exact counts (core rows first, then the node,
## one shared cap per status); [member terms] then settle what the clears buy
## or cost ([method CleanseTerm.settle_all]). Nothing to clear emits nothing.
##
## Each cap folds through its status's `<family>_stacks_per_hit` exactly as a
## planted rider does ([method StatusDef.stacks_per_hit_at] over the read
## node's slice in the cast's world). A landing where [member crit_when] holds
## multiplies the folded caps by the caster's `crit_multiplier`
## ([method CritRoll.multiplier_for]) and stamps `crit_tier = 1` on the cure
## hit. The crit lives HERE, not on [member SpellDef.crit_conditions]: those
## stamp after effects run and skip a zero-amount hit, too late to move counts.
##
## Authored as a TEMPLATE shared by an intake's [CleanseUse] rows; a cast runs
## a fresh copy ([method for_cast]) whose [member caps] the rows' loads write.
## Counts are decided on the world the walk reads, never the live node.

## Stacks this cleanse may clear per landing, per status (before the fold).
@export var caps: Dictionary[StatusDef, int] = {}
## What this cleanse does with the stacks it cleared, in order
## ([method CleanseTerm.settle_all]). Empty is a free cleanse.
@export var terms: Array[CleanseTerm] = []
## When true at a landing, the caps multiply by the caster's crit multiplier.
## Null never crits.
@export var crit_when: LandingCondition = null

## The authored template this per-cast copy came from; null on a template.
var template: CleanseEffect = null


## A fresh per-cast copy of this template: its own empty [member caps], the
## template's [member terms] / [member crit_when] by reference (stateless).
func for_cast() -> CleanseEffect:
	var copy := CleanseEffect.new()
	copy.terms = terms
	copy.crit_when = crit_when
	copy.when = when
	copy.template = self
	return copy


func _apply_spell(lctx: LandingContext) -> void:
	var state := lctx.payload
	var spot := lctx.node
	if caps.is_empty() or state == null or spot == null or lctx.cast == null:
		return
	var budget := _folded_caps(lctx)
	var crit := crit_when != null and crit_when.evaluate(lctx)
	if crit:
		var mult := CritRoll.multiplier_for(_caster_board(lctx))
		for def: StatusDef in budget:
			budget[def] = floorf(budget[def] * mult)
	var hit := CureInstance.new()
	var core_part := {}
	for def: StatusDef in budget:
		var n := minf(lctx.core_stacks_of(spot, def.id), budget[def])
		if n > 0.0:
			core_part[def] = n
			budget[def] -= n
	for def: StatusDef in core_part:
		hit.add(def, core_part[def], true)
	for def: StatusDef in budget:
		var n := minf(lctx.stacks_of(spot, def.id), budget[def])
		if n > 0.0:
			hit.add(def, n)
	if hit.defs.is_empty():
		return
	if crit:
		hit.crit_tier = 1
	hit.source = state
	hit.target = spot
	hit.origin = state.predecessor if state.predecessor != null else state.source
	hit.read_node = state.source
	lctx.cast.outcome.hits.append(hit)
	CleanseTerm.settle_all(terms, hit, lctx)


## Each positive cap folded through its status's stacks-per-hit stat, read
## through the read node's slice in the cast's world (the rider's fold).
func _folded_caps(lctx: LandingContext) -> Dictionary:
	var world := lctx.cast.world
	var slice: NodeCombat = world.combat_for(lctx.read_node) if world != null and lctx.read_node != null else null
	var out := {}
	for def: StatusDef in caps:
		if def == null or caps[def] <= 0:
			continue
		var extra: Array[ModifierBins] = []
		if lctx.read_overlays.is_valid():
			extra = lctx.read_overlays.call(def.stacks_stat_id())
		out[def] = def.stacks_per_hit_at(slice, float(caps[def]), extra)
	return out


func _caster_board(lctx: LandingContext) -> StatBoard:
	var caster := lctx.cast.caster
	return caster.stat_board if caster != null else null


## "Cleanses up to 5 Corruption, 20 Curse per hit, the node pays …" — the caps
## as authored (a template's are empty: its rows describe themselves).
func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	var names: Array[String] = []
	for def: StatusDef in caps:
		if def != null:
			names.append("%d %s" % [caps[def], def.display_name if def.display_name != "" else String(def.id)])
	var parts: Array[String] = ["Cleanses up to %s per hit" % (", ".join(names) if not names.is_empty() else "its load")]
	parts.append_array(CleanseTerm.describe_all(terms))
	if crit_when != null and crit_when.get_description() != "":
		parts.append("crits %s" % crit_when.get_description())
	return ", ".join(parts) + "."
