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


## Every authored class a slot of this kind may choose, in [method load_all]
## order. [param slot_bit] is [constant PICKABLE_PLAYER] or
## [constant PICKABLE_AI].
##
## This IS the runtime caller [method load_all] flagged as hypothetical: a
## project that exported only scene-referenced resources would quietly return a
## short list here. Nothing strips resources today; revisit at export time.
static func pickable_for(slot_bit: int) -> Array[CoreClass]:
	var out: Array[CoreClass] = []
	for core in load_all():
		if core.is_pickable_in(slot_bit):
			out.append(core)
	return out


## May a slot carrying [param slot_bit] choose this class?
func is_pickable_in(slot_bit: int) -> bool:
	return (pickable_in & slot_bit) != 0


## The [member pickable_in] bit for a human lobby slot.
const PICKABLE_PLAYER := 1
## The [member pickable_in] bit for an AI lobby slot.
const PICKABLE_AI := 2


## Which lobby slots may CHOOSE this class (#618 D6). A property OF the class
## ("this is an enemy archetype"), true wherever it is offered — a lobby-side
## allow-list would be a second place to update every time a core is authored.
##
## [b]`0` — "neither" — is the deliberate default.[/b] A newly authored core is
## invisible in every picker until somebody opts it in, so a class added for a
## boss, a test, or an unfinished experiment cannot leak into the lobby by
## merely existing.
##
## Composes with, rather than duplicates, the per-route `LobbyPolicy` (#615):
## the mask says WHAT A CORE IS, the policy says whether this lobby lets that
## slot choose at all.
##
## Deliberately NOT typed against [enum Participant.Kind] — [Participant] gains
## a [CoreClass] field of its own, and a mutual `class_name` reference between
## the two is exactly the resolution cycle `.claude/rules/godot-workflow.md`
## warns about. Callers translate a kind to a bit; see
## [method LobbyScreen.slot_bit_for].
@export_flags("Player slots", "AI slots") var pickable_in: int = 0

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
##
## No per-entry duplication (#377) — the same shared `.tres` modifier instance
## applies safely to every entity of this class; binding lives on each
## entity's own board, so each computes independently. Nothing mutates a
## CoreClass modifier's `value` at runtime (that's the #376 mutator's job,
## scoped to SkillNode's own `modifiers`/`_local_modifiers`, never a class's).
##
## Routes through [method Entity.grant_core_modifier] (#323) — the register's
## sole write path — rather than `entity.stat_board.add_modifier` directly, so
## a class-template grant seeds [member Entity.core_modifiers] the same way a
## looted grant does. Still no per-entry duplication (unchanged from #377):
## `grant_core_modifier` mirrors `m` onto the board as-is.
func apply(entity: Entity) -> void:
	if entity.stat_board == null:
		return
	for m in modifiers:
		entity.grant_core_modifier(m)
	for e in effects:
		entity.grant_effect(e)


## Called from Entity._on_turn_started after the entity's own upkeep.
## Default no-op; override for class-specific per-turn behavior
## (mana regen for casters, rage decay for berserkers, etc.).
func on_turn_started(_entity: Entity) -> void:
	pass
