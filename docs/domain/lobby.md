# Lobby, roster and run bootstrap

The pre-run session surface: palette, roster, policy, bootstrap.

## Player palette (`session/player_palette.gd`)

The colours a lobby slot may pick a hero from (#616). Authored once as
`session/player_palette.tres`; the lobby assigns defaults round-robin and
the per-slot picker overrides.

**Distinct from the stat palette.** `.claude/rules/ui-palette.md` makes
`StatDef.tint_color` the source of truth for attribute/vital colours
and forbids a second resource restating them — this is not that. A hero's
identity colour answers "whose is this", not "which stat is this", so it is
its own axis and its own resource. Nothing here is read back into a stat
colour, and nothing reads values out of `ui/theme/editor_swatches.tres`.

**Two colours are deliberately absent, and both absences are load-bearing:**

**1. Gold.** Reserved for pure positives (same rule file) — reward, never
identity. The generator below therefore skips the hue band `[62, 112)`
outright rather than trusting an author to eyeball it.

**2. Pure white.** `Participant.color` defaults to
`Color.WHITE` and there is no separate "unset" flag, so
`ProcgenPlaySandbox.resolve_spawn_color` reads pure white as the
sentinel for "this participant carries no colour" and falls through to the
level's `player_color` / `enemy_colors` exports. A slot that could
pick pure white would therefore silently spawn in the level default instead
of what the player chose. `test_lobby_roster.gd` pins the absence.

**Owner call, 2026-09-02, superseding #639's stride:** sixteen colours in
two authored tiers — eight canonical brights (index 0-7: Red, Blue, and six
more spread around the non-gold hue arc), then eight muted "second choice"
colours (index 8-15) sitting in the hue gaps between the brights, for a
roster that somehow outgrows tier one. `default_for` just walks the
array (`colors[index % size]`) — the ordering itself is arranged so that
consecutive slots land on well-separated hues; #639's runtime
`index * stride` trick is retired rather than reapplied to a hand-curated
list. `test_lobby_roster.gd` still pins pairwise OKLab separation (dE ≥
0.14, same bar #639 used) for a 3- and a 6-slot roster.

Values were derived OKLCH → sRGB with the house conversion (Björn Ottosson's
OKLab formulas, same script as the stat palette table), gamut-checked per
hue rather than clamped, with lightness cycled across three values (0.62 /
0.74 / 0.86) so hue alone never has to carry the whole separation. Don't
eyeball a new one — re-derive it.


Names, index-for-index with the shipped array (not a second data source —
just what to call an index when talking about one):
```
0 Red         4 Orange       8 Rust       12 Cobalt
1 Blue        5 Chartreuse   9 Moss       13 Lavender
2 Violet      6 Olive       10 Teal       14 Plum
3 Magenta     7 Cyan        11 Steel      15 Rose
```
