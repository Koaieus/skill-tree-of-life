extends GutTest

## What the [SpellTooltip] is allowed to move with the caster's stats, and what
## it must print raw.
##
## `cast_range_distance` / `cast_range_hops` stretch how far away a target may
## be — the *cast-range* row,
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

# show_for() is a coroutine that settles its own layout over two process
# frames before fading in — await it (its last line is the settled state)
# rather than budgeting physics frames (#978).


## A caster whose `cast_range_distance` is SET to 100 px — a SET replaces the
## spell's authored euclidean reach outright, so any scaling applied to a row
## is unmistakable in the printed number, and the board's own innate INT →
## `cast_range_distance` line cannot move the expected number out from under
## the assertions (that rate is the owner's to tune, per
## `.claude/rules/stat-knobs-and-bins.md`).
func _distance_set_caster() -> Entity:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"cast_range_distance"
	mod.operation = StatModifier.Operation.SET
	mod.value = 100.0
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	entity.stat_board.add_modifier(mod)  # the setter took a private copy; modify that one
	return entity


## A caster whose `cast_range_hops` is SET to a fixed reach — the hop-ranged
## sibling of [method _distance_set_caster]. SET rather than ADD_BASE for the
## same reason: the board's own innate INT threshold ladder must not move the
## expected number out from under the assertions.
const _HOP_REACH := 3.0


func _hop_boosted_caster() -> Entity:
	var board: EntityStatBoard = _BOARD.duplicate(true)
	var mod := StatModifier.new()
	mod.stat_id = &"cast_range_hops"
	mod.operation = StatModifier.Operation.SET
	mod.value = _HOP_REACH
	var entity: Entity = autofree(Entity.new())
	entity.stat_board = board
	entity.stat_board.add_modifier(mod)  # the setter took a private copy; modify that one
	return entity


## Joined plain text of a named section (%CastSection, %ThenSection, …) — the
## rows moved off the flat %StatsGrid into the four derived sections (#764),
## so a value that used to be one row's `.value` is now a substring of its
## section's text.
func _section_text(tt: SpellTooltip, unique_name: String) -> String:
	var section := tt.get_node(unique_name) as SpellTooltipSection
	return " ".join(section.line_texts())


func _shown_for(caster: Entity) -> SpellTooltip:
	var tt: SpellTooltip = _TOOLTIP.instantiate()
	add_child_autofree(tt)
	await get_tree().process_frame
	await tt.show_for(load(_SPELL) as SpellDef, caster)
	return tt


func test_propagation_hops_are_printed_raw_even_for_a_boosted_caster() -> void:
	var spell := load(_SPELL) as SpellDef
	assert_not_null(spell.propagation, "fixture: the spell must propagate")
	var expected := "%d hop" % spell.propagation.max_hops

	var base_tt := await _shown_for(null)
	assert_string_contains(
		_section_text(base_tt, "%ThenSection"), expected,
		"no caster: hops must be the authored number"
	)

	var boosted_tt := await _shown_for(_distance_set_caster())
	assert_string_contains(
		_section_text(boosted_tt, "%ThenSection"), expected,
		"a cast_range_distance SET must not move the bounce count SpellResolver reads raw"
	)


## cast_range_hops twin of the above — same hard constraint, different stat:
## neither of the two INT-scaled reach stats may leak into in-flight bounces.
func test_propagation_hops_are_printed_raw_even_for_a_cast_range_hops_boosted_caster() -> void:
	var spell := load(_SPELL) as SpellDef
	assert_not_null(spell.propagation, "fixture: the spell must propagate")
	var expected := "%d hop" % spell.propagation.max_hops

	var boosted_tt := await _shown_for(_hop_boosted_caster())
	assert_string_contains(
		_section_text(boosted_tt, "%ThenSection"), expected,
		"a cast_range_hops SET must not move the bounce count SpellResolver reads raw"
	)


## cast_range_hops, not cast_range_distance, is what stretches a hop-ranged
## spell's cast range — HopRangeFinder.effective_max_hops() folds the authored
## max_hops under the stat, and a SET on the stat replaces it outright.
func test_cast_range_does_scale_with_cast_range_hops() -> void:
	var spell := load(_SPELL) as SpellDef
	var rf := spell.targeting.get(&"range_finder") as HopRangeFinder
	assert_not_null(rf, "fixture: the spell must be hop-ranged")

	var base_tt := await _shown_for(null)
	assert_string_contains(_section_text(base_tt, "%CastSection"), str(rf.max_hops))

	var boosted_tt := await _shown_for(_hop_boosted_caster())
	assert_string_contains(
		_section_text(boosted_tt, "%CastSection"), str(int(_HOP_REACH))
	)


## The tooltip asks the finder for the number instead of re-deriving it, so the
## two can no longer drift. Pin the delegation itself: whatever the finder says
## for this board is what the Cast section prints.
func test_the_range_row_is_whatever_the_finder_says() -> void:
	var spell := load(_SPELL) as SpellDef
	var rf := spell.targeting.get(&"range_finder") as HopRangeFinder
	var caster := _distance_set_caster()
	var from_finder := rf.effective_max_hops(null, null, caster.stat_board)

	var tt := await _shown_for(caster)
	assert_string_contains(_section_text(tt, "%CastSection"), str(from_finder))
