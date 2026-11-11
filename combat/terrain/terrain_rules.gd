@tool
class_name TerrainRules
extends Resource

## The shared terrain knobs (`docs/domain/elements.md` § Terrain), one
## resource so every reader — the band function here, #1795's world-turn
## pass, #1796's display, #1798 — tunes from the same file. Never a const.

const PATH := "res://combat/terrain/terrain_rules.tres"

## T per point of GRAPH degree: a node of degree d is inert to terrain up to
## `t_per_degree × d` stacks and primes past it (owner, 2026-11-08: a leaf
## holds 2 of any element without effect, the third primes). Tentative knob.
@export_range(1, 8, 1) var t_per_degree: int = 2:
	set(value):
		t_per_degree = value
		emit_changed()


static func shared() -> TerrainRules:
	return load(PATH) as TerrainRules
