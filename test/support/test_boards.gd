class_name TestBoards
extends RefCounted

## Fixture boards for FORMULA tests.
##
## The authored `default_entity_board.tres` is CONTENT: its attribute bases
## move whenever the owner tunes, and a formula test that duplicates it inherits
## every such move. `constitution.base_value` 0 → 20 shifted `node_health` by
## +20 on sixteen tests that had arranged `node_health.base_value = 10`
## themselves and asserted 10 — none of them were about CON. A formula test
## arranges its own inputs; content is an input, never the fixture
## (`docs/domain/stat-knobs-and-bins.md`).
##
## Lives in `test/support/` (outside `.gutconfig.json`'s `dirs`), so GUT never
## collects it as a suite.

const DEFAULT_ENTITY_BOARD := preload("res://entity/default_entity_board.tres")


## The default entity board with its tuned ATTRIBUTE contributions flattened,
## so `node_health` / `core_health` / damage read exactly what the test writes
## into their bases. Use this whenever a test asserts a number it arranged;
## use [constant DEFAULT_ENTITY_BOARD] only when the test is ABOUT the
## authored content (and then assert its shape, not its literal).
static func flat_entity_board() -> EntityStatBoard:
	var board: EntityStatBoard = DEFAULT_ENTITY_BOARD.duplicate(true)
	board.mint_facets()
	board.constitution.base_value = 0.0
	return board


## Strip the board's innate base-damage modifiers (the melee / ranged / spell
## `+8` / `+4` / `+4` ADD_BASE lines) so a fixture that authors its own damage
## bases reads exactly the numbers it wrote. Call after duplicating the
## default board, before the entity applies its intrinsics.
static func strip_innate_damage(board: EntityStatBoard) -> void:
	var kept: Array[StatModifier] = []
	for m in board.intrinsic_modifiers:
		if m.formula == null and m.stat_id in [
				&"blade_damage", &"ranged_damage", &"spell_damage"]:
			continue
		kept.append(m)
	board.intrinsic_modifiers = kept
