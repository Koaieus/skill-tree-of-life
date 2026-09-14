class_name StatusInstance
extends HitInstance

## A single status application produced by an [ApplyStatusEffect] on-hit
## effect (#878, #868 hub) — [HealInstance]/[DamageInstance]'s sibling for the
## third [enum HitInstance.Kind]. Pure data until [method land_on]: the actual
## mutation is [method NodeCombat.apply_status], run against whichever
## [CombatWorld] the applier hands in — a throwaway shadow for a resolve/
## preview pass, the live world for a real landing or a peer's replay of the
## recorded result (`.claude/rules/attack-timeline.md`).
##
## [member HitInstance.amount] / [member HitInstance.effective_amount] both
## carry [member power] once landed, rather than growing a parallel wire
## field — [AttackRecord] already ships every hit's `effective_amount`, so a
## status rides that array for free (#878, see [method AttackRecord.capture]).

## The status this instance applies. Crosses the wire as
## [member Resource.resource_path] ([AttackRecord] `KEY_HIT_STATUS_DEF`),
## never a live reference — same pattern as [PresentationTempo]
## (`attack_record.gd`'s `_tempo_path` / `_tempo_of`). A [StatusDef] built in
## memory with no backing `.tres` therefore cannot survive a record round
## trip; author one under `test/` for anything that needs to.
var def: StatusDef = null
## Power handed to [method NodeCombat.apply_status] — already through
## propagation / board scaling by the time [method ApplyStatusEffect.apply]
## built this instance.
var power: float = 0.0


func _init() -> void:
	kind = Kind.STATUS


## [param node] is a [NodeCombat] — a shadow slice mid-resolve, or the live
## slice on a real landing / a peer's replay (#498 step 3, the same contract
## every other [HitInstance] follows: [member HitInstance.target] stays the
## real identity, [param node] is whichever state this landing mutates).
## [method NodeCombat.apply_status] is already a no-op on a null def, a
## non-positive power, and an unallocated node under a `CLEAR` policy (#872),
## so this does not re-gate any of that.
func land_on(node: NodeCombat, _world: CombatWorld) -> void:
	node.apply_status(def, power)
	amount = power
	effective_amount = power


func _to_string() -> String:
	var name: String = def.display_name if def != null else "<null>"
	return "<StatusInstance %s %.1f → %s>" % [name, power, target]
