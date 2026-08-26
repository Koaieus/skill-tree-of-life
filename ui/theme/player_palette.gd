@tool
class_name PlayerPalette
extends Resource

## The colours a lobby slot may pick a hero from (#616). Authored once as
## `ui/theme/player_palette.tres`; the lobby assigns defaults round-robin and
## the per-slot picker overrides.
##
## [b]Distinct from the stat palette.[/b] `.claude/rules/ui-palette.md` makes
## [member StatDef.tint_color] the source of truth for attribute/vital colours
## and forbids a second resource restating them — this is not that. A hero's
## identity colour answers "whose is this", not "which stat is this", so it is
## its own axis and its own resource. Nothing here is read back into a stat
## colour, and nothing reads values out of `ui/theme/editor_swatches.tres`.
##
## [b]Two colours are deliberately absent, and both absences are load-bearing:[/b]
##
## [b]1. Gold.[/b] Reserved for pure positives (same rule file) — reward, never
## identity. The generator below therefore skips the hue band `[62, 112)`
## outright rather than trusting an author to eyeball it.
##
## [b]2. Pure white.[/b] [member Participant.color] defaults to
## [constant Color.WHITE] and there is no separate "unset" flag, so
## [method ProcgenPlaySandbox.resolve_spawn_color] reads pure white as the
## sentinel for "this participant carries no colour" and falls through to the
## level's `player_color` / `enemy_colors` exports (#563). A slot that could
## pick pure white would therefore silently spawn in the level default instead
## of what the player chose. `test_lobby_roster.gd` pins the absence.
##
## Values were derived OKLCH → sRGB with the house conversion (Björn Ottosson's
## OKLab formulas, same script as the stat palette table): twenty hues spread
## evenly over the non-gold arc, alternating `oklch(0.70 0.17 h)` and
## `oklch(0.80 0.13 h)` so adjacent entries differ in lightness as well as hue.
## Don't eyeball a new one — re-derive it.

## Every colour a slot may choose, in picker order.
@export var colors: Array[Color] = []


func size() -> int:
	return colors.size()


## The default colour for the slot at [param index], wrapping if a roster ever
## outgrows the palette. Max roster today is 6 (2 humans + 4 AI), so twenty
## entries is headroom, not a coincidence.
func default_for(index: int) -> Color:
	if colors.is_empty():
		return Color.WHITE
	return colors[index % colors.size()]


## Does this palette offer [param color]? Compared exactly — every colour that
## reaches here came out of this same array, so no epsilon is warranted and an
## epsilon would blur two neighbouring entries into one.
func has_color(color: Color) -> bool:
	return colors.has(color)
