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
## Stacks handed to [method NodeCombat.apply_status]. Until [method land_on]
## runs this is the applier's authored per-hit number ([member
## ApplyStatusEffect.power], `AmmoType.status_power`); land folds the
## attacker's potency and the landing node's resistance into it exactly once
## (#963) and the LANDED number is what [AttackRecord] ships.
var power: float = 0.0
## True once [member power] is the landed number — set by [method land_on]
## on the authority's own resolve and by [method AttackRecord.rebuild], which
## reconstructs the hit flat so a peer's replay lands it rather than scaling
## it a second time (the [member HitInstance.basis] `PERCENT_MAX` precedent).
var power_resolved: bool = false

## Which host the status LANDED on (#996, hub #994). NODE is the ordinary
## landing; ENTITY is the fall-through — the target is its owner's core and
## that core is cracked (`hp.current == 0`) at land time, so the row goes on
## the entity's own [StatusHost] and ticks the `health` pool. Resolved in
## [method land_on] on the authority, alongside [member power_resolved], and
## shipped by [AttackRecord] (`KEY_HIT_STATUS_HOST`) so a peer lands on the
## same host without re-deriving it from node HP.
enum HostKind { NODE, ENTITY }
var host_kind: HostKind = HostKind.NODE


func _init() -> void:
	kind = Kind.STATUS


## [param node] is a [NodeCombat] — a shadow slice mid-resolve, or the live
## slice on a real landing / a peer's replay (#498 step 3, the same contract
## every other [HitInstance] follows: [member HitInstance.target] stays the
## real identity, [param node] is whichever state this landing mutates).
## [method StatusHost.apply_status] is already a no-op on a null def, a
## non-positive power, and an unallocated host under a `CLEAR` policy (#872),
## so this does not re-gate any of that.
##
## Fall-through (#996, owner 2026-09-20 on #994): the status lands on the
## ENTITY iff [param node] is its owner's core AND that core is cracked
## (`hp.current == 0`) at this moment — damage landed earlier in the same
## `outcome.hits` is visible, so an arrow that cracks the core sends its own
## poison through. Decided once, on the authority, into [member host_kind];
## a rebuilt hit lands on the shipped host without re-reading node HP. A
## node-hosted row on the core stays node-hosted: the hosts never merge.
##
## Scaling (`docs/design/damage_over_time.md` §Applying):
## `(power + Σ extra(attacker)) × potency(attacker) × (1 − resistance(host))`,
## the flat extras summed from [member StatusDef.extra_stacks_stat_ids] before
## the multiply, the rest read through the def's [member
## StatusDef.potency_stat_id] / [member StatusDef.resistance_stat_id] — blank
## id, null attacker or an unknown stat each contribute +0 / ×1. Resistance is read on the RECEIVING host — the landing
## node slice (so a shadow resolve sees the shadow's modifiers), or the entity
## board alone on fall-through. Resolved once: a rebuilt hit arrives
## [member power_resolved] and lands as-is.
func land_on(node: NodeCombat, _world: CombatWorld) -> void:
	if not power_resolved:
		if node.is_core() and node.get_current_hp() <= 0.0:
			host_kind = HostKind.ENTITY
	var host = node
	if host_kind == HostKind.ENTITY:
		host = node.owner()
		if host == null:
			# A replay whose node lost its owner to an earlier hit's cascade:
			# nothing to land on, nothing landed (`apply_status` self-gates
			# only on a node).
			amount = 0.0
			effective_amount = 0.0
			return
	if not power_resolved:
		power = (power + _extra_stacks()) * _potency() * (1.0 - _resistance(host))
		power_resolved = true
	host.apply_status(def, power)
	amount = power
	effective_amount = power


func _extra_stacks() -> float:
	if def == null or attacker == null or attacker.stat_board == null:
		return 0.0
	var sum := 0.0
	for id: StringName in def.extra_stacks_stat_ids:
		var v: Variant = attacker.stat_board.get_value(id)
		if v != null:
			sum += float(v)
	return sum


func _potency() -> float:
	if def == null or def.potency_stat_id.is_empty():
		return 1.0
	if attacker == null or attacker.stat_board == null:
		return 1.0
	var v: Variant = attacker.stat_board.get_value(def.potency_stat_id)
	return float(v) if v != null else 1.0


## [param host] is the receiving [StatusHost] owner — a [NodeCombat] or, on
## fall-through, an [EntityCombat]; untyped because the contract is.
func _resistance(host) -> float:
	if def == null or def.resistance_stat_id.is_empty() or host == null:
		return 0.0
	var v: Variant = host.get_local_value(def.resistance_stat_id)
	return float(v) if v != null else 0.0


func _to_string() -> String:
	var name: String = def.display_name if def != null else "<null>"
	return "<StatusInstance %s %.1f → %s>" % [name, power, target]
