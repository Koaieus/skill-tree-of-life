@tool
class_name HexStatus
extends StatusDef

## Hexed: every stack adds a flat crit-chance bonus to hits landing on the host
## (the authored `incoming_modifiers` entry in `hexed.tres`), and the jinx goes
## off — a critical DAMAGE hit taken spends the hex down to
## `floor(power × spend_factor)` ([method _on_crit_taken]). The spend is on top
## of the def's flat per-turn decay. A heal, crit or not, never spends.

## The share of its stacks a row KEEPS when the host takes a crit:
## `floor(power × spend_factor)`, so a single stack pops entirely. 1.0 disables
## the spend; 0.0 wipes the row on the first crit.
@export_range(0.0, 1.0, 0.05) var spend_factor: float = 0.5
