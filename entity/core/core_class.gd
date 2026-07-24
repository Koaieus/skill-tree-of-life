@tool
class_name CoreClass
extends Resource

## A class specialization for an Entity — the "head" sitting on the core node.
## Carries stat modifiers that brand the entity (warrior vs glass-cannon vs
## tank), plus optional virtual hooks for behaviors that go beyond pure stats
## (turn-start upkeep, AI policy, attack-plan tweaks).
##
## Most classes are just a `.tres` on this base — a modifier/effect/sigil
## bundle designers author via the inspector. Only classes that need a
## behavioural hook (a custom `apply`, `on_turn_started`, AI policy) subclass
## this; a pure stat/aura class does not (Balanced, Ninja, Serpent all ride
## the plain resource). Entity composes one as `core_class: CoreClass`, not
## subclasses it — the core IS the entity, but the entity is also more than
## the core (its owned subgraph, its initiative position), so a swappable
## field keeps the Entity contract uniform across runs.

@export var display_name: String = ""

@export_multiline var description: String = ""

## Persistent modifiers granted by this class. Applied once during
## Entity._ready via `apply()`. Formula-driven entries are duplicated
## automatically — same .tres can sit on many entities safely.
@export var modifiers: Array[StatModifier] = []

## Behavioural effects granted for the entity's lifetime — auras, per-turn
## rules, anything that doesn't reduce to a flat modifier. Sits alongside
## [member modifiers] rather than replacing it: a pure stat bundle stays a
## bundle. See [Effect].
##
## Each entry is a shared resource (this same `.tres` may brand many entities),
## so effects must keep runtime state on their [EffectInstance], never on
## themselves.
@export var effects: Array[Effect] = []

## Visual identity mark rendered on the HUD hero card ([HeroSigilCard]). `null`
## falls back to the card's default glyph — existing classes without one
## (Pacifist, basic enemy) keep working unchanged. See [Sigil].
@export var sigil: Sigil = null

## The class's turn-start aura radiating from the core's node (D-10). `null`
## means no aura. Applied by [method Entity._on_turn_started], not by
## [method apply] — an aura is re-evaluated every turn against the current
## owned subgraph, not granted once as a static modifier.
@export var aura: CoreAura = null


## Wire this class onto the given entity. Default applies the modifier set and
## grants the effects; override for classes whose behaviour needs custom signal
## wiring or scene additions.
##
## Called from `Entity._ready` once `navigator` exists and `core_location` is
## set — auras read the owned subgraph the moment they're granted.
func apply(entity: Entity) -> void:
	if entity.stat_board == null:
		return
	for m in modifiers:
		entity.stat_board.add_modifier(m.duplicate(true))
	for e in effects:
		entity.grant_effect(e)


## Called from Entity._on_turn_started after the entity's own upkeep.
## Default no-op; override for class-specific per-turn behavior
## (mana regen for casters, rage decay for berserkers, etc.).
func on_turn_started(_entity: Entity) -> void:
	pass
