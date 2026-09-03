extends GutTest

## What the [SpellTooltip] is allowed to move with the caster's stats, and what
## it must print raw.
##
## `spell_range` stretches how far away a target may be — the *cast-range* row,
## which the finder itself computes. It does NOT grant in-flight bounces:
## `SpellResolver` seeds `hops_remaining` straight off `PropagationConfig.max_hops`,
## and per the owner's 2026-09-02 ruling propagation scaling stays off until it
## has a tuning model of its own. The tooltip used to carry its own copy of
## `HopRangeFinder`'s formula and apply it to BOTH, so it over-reported bounces
## for every caster above baseline INT while the combat readout showed the truth.

const _TOOLTIP := preload("res://ui/spell_tooltip/spell_tooltip.tscn")
const _BOARD := preload("res://entity/default_entity_board.tres")

# A hop-ranged spell with a hop-limited propagation, so one caster exercises
# both rows at once.
const _SPELL := "res://attack/spell/defs/lightning_bolt.tres"

# show_for() settles its layout over two frames before fading in.
const _SETTLE_FRAMES: int = 5


## A caster whose `spell_range` is +100%, i.e. exactly double euclidean reach —
## big enough that any scaling applied to a row is unmistakable in the printed
## number. SET rather than ADD_BASE so the board's own innate INT → `spell_range`
## formula cannot move the expected number out from under the assertions (that
## rate is the owner's to tune, per `.claude/rules/stat-knobs-and-bins.md`).
func _doubled_caster() -> Entity:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"spell_range"
	mod.operation = StatModifier.Operation.SET
	mod.value = 100.0
	board.add_modifier(mod)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	return entity


## A caster whose `spell_hops` is set to a fixed flat bonus (#727) — the
## hop-ranged sibling of [method _doubled_caster]. SET rather than ADD_BASE
## for the same reason: the board's own innate INT threshold ladder must not
## move the expected number out from under the assertions.
const _HOP_BONUS := 3.0


func _hop_boosted_caster() -> Entity:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"spell_hops"
	mod.operation = StatModifier.Operation.SET
	mod.value = _HOP_BONUS
	board.add_modifier(mod)
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	return entity


func _rows(tt: SpellTooltip) -> Dictionary:
	var out: Dictionary = {}
	for row in tt.get_node("%StatsGrid").get_children():
		out[(row as SpellStatRow).row_label] = (row as SpellStatRow).value
	return out


func _shown_for(caster: Entity) -> Dictionary:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await wait_frames(2)
	tt.show_for(load(_SPELL) as SpellDef, caster)
	for _i in _SETTLE_FRAMES:
		await wait_frames(1)
	return _rows(tt)


func test_propagation_hops_are_printed_raw_even_for_a_boosted_caster() -> void:
	var spell := load(_SPELL) as SpellDef
	assert_not_null(spell.propagation, "fixture: the spell must propagate")
	var expected := str(spell.propagation.max_hops)

	var base_rows: Dictionary = await _shown_for(null)
	assert_eq(base_rows.get("Hops"), expected, "no caster: hops must be the authored number")

	var boosted_rows: Dictionary = await _shown_for(_doubled_caster())
	assert_eq(
		boosted_rows.get("Hops"), expected,
		"+100%% spell_range must not move the bounce count SpellResolver reads raw"
	)


## spell_hops twin of the above — same hard constraint, different stat (#727):
## neither of the two INT-scaled reach stats may leak into in-flight bounces.
func test_propagation_hops_are_printed_raw_even_for_a_spell_hops_boosted_caster() -> void:
	var spell := load(_SPELL) as SpellDef
	assert_not_null(spell.propagation, "fixture: the spell must propagate")
	var expected := str(spell.propagation.max_hops)

	var boosted_rows: Dictionary = await _shown_for(_hop_boosted_caster())
	assert_eq(
		boosted_rows.get("Hops"), expected,
		"a spell_hops bonus must not move the bounce count SpellResolver reads raw"
	)


## spell_hops (#727), not spell_range, is what stretches a hop-ranged spell's
## cast range now — HopRangeFinder.effective_max_hops() is additive
## (max_hops + spell_hops), never a percent multiplier.
func test_cast_range_does_scale_with_spell_hops() -> void:
	var spell := load(_SPELL) as SpellDef
	var rf := spell.targeting.get(&"range_finder") as HopRangeFinder
	assert_not_null(rf, "fixture: the spell must be hop-ranged")

	var base_rows: Dictionary = await _shown_for(null)
	assert_string_contains(str(base_rows.get("Range")), str(rf.max_hops))

	var boosted_rows: Dictionary = await _shown_for(_hop_boosted_caster())
	assert_string_contains(str(boosted_rows.get("Range")), str(rf.max_hops + int(_HOP_BONUS)))


## The tooltip asks the finder for the number instead of re-deriving it, so the
## two can no longer drift. Pin the delegation itself: whatever the finder says
## for this board is what the row prints.
func test_the_range_row_is_whatever_the_finder_says() -> void:
	var spell := load(_SPELL) as SpellDef
	var rf := spell.targeting.get(&"range_finder") as HopRangeFinder
	var caster := _doubled_caster()
	var from_finder := rf.effective_max_hops(null, null, caster.stat_board)

	var rows: Dictionary = await _shown_for(caster)
	assert_string_contains(str(rows.get("Range")), str(from_finder))
