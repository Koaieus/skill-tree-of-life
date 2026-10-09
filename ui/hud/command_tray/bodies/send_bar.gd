@tool
class_name SendBar
extends Control

## A vertical send bar: the fill is the share of the pile sent this volley.

signal value_requested(n: int)

@export var stock: int = 0
@export var value: int = 0
@export var tint: Color = Color.WHITE
@export var border_decades: PackedInt32Array = [1, 10, 100]


## The amount at fraction-from-bottom of the bar for a local y.
static func value_at(_local_y: float, _height: float, _stock: int) -> int:
	return 0


## How many border thirds are lit for a stock: 0 at nothing, then one per decade bound reached.
static func lit_thirds(_stock: int, _border_decades: PackedInt32Array) -> int:
	return 0
