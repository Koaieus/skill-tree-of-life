@tool
class_name ThresholdFormula
extends StatFormula

## Breakpoint scaling — "+1 each time the source crosses one of these values".
## Computes the COUNT of [member breakpoints] the source has reached, in
## integer comparisons only; the modifier's `value` carries the coefficient,
## exactly as [RatioFormula]'s does.
##
## [b]This exists to keep transcendentals out of gameplay math[/b] (#547).
## Mana-per-turn was authored as `floor(log(INT) / log(10.0))`, which is wrong
## on glibc today — `log(1000.0)` lands one ulp below `3 * log(10.0)`, the
## ratio is `2.9999999999999996`, and `floor` turns that into a whole missing
## point of regen at INT 1000. It is also unfixable in principle: IEEE 754
## specifies only `+ - * / sqrt` (and fma) to be correctly rounded, so every
## platform's libm approximates `log` differently in the last bits — and
## derived stats are recomputed locally on every peer rather than sent, so a
## Windows client and a Linux host would silently disagree about a caster's
## regen for a whole run. `floor(log_b(x))` sits exactly on an integer
## boundary precisely at the round numbers a stat system lands on constantly.
## A sorted list of integers compared with `>=` has no such failure mode.
##
## Any monotone step function of one stat is authorable here, not just decades:
## `[3, 8, 21, 55, 149, 404]` reproduces `floor(ln(WIS))` exactly for every
## integer WIS, because `ceil(e^n)` is where each step actually lands.
##
## [b]It saturates.[/b] A finite list cannot climb forever, so the value tops
## out at `breakpoints.size()`. That is a deliberate authoring obligation, not
## a bug: extend the list past any value the stat can plausibly reach (the
## shipped mana ladder runs to 1e6 INT), and pin the top of it in a test.
## Use [RatioFormula] for the far more common ungated `floor(source / N)`.

## The stat being compared. Accepts a bare `<stat_id>` (reads the computed
## value / cap) or a `<stat_id>__<accessor>` token (reads a named accessor —
## see [method Stat.read_accessor]); the formula layer splits the token.
@export var source_stat_id: StringName = &""

## Ascending values of `source_stat_id` at which the result steps up by one.
## `[10, 100, 1000]` reads "+1 at 10, +1 more at 100, +1 more at 1000".
## MUST be sorted ascending — [method compute] stops at the first breakpoint
## the source has not reached, so an out-of-order entry silently truncates
## the ladder rather than erroring.
@export var breakpoints: Array[float] = []


func to_dict() -> Dictionary:
	var d := super()
	d["type"] = StatModifierCodec.TAG_THRESHOLD
	d["source_stat_id"] = source_stat_id
	var bps: Array = []
	for b in breakpoints:
		bps.append(float(b))
	d["breakpoints"] = bps
	return d


func read_dict(d: Dictionary) -> void:
	super(d)
	source_stat_id = StringName(d.get("source_stat_id", &""))
	var bps: Array[float] = []
	for raw in (d.get("breakpoints", []) as Array):
		bps.append(float(raw))
	breakpoints = bps


func get_input_ids() -> Array[StringName]:
	return [StatFormula.base_of(source_stat_id)]


func compute(board: StatBoard) -> float:
	var s := board.get_stat(StatFormula.base_of(source_stat_id))
	if s == null:
		return 0.0
	var v := float(s.read_accessor(StatFormula.accessor_of(source_stat_id)))
	var reached := 0
	for b in breakpoints:
		if v < b:
			break
		reached += 1
	return float(reached)


## "×10 INT" for a geometric ladder, "WIS" otherwise — the same principle as
## [RatioFormula.describe_per]: the displayed number is READ OFF the same
## array [method compute] walks, so the two cannot drift apart. A ladder whose
## shape has no one-line name (`floor(ln(WIS))`) falls back to the source
## abbreviation, and an authored [member per_phrase] still wins over both.
##
## The non-geometric fallback stays a bare abbreviation here (never empty —
## [code]test_every_board_intrinsic_formula_is_described[/code] requires
## every shipped formula to answer something), but it is no longer what gets
## shown to a player on that path: see [method describe_clause] below, which
## is what [StatModifier] actually renders.
func describe_per() -> String:
	if not per_phrase.is_empty():
		return per_phrase
	var abbr := _abbrev(StatFormula.base_of(source_stat_id))
	var ratio := _common_ratio()
	if ratio <= 0.0:
		return abbr
	return "×%s %s" % [_trim(ratio), abbr]


## Overrides [StatFormula.describe_clause] for the one shape [method
## describe_per] cannot honestly answer (#773, owner-narrowed 2026-09-07):
## a non-geometric ladder has no ratio, so wrapping its bare abbreviation in
## " per WIS" reads as "+1 per point of WIS" — a rate the ladder does not
## have. An authored [member per_phrase] and the geometric ladder both ARE
## honest "per" rates, so both keep the base class's default " per <phrase>"
## wrapping (delegated via `super()`) unchanged. Only the non-geometric,
## unauthored case renders its own clause instead — the ladder itself, named
## with "at" rather than "per":
##
##   "+1 Spell Hops at 50 / 150 / 500 / 1000 / 5000 INT"
##
## Truncated to the first three rungs plus the last past 5 entries (see
## [method _ladder_list]) so a long ladder (WIS's ten-rung sensor-range curve,
## if it ever loses its authored `per_phrase`) still fits the loot pick card
## this was reported from.
func describe_clause() -> String:
	if not per_phrase.is_empty() or _common_ratio() > 0.0:
		return super()
	if breakpoints.is_empty():
		return ""
	return " at %s %s" % [_ladder_list(), _abbrev(StatFormula.base_of(source_stat_id))]


## The constant multiplier between consecutive breakpoints, or `-1.0` when the
## ladder is not geometric (or is too short to have a ratio at all). The first
## breakpoint must itself equal the ratio — `[10, 100, 1000]` is "×10" only
## because the ladder starts at 10, not at 1.
func _common_ratio() -> float:
	if breakpoints.size() < 2 or breakpoints[0] <= 0.0:
		return -1.0
	var ratio := breakpoints[0]
	for i in range(1, breakpoints.size()):
		if breakpoints[i - 1] <= 0.0:
			return -1.0
		if not is_equal_approx(breakpoints[i] / breakpoints[i - 1], ratio):
			return -1.0
	return ratio


## "50 / 150 / 500 / 1000 / 5000" for a short ladder. Past 5 rungs (none
## shipped today — the longest, WIS's sensor-range ladder, carries an
## authored `per_phrase` and never reaches this branch) truncates to the
## first 3 plus the last, ellipsis between, so the rendered clause stays on
## one line on the loot pick card the owner flagged this on.
func _ladder_list() -> String:
	var strs: Array[String] = []
	if breakpoints.size() > 5:
		for b in breakpoints.slice(0, 3):
			strs.append(_trim(b))
		strs.append("…")
		strs.append(_trim(breakpoints[-1]))
	else:
		for b in breakpoints:
			strs.append(_trim(b))
	return " / ".join(strs)
