@tool
class_name NoPropagation
extends SpellPropagation

## Single-target — the spell does nothing beyond the seed hit. For Degree
## Drain, Supernova's resolved-target list (when AoE collection lands), and
## any future spell whose interesting behaviour lives entirely in its
## on-hit effects, not in propagation.


func next_hops(_state: SpellState) -> Array[SpellState]:
	return []
