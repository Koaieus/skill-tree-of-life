@tool
class_name BladeStyle
extends Resource
## Look profile for the phantom blade's [BladeNode] / [BladeEdge] visuals (#256).
##
## Same shape as [GlowStyle]: the knobs live on the resource, every setter calls
## `emit_changed()` (a custom Resource does NOT auto-emit — see GlowStyle's
## header), and each consumer connects once. Beyond holding colours it owns two
## rules that must not be re-implemented per visual:
##
##   * [b]Identity tint.[/b] A blade is a 1:1 copy of the wielder's own nodes, so
##     it carries the wielder's colour: [member entity_tint] is how far the
##     authored base is pulled toward [member Entity.color]. Disc, rim and edge
##     stroke all read the same blend, so a tint cannot drift between them.
##   * [b]Disabled = the interim "pop".[/b] Until the real pop VFX exists (#256),
##     a blade part that died mid-swing reads as [i]de-lit[/i]: dropped below the
##     bloom threshold and desaturated — HDR → SDR. Owner call (2026-08-21):
##     model the pop this way first, so there is instant feedback on which parts
##     of the blade are still live. A stand-in for the animation, not the
##     animation.
##
## Colours are authored as [Emissive] tiers over a base, never as hand-picked
## floats (`.claude/rules/hdr-color.md`).

## Base hue of an ordinary blade member, before the identity tint and before any
## tier is applied.
@export var member_base: Color = Color.FIREBRICK:
	set(value):
		member_base = value
		emit_changed()
## Base hue of the pivot — the handle the swing is driven around.
@export var pivot_base: Color = Color.CHOCOLATE:
	set(value):
		pivot_base = value
		emit_changed()
## How far the bases are pulled toward the wielder's [member Entity.color].
## 0 = authored base only (the pre-#256 look), 1 = pure identity colour.
@export_range(0.0, 1.0) var entity_tint: float = 0.55:
	set(value):
		entity_tint = value
		emit_changed()

## Emissive tier of the node rim. A thin stroke has low coverage and needs the
## full stop to read as lit.
@export_range(-2.0, 4.0, 0.05) var rim_tier: float = Emissive.VALUE:
	set(value):
		rim_tier = value
		emit_changed()
@export_range(0.5, 12.0, 0.5) var rim_width: float = 2.0:
	set(value):
		rim_width = value
		emit_changed()
## Emissive tier of the node fill. A large disc blows out at the rim's tier, so
## it sits a step lower by default (`.claude/rules/skill-node-scale.md`).
@export_range(-2.0, 4.0, 0.05) var fill_tier: float = Emissive.LABEL:
	set(value):
		fill_tier = value
		emit_changed()
@export_range(0.0, 1.0) var fill_alpha: float = 0.7:
	set(value):
		fill_alpha = value
		emit_changed()

## Emissive tier of the edge stroke connecting two blade nodes.
@export_range(-2.0, 4.0, 0.05) var edge_tier: float = Emissive.VALUE:
	set(value):
		edge_tier = value
		emit_changed()
@export_range(0.5, 12.0, 0.5) var edge_width: float = 2.0:
	set(value):
		edge_width = value
		emit_changed()

## Tier a DISABLED (popped / severed) part is redrawn at. Below
## [constant Emissive.INERT] on purpose: the point is that it stops glowing.
@export_range(-3.0, 2.0, 0.05) var disabled_tier: float = -1.0:
	set(value):
		disabled_tier = value
		emit_changed()
## How much saturation a disabled part loses. 1 = fully grey.
@export_range(0.0, 1.0) var disabled_desaturation: float = 0.75:
	set(value):
		disabled_desaturation = value
		emit_changed()
## Alpha multiplier on a disabled part — it lingers as a husk rather than
## vanishing, so you can see WHERE the blade lost a piece.
@export_range(0.0, 1.0) var disabled_alpha: float = 0.55:
	set(value):
		disabled_alpha = value
		emit_changed()


## The blade's base hue for one part, identity tint applied. `entity_color` is
## the wielder's colour; pass [constant Color.TRANSPARENT] for an ownerless
## blade (test fixtures) and the authored base comes back untouched.
func base_for(is_pivot: bool, entity_color: Color) -> Color:
	var base := pivot_base if is_pivot else member_base
	if entity_color.a <= 0.0 or entity_tint <= 0.0:
		return base
	var tinted := base.lerp(entity_color, entity_tint)
	tinted.a = base.a
	return tinted


func fill_color(is_pivot: bool, entity_color: Color, disabled: bool) -> Color:
	var c := _lit(base_for(is_pivot, entity_color), fill_tier, disabled)
	c.a *= fill_alpha
	return c


func rim_color(is_pivot: bool, entity_color: Color, disabled: bool) -> Color:
	return _lit(base_for(is_pivot, entity_color), rim_tier, disabled)


func edge_color(entity_color: Color, disabled: bool) -> Color:
	return _lit(base_for(false, entity_color), edge_tier, disabled)


## The one place "lit" and "de-lit" are decided, so every blade visual dims by
## the same rule. A disabled part swaps the requested tier for
## [member disabled_tier] and bleeds saturation — it does not merely fade,
## because alpha is the fade channel and colour value is the dimmer
## (see [Emissive]).
func _lit(base: Color, tier: float, disabled: bool) -> Color:
	if not disabled:
		return Emissive.at(base, tier)
	var muted := base
	muted.s *= 1.0 - disabled_desaturation
	var c := Emissive.at(muted, disabled_tier)
	c.a *= disabled_alpha
	return c
