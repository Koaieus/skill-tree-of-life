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
## [b]Owner call, 2026-09-02, superseding #639's stride:[/b] sixteen colours in
## two authored tiers — eight canonical brights (index 0-7: Red, Blue, and six
## more spread around the non-gold hue arc), then eight muted "second choice"
## colours (index 8-15) sitting in the hue gaps between the brights, for a
## roster that somehow outgrows tier one. [method default_for] just walks the
## array (`colors[index % size]`) — the ordering itself is arranged so that
## consecutive slots land on well-separated hues; #639's runtime
## `index * stride` trick is retired rather than reapplied to a hand-curated
## list. `test_lobby_roster.gd` still pins pairwise OKLab separation (dE ≥
## 0.14, same bar #639 used) for a 3- and a 6-slot roster.
##
## Values were derived OKLCH → sRGB with the house conversion (Björn Ottosson's
## OKLab formulas, same script as the stat palette table), gamut-checked per
## hue rather than clamped, with lightness cycled across three values (0.62 /
## 0.74 / 0.86) so hue alone never has to carry the whole separation. Don't
## eyeball a new one — re-derive it.
##
## `dev_sandbox.tscn`'s pre-#616 hardcoded players — `Color(0.9, 0.2, 0.2)` Red
## and `Color(0.25, 0.45, 0.95)` Blue — were the reference for where slots 0/1
## should sit; kept here as a note in case a future fully-bespoke (non-OKLCH-
## generated) palette wants to match them exactly rather than approximate them.
##
## Names, index-for-index with the shipped array (not a second data source —
## just what to call an index when talking about one):
## [codeblock]
## 0 Red         4 Orange       8 Rust       12 Cobalt
## 1 Blue        5 Chartreuse   9 Moss       13 Lavender
## 2 Violet      6 Olive       10 Teal       14 Plum
## 3 Magenta     7 Cyan        11 Steel      15 Rose
## [/codeblock]

## Every colour a slot may choose, in picker order.
@export var colors: Array[Color] = []


func size() -> int:
	return colors.size()


## The default colour for the slot at [param index], wrapping if a roster ever
## outgrows the palette. Max roster today is 6 (2 humans + 4 AI); sixteen
## entries is headroom, not a coincidence — the first eight are the whole
## tier a roster ever actually draws from by default.
func default_for(index: int) -> Color:
	if colors.is_empty():
		return Color.WHITE
	return colors[index % colors.size()]


## Does this palette offer [param color]? Compared exactly — every colour that
## reaches here came out of this same array, so no epsilon is warranted and an
## epsilon would blur two neighbouring entries into one.
func has_color(color: Color) -> bool:
	return colors.has(color)
