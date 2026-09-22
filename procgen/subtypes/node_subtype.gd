@tool
class_name NodeSubtype
extends Resource

## A node's second identity, orthogonal to [Archetype]: `regular` / `blight` /
## `bless`. Archetype picks the family, subtype picks the pole.
##
## A Resource rather than an enum or a StringName because subtype crosses three
## layers — procgen selects on it, [SkillNode] carries it, the visuals read it —
## and the thing crossing those layers must carry DATA (a tint, an emissive
## tier). An enum would force a `match` in each layer; a new subtype would then
## mean editing all three. [Archetype] is already exactly this shape.
##
## The gate lives on [member StatPool.subtypes], NOT here: a pool states which
## subtypes may draw it, which makes "blighted DEX trades crit% for DoT stats"
## one line of authoring on the crit pool, per-archetype, with no second
## mechanism. See docs/design/node_subtypes.md.

## Stable identity. `&"regular"` is the default every node falls back to.
@export var id: StringName = &"":
	set(v):
		id = v
		resource_name = String(v)

@export var display_name: String = ""

## Composed into [NodeVisualsComposite]'s existing `feedback_tint × status_tint`
## modulate chain — WHITE is the identity element, so `regular` contributes
## nothing. Zero new instance-uniform slots: nodes already bind ~18 of a global
## 4096 cap. See .claude/rules/rendering-performance.md.
@export var tint: Color = Color.WHITE

## Bloom tier. A thing glows iff its colour exceeds 1.0 — `bless` takes a tier
## and picks up the existing WorldEnvironment pass for free, `blight` is DARK
## and must stay at INERT. See .claude/rules/hdr-color.md.
@export var emissive_tier: Emissive.Tier = Emissive.Tier.INERT

## This subtype's share of the per-node placement roll. The default subtype is
## the remainder and authors none.
@export_range(0.0, 1.0) var base_chance: float = 0.0


## The canonical default, used wherever a preset authors no override.
##
## GOTCHA: this is a lazy static accessor and NOT `const REGULAR := preload(…)`.
## `regular.tres`'s own script IS this class, so a class-scope preload is a
## cyclic load. Same idiom [StatPool] uses for `TagRegistry.canonical()`.
static var _regular: NodeSubtype = null

static func regular() -> NodeSubtype:
	if _regular == null:
		_regular = load("res://procgen/subtypes/regular.tres") as NodeSubtype
	return _regular
