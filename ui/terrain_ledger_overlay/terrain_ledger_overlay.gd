## Runtime debug overlay: F4 toggles a per-element readout of [TerrainLedger].
extends Control
class_name TerrainLedgerOverlay

@export var ledger: TerrainLedger = null
@export var toggle_key: Key = KEY_F4
@export var heat_element: Element = null
@export var cold_element: Element = null
@export var charge_element: Element = null
