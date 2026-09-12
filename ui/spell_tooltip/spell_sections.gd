class_name SpellSections
extends RefCounted

## The ONE derivation of a spell's four marked sections — Cast / On arrival /
## Then / Crits (#764) — as plain text, for every surface that renders them.
##
## [b]One derivation, no second implementation (#853).[/b] [SpellTooltip]
## (hover, with the caster's board) and the spell catalogue (long-form, no
## caster) show the same four sections; had each derived its own lines the two
## would drift the first time a describer changed. So the derivation lives
## here, once, as a static [method build], and the composers only decide where
## the resulting [Lines] go. Rendering stays in [SpellTooltipSection] — this
## class holds no [Node].
##
## [b]Every line is asked of the resource that owns it[/b] — the finder for
## reach, the effect for its number, the config for the walk — never re-derived
## here. A private copy of the hop-scaling formula is exactly what once made the
## tooltip disagree with the game about propagation depth.
##
## [b]The gold rule.[/b] A line is marked dynamic when, and only when, the
## caster's [param board] actually moved the number off the spell's printed
## base — computed by describing twice (raw, then with the board) and comparing.
## With no board (the catalogue's case) nothing is ever dynamic: base numbers,
## nothing gold.


## One section's rows plus which of them wear the caster-scaled accent — the
## exact pair [method SpellTooltipSection.bind] takes.
class Lines extends RefCounted:
	var lines: PackedStringArray = []
	var dynamic: Array[int] = []

	## Append a non-empty row; `is_dynamic` marks it for the gold accent.
	func add(text: String, is_dynamic: bool = false) -> void:
		if text.is_empty():
			return
		lines.append(text)
		if is_dynamic:
			dynamic.append(lines.size() - 1)

	## Append the caster-scaled reading, gold iff it differs from the raw one.
	func add_scaled(raw: String, effective: String) -> void:
		add(effective, effective != raw)

	func is_empty() -> bool:
		return lines.is_empty()


var cast: Lines = Lines.new()
var on_arrival: Lines = Lines.new()
var then: Lines = Lines.new()
var crits: Lines = Lines.new()


## Derive all four sections for [param def]. [param board] is the caster's
## [StatBoard] when a caster is known (the tooltip), null for base numbers
## (the catalogue).
static func build(def: SpellDef, board: StatBoard = null) -> SpellSections:
	var out := SpellSections.new()
	if def == null:
		return out
	out.cast = _cast(def, board)
	out.on_arrival = _on_arrival(def, board)
	out.then = _then(def)
	out.crits = _crits(def)
	return out


## Section 1 — who it can hit ([Targeting]/[NodeTargeting]), then how far
## ([RangeFinder], described by the finder itself so the scaled number is the
## finder's own).
static func _cast(def: SpellDef, board: StatBoard) -> Lines:
	var out := Lines.new()
	if def.targeting != null:
		out.add(def.targeting.get_description())
	var rf := def.targeting.get_range_finder() if def.targeting != null else null
	if rf != null:
		out.add_scaled(rf.get_description(null), rf.get_description(board))
	return out


## Section 2 — one line per [OnHitEffect] in authored order (each carries the
## D-32 impact number, gold when the board moved it), then the reducer's line
## when the spell propagates.
static func _on_arrival(def: SpellDef, board: StatBoard) -> Lines:
	var out := Lines.new()
	for effect in def.on_hit_effects:
		if effect == null:
			continue
		out.add_scaled(effect.get_description(def, null), effect.get_description(def, board))
	var prop := def.propagation
	if prop != null and prop.max_hops > 0 and prop.reducer != null:
		out.add(prop.reducer.get_description())
	return out


## Section 3 — [PropagationConfig] describes its own walk (and owns the
## single-target collapse for a step-less / zero-hop spread); a null config is
## an invalid def ([method SpellDef.validate] flags it) and the one case the
## config cannot answer for.
static func _then(def: SpellDef) -> Lines:
	var out := Lines.new()
	var prop := def.propagation
	if prop == null:
		out.add("Single target.")
		return out
	out.add(prop.get_description())
	if prop.hop_damage != null:
		out.add(prop.hop_damage.get_description())
	return out


## Section 4 — one line per [LandingCondition]. No number to scale, so never
## dynamic; empty for a spell that authors no crits (the section collapses).
static func _crits(def: SpellDef) -> Lines:
	var out := Lines.new()
	for cond in def.crit_conditions:
		if cond == null:
			continue
		out.add(cond.get_description())
	return out

