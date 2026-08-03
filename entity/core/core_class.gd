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

## Directory every authored CoreClass `.tres` lives in. A `const`, not an
## `@export` — where classes live is a fact about the class, not per-resource
## data, and `@export` cannot be applied to a `static var` at all (parse error
## in Godot 4; see .claude/rules/godot-workflow.md).
const DIR := "res://entity/core/"


## Every authored CoreClass resource on disk. Discovers rather than enumerates,
## so a newly authored class is covered by anything that asks — today that is
## test_stat_dependency_graph.gd's board-vs-class DAG check (#322), which used
## to carry a hand-maintained preload list that silently went stale.
##
## Deliberately does NOT assert the result is non-empty: "there should be about
## five of these" is a claim about shipped content and belongs in a test, not in
## a loader that a stripped build or a mod directory could legitimately empty.
##
## If a RUNTIME caller ever appears (class-select UI, procgen enemy rolls), note
## that a project exporting only selected resources would strip any core class
## no scene references, and this would quietly return a short list.
static func load_all() -> Array[CoreClass]:
	var out: Array[CoreClass] = []
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".tres"):
			continue
		var res := load(DIR.path_join(file))
		if res is CoreClass:
			out.append(res)
	return out


@export var display_name: String = ""

@export_multiline var description: String = ""

## Composition by reference (D-27, #279): a shared batch of modifiers/effects
## authored once and reused across many CoreClass `.tres` — edit the base,
## every class composing it changes. [method apply] walks the base first, then
## this class's own `modifiers`/`effects`; PURE APPEND, never override-by-
## stat_id (the stat pipeline already stacks modifiers natively — "weaker than
## the base" is a negative modifier, not a replace rule). `null` means no base.
@export var inherits: CoreClass = null

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
## Walks the [member inherits] chain base-first (D-27, #279) before applying
## this class's own modifiers/effects, so a base's grants land first and a
## child's stack on top of them — pure append, never an override.
##
## Called from `Entity._ready` once `navigator` exists and `core_location` is
## set — auras read the owned subgraph the moment they're granted.
func apply(entity: Entity) -> void:
	if entity.stat_board == null:
		return
	for c in _chain([]):
		for m in c.modifiers:
			entity.stat_board.add_modifier(m.duplicate(true))
		for e in c.effects:
			entity.grant_effect(e)


## Read-only flattened view of the [member inherits] chain's modifiers,
## base-first (same order [method apply] installs in, so a caller that only
## needs to inspect the composed set doesn't have to duplicate the walk).
## UNLIKE [method apply], does NOT duplicate — this is a template a caller
## reads, not an install. [b]Consumer:[/b] [method LootSystem._core_modifiers]
## reads this instead of [member modifiers] directly, so the loot draw sees
## the composed set (e.g. `attribute_baseline_core`'s STR/DEX/INT) rather than
## just what this `.tres` declares itself (#279). A future change to the chain
## contract must keep both ends (there and here) in sync.
func all_modifiers() -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for c in _chain([]):
		out.append_array(c.modifiers)
	return out


## Shared walk behind [method apply] and [method all_modifiers]: this class
## and every ancestor via [member inherits], base-first. `visited` guards
## against an inheritance cycle (A inherits B inherits A) — detected rather
## than left to hang, and reported with push_error since a cyclic `.tres`
## graph is an authoring bug, not a runtime condition to silently swallow.
func _chain(visited: Array[CoreClass]) -> Array[CoreClass]:
	if visited.has(self):
		push_error(
			"CoreClass.apply: inheritance cycle detected at '%s' — 'inherits' chain never terminates"
			% resource_path
		)
		return []
	visited.append(self)
	var out: Array[CoreClass] = []
	if inherits != null:
		out.append_array(inherits._chain(visited))
	out.append(self)
	return out


## Called from Entity._on_turn_started after the entity's own upkeep.
## Default no-op; override for class-specific per-turn behavior
## (mana regen for casters, rage decay for berserkers, etc.).
func on_turn_started(_entity: Entity) -> void:
	pass
