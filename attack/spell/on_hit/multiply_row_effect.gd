@tool
class_name MultiplyRowEffect
extends OnHitEffect

## Multiplies the target's EXISTING row of [member def] by [member factor] —
## the row as it stands when this hit lands, so an [ApplyStatusEffect]
## authored before it in the same list is counted. Unlike [ScaleStacksEffect]
## (which scales the stacks a landing itself mints) this reads the host.
##
## Emits one status hit carrying the increase `row × (factor − 1)`, decided
## at land on the authority's shadow and then [member StatusInstance.power_resolved],
## so the record ships a plain status hit and a replay lands the same number
## (`.claude/rules/attack-timeline.md`). Lands through
## [method StatusHost.apply_status], so it multiplies only under
## [constant StatusDef.Reapply.ACCUMULATE]; a REFRESH def keeps the larger.
## Mode-agnostic: reads only the [HitLanding].

@export var def: StatusDef = null
## The row's multiplier; `1.0` adds nothing. Never below 1 — the row never drops.
@export_range(1.0, 5.0, 0.1) var factor: float = 2.0


func apply(landing: HitLanding) -> void:
	if landing == null or landing.target == null or def == null:
		return
	var hit := _RowMultiply.new()
	StatusInstance.stamp_landing(hit, def, landing)
	hit.factor = factor
	landing.hits.append(hit)


func status_def() -> StatusDef:
	return def


func get_description(_spell: SpellDef = null, _board: StatBoard = null, _read_node: SkillNode = null) -> String:
	var what := def.display_name if def != null and def.display_name != "" else "status"
	return "Multiplies the node's %s ×%s." % [what, NumFmt.num(factor)]


## The landing: the row it reads is the host's own `(def.id, group key)` row
## — the one [method StatusHost.apply_status] writes back into.
class _RowMultiply extends StatusInstance:
	var factor: float = 2.0

	func land_on(node: NodeCombat, world: CombatWorld) -> void:
		if not power_resolved and def != null:
			var key: Variant = def.group_key(_attacker_camp_id(), _attacker_id())
			var row: float = node.get_status_power(def.id, key) if key != null else 0.0
			power = maxf(StatusDef.round_half_up(row * (factor - 1.0)), 0.0)
			power_resolved = true
		super.land_on(node, world)
