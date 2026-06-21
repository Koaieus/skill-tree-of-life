@tool
@abstract
class_name CoreClass
extends Resource

## A class specialization for an Entity — the "head" sitting on the core node.
## Carries stat modifiers that brand the entity (warrior vs glass-cannon vs
## tank), plus optional virtual hooks for behaviors that go beyond pure stats
## (turn-start upkeep, AI policy, attack-plan tweaks).
##
## Concrete subclasses extend this for compile-time class identity. A `.tres`
## per concrete class defines the actual modifier set; designers author them
## via the inspector. Entity composes one as `core_class: CoreClass`, not
## subclasses it — the core IS the entity, but the entity is also more than
## the core (its owned subgraph, its initiative position), so a swappable
## field keeps the Entity contract uniform across runs.

@export var display_name: String = ""
## Persistent modifiers granted by this class. Applied once during
## Entity._ready via `apply()`. Formula-driven entries are duplicated
## automatically — same .tres can sit on many entities safely.
@export var modifiers: Array[StatModifier] = []



## Wire this class onto the given entity. Default applies the modifier set;
## override for classes whose effects don't reduce to modifiers (custom
## signal wiring, scene additions, etc.).
func apply(entity: Entity) -> void:
	if entity.stat_board == null:
		return
	for m in modifiers:
		entity.stat_board.add_modifier(m.duplicate(true))


## Called from Entity._on_turn_started after the entity's own upkeep.
## Default no-op; override for class-specific per-turn behavior
## (mana regen for casters, rage decay for berserkers, etc.).
func on_turn_started(_entity: Entity) -> void:
	pass
