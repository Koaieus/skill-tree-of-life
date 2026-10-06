@tool
class_name ApplyStatusEffect
extends OnHitEffect

## Applies a [StatusDef] on-hit: contributes a [StatusInstance] carrying
## [member def] / [member power] (#878, #868 hub). Unlike [DamageEffect] /
## [HealEffect], the number is this effect's OWN export rather than a read of
## [member CastSpell.damage] — a status spell's magnitude is authored on the
## applier, not derived from the propagated damage figure. Compose alongside
## [DamageEffect] on the same [SpellDef] for a "little damage, applies a
## status" spell (owner's Blindness/Poison ask, #868).
##
## Reads only the mode-agnostic [HitLanding] (ADR 0044), so it works on a
## spell's landing, an arrow's and a blade contact's alike: the emitted
## status copies the landing's attacker / source / origin / read node / target /
## structural key, and rides [member HitLanding.paired] — the status applies
## iff that primary hit landed ([member StatusInstance.paired]).

@export var def: StatusDef = null
@export var power: float = 1.0


func apply(landing: HitLanding) -> void:
	if landing == null or landing.target == null or def == null:
		return
	var status := StatusInstance.new()
	status.def = def
	status.power = power
	# The potency read at land (#963) is the attacker's board.
	status.attacker = landing.attacker
	status.source = landing.source
	status.target = landing.target
	status.origin = landing.origin
	status.read_node = landing.read_node
	status.structural_key = landing.structural_key
	status.paired = landing.paired
	landing.hits.append(status)


## Per #764's contract: a null [param spell] (no preview context) still
## returns a description, just without needing one — [member power] is
## already this effect's own authored number, not a formula input. The
## per-hit line is [method StatusDef.stacks_per_hit] — #1189's fold, the same
## one the landing itself uses — so a null [param board] answers the authored
## [member power] unscaled and a board with the attacker's
## `<family>_stacks_per_hit` folds it in, both trimmed to 2dp.
func get_description(_spell: SpellDef = null, board: StatBoard = null) -> String:
	if def == null:
		return "Applies a status."
	var name := def.display_name if not def.display_name.is_empty() else String(def.id)
	var stacks := def.stacks_per_hit(board, power)
	return "Applies %s (%s per hit)." % [name, NumFmt.num(stacks)]
