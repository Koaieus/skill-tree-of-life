## Graph-wide Heat / Cold / Charge bookkeeping, one sample per world turn
## (`docs/domain/terrain-ledger.md`).
##
## A sample is `{ &"heat": {...}, &"cold": {...}, &"charge": {...} }`, each
## element a Dictionary of ints keyed [constant FIELDS]: `produced`, `effect`,
## `voided` (node-paid), `decayed`, `onto_opposite`, `from_opposite`, `total`
## (the graph's count when the sample closed), plus `voided_incoming` (a blade
## copy's pay, off the graph) and `primed` (nodes in a band of the element).
## Charge has no opposite: its two opposite keys stay 0. Per element, every
## closed sample satisfies Δtotal = produced + effect − voided − decayed
## − onto_opposite − from_opposite, Δ against the previous sample (the first
## against [method baseline]). Session-only debug telemetry: never saved,
## never synced. Counts live landings only ([signal CombatWorld.terrain_booked]);
## a shadow resolve adds nothing.
extends Node
class_name TerrainLedger

## Closed once per world turn, oldest first in [method samples].
signal sample_closed(sample: Dictionary)

const ELEMENTS: Array[StringName] = [&"heat", &"cold", &"charge"]
const FIELDS: Array[StringName] = [
	&"produced", &"effect", &"voided", &"decayed",
	&"onto_opposite", &"from_opposite", &"total",
	&"voided_incoming", &"primed",
]
## [TerrainBook.Field] -> the sample key it adds to.
const _BOOKED := {
	TerrainBook.Field.PRODUCED: &"produced",
	TerrainBook.Field.EFFECT: &"effect",
	TerrainBook.Field.VOIDED: &"voided",
	TerrainBook.Field.VOIDED_INCOMING: &"voided_incoming",
	TerrainBook.Field.DECAYED: &"decayed",
	TerrainBook.Field.ONTO_OPPOSITE: &"onto_opposite",
}

## World turns kept (tentative, easy to change).
@export_range(5, 400) var window_turns: int = 40:
	set(v):
		window_turns = v
		_trim()

## Whose [signal TurnManager.world_turn_ended] closes a sample.
@export var turn_manager: TurnManager = null: set = _set_turn_manager

var _samples: Array[Dictionary] = []
var _current: Dictionary = empty_sample()
var _world: CombatWorld = null
## Element -> its graph total when the history last started.
var _baseline: Dictionary = {}


func _ready() -> void:
	if _world == null:
		bind_world(CombatWorld.live())


## The closed samples, oldest first, at most [member window_turns].
func samples() -> Array[Dictionary]:
	return _samples


## The open sample for this world turn.
func current() -> Dictionary:
	return _current


## Element -> its graph total the first closed sample's Δ is taken against.
func baseline() -> Dictionary:
	return _baseline


static func empty_sample() -> Dictionary:
	var s := {}
	for e in ELEMENTS:
		var row := {}
		for f in FIELDS:
			row[f] = 0
		s[e] = row
	return s


## Count [param world]'s terrain from here on (the live world by default); the
## history restarts.
func bind_world(world: CombatWorld) -> void:
	if _world != null:
		if _world.terrain_booked.is_connected(_on_booked):
			_world.terrain_booked.disconnect(_on_booked)
		if _world.terrain_rebased.is_connected(_rebase):
			_world.terrain_rebased.disconnect(_rebase)
	_world = world
	if _world != null:
		_world.terrain_booked.connect(_on_booked)
		_world.terrain_rebased.connect(_rebase)
	_rebase()


## Close the open sample: stamp each element's graph total and primed count,
## keep it (trimmed to [member window_turns]) and open the next.
func close_sample() -> void:
	var s := _current
	var totals := _totals()
	for e in ELEMENTS:
		var row: Dictionary = s[e]
		row[&"total"] = int(totals[e][0])
		row[&"primed"] = int(totals[e][1])
	s[&"heat"][&"from_opposite"] = s[&"cold"][&"onto_opposite"]
	s[&"cold"][&"from_opposite"] = s[&"heat"][&"onto_opposite"]
	_samples.append(s)
	_trim()
	_current = empty_sample()
	sample_closed.emit(s)


func _on_booked(sums: PackedInt32Array) -> void:
	for i in ELEMENTS.size():
		var row: Dictionary = _current[ELEMENTS[i]]
		for f: int in _BOOKED:
			row[_BOOKED[f]] = int(row[_BOOKED[f]]) + TerrainBook.read_of(sums, i, f)


## Clear the history and take the board as it stands as the new baseline.
func _rebase() -> void:
	_samples.clear()
	_current = empty_sample()
	var totals := _totals()
	for e in ELEMENTS:
		_baseline[e] = int(totals[e][0])


## Element -> [total, primed] over the world's terrain index.
func _totals() -> Dictionary:
	var out := {}
	for e in ELEMENTS:
		out[e] = [0, 0]
	if _world == null:
		return out
	var fire := TerrainSettle.element_on(Terrain.Axis.HEAT)
	var ice := TerrainSettle.element_on(Terrain.Axis.COLD)
	var light := TerrainSettle.element_on(Terrain.Axis.CHARGE)
	for node in _world.terrain_nodes():
		var t := node.terrain_t()
		out[&"heat"][0] += maxi(t, 0)
		out[&"cold"][0] += maxi(-t, 0)
		out[&"charge"][0] += node.charge()
		if fire != null and node.terrain_band(fire) != null:
			out[&"heat"][1] += 1
		if ice != null and node.terrain_band(ice) != null:
			out[&"cold"][1] += 1
		if light != null and node.terrain_band(light) != null:
			out[&"charge"][1] += 1
	return out


func _trim() -> void:
	while _samples.size() > maxi(window_turns, 1):
		_samples.pop_front()


func _set_turn_manager(value: TurnManager) -> void:
	if turn_manager != null and turn_manager.world_turn_ended.is_connected(close_sample):
		turn_manager.world_turn_ended.disconnect(close_sample)
	turn_manager = value
	if turn_manager != null:
		turn_manager.world_turn_ended.connect(close_sample)
