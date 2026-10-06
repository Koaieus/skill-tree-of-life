class_name ExertInstance
extends HitInstance

## One node of an attack's ORIGIN SET exerting itself at launch — no HP,
## [member amount] stays 0, so [method CritRoll.decide] draws nothing for it.
## Lands on [member target]'s slice through [method NodeCombat.exert], which
## hands every status row on that host its [method StatusDef._on_exerted]; a
## status that reacts to exertion lives in its def, never here.
##
## Minted one per distinct origin node at [member structural_key] 0 (the
## attack's first beat): ranged — every leaf that fired the volley; melee —
## every node copied onto the blade, pivot included; magic — the cast source
## plus its owned neighbours. [member origin] stays null on purpose — it is
## the VFX spawn point, and an exertion draws nothing — so every reader that
## spawns a tracer off `origin` passes it by. Readers that count shots or
## damage skip it by CLASS.
##
## On the wire it is just a kind, a target and an attacker: [method
## AttackRecord.rebuild] mints this class back from [constant Kind.EXERT].


func _init() -> void:
	kind = Kind.EXERT


static func at(node: SkillNode, by: Entity, src: Variant = null) -> ExertInstance:
	var e := ExertInstance.new()
	e.target = node
	e.attacker = by
	e.source = src
	e.structural_key = 0.0
	return e


func land_on(node: NodeCombat, _world: CombatWorld) -> void:
	effective_amount = 0.0
	node.exert()


func _to_string() -> String:
	return "ExertInstance(%s)" % [target]
