@tool
class_name RangedBody
extends CommandTrayBodyBase
## Ranged tab content — the Quiver's view (#954), as the magic body is the
## [SpellBook]'s: the volley bar full width on top with Reload / Reset /
## Launch at its end, and below it the inventory — one tall [AmmoCard] per
## type with stock or reload gain. The base card is baked into the scene and
## carries the fill toggle; special cards are instanced in preference order.
##
## Composition rule: the player sets each SPECIAL's count; base arrows either
## FILL the remaining room (fill ON — the volley sits at max) or hold an
## explicit count (fill OFF — the bar and the base card move it). Every choice
## is sticky for the run in the entity's [VolleyPreference] (fill, the
## per-type counts) and survives a new target; the body owns no sticky state.
## The clamp to the bins and to max lives in the plan only, never written back.
## The body writes exactly one thing into the plan — [member
## RangedAttackPlan.ammo], listed in the preference's card order — and submits
## one command, [ReloadCommand] via [method PlayerInputController.request_reload].
##
## Readouts: `N / max` on the bar with the typed segments, notches at the wave
## boundaries, the per-leaf contribution ("2+2+1") read from the PLAN, each
## card's count / stock / `+gain`, a gentle "room for k more" while the volley
## is below max, and the reload button's `⟳ Reload +yield −1 AP`. No kills
## text anywhere (owner: "TMI").
##
## Input: scroll on the bar ±1 (Shift = ±wave), `M` back to max (fill ON),
## `ui_volley_fill` toggles fill, `Enter` launches; `R` (`ui_reload`) reloads.
## No per-frame work: one rebuild per plan state change / adjustment.

const _AMMO_CARD_SCENE := preload("res://ui/hud/command_tray/bodies/ammo_card.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")
const _BASE := AmmoTypeRoster.BASE_ID

@onready var _hint: Label = %Hint
@onready var _leaves_label: Label = %LeavesLabel
@onready var _capacity_hint: Label = %CapacityHint
@onready var _volley_bar: VolleyBar = %VolleyBar
@onready var _base_card: AmmoCard = %BaseCard
@onready var _specials: HBoxContainer = %Specials
@onready var _reload_button: Button = %ReloadButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton

var _special_cards: Array[AmmoCard] = []
var _quiver: Quiver = null
var _refreshing := false
var _orphan_pref: VolleyPreference = null


func _ready() -> void:
	_base_card.setup(_ROSTER.base_type())


func _on_bound() -> void:
	_reset_button.pressed.connect(_reset_plan)
	_launch_button.pressed.connect(_on_launch_pressed)
	_reload_button.pressed.connect(_on_reload_pressed)
	_volley_bar.step_requested.connect(_on_bar_step)
	_volley_bar.set_requested.connect(set_n)
	_connect_card(_base_card)
	if _armed_stack != null:
		_armed_stack.attack_plan_state_changed.connect(_refresh)
	Events.volley_arrow_placed.connect(_volley_bar.on_arrow_placed)
	Events.volley_arrow_released.connect(_volley_bar.on_arrow_released)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_on_can_act_changed)
	_quiver = _player.stat_board.arrows as Quiver if _player != null and _player.stat_board != null else null
	if _quiver != null:
		_quiver.bin_changed.connect(_on_bin_changed)
	_refresh()


## The bound player's sticky ranged choices — its [VolleyPreference] on the
## [ArmedStack], so they survive a tray rebuild, a launch and a turn end. A
## body with no stack keeps a throwaway one.
func _pref() -> VolleyPreference:
	if _armed_stack != null:
		return _armed_stack.memory_for(_player).ranged
	if _orphan_pref == null:
		_orphan_pref = VolleyPreference.new()
	return _orphan_pref


func teardown() -> void:
	if Events.volley_arrow_placed.is_connected(_volley_bar.on_arrow_placed):
		Events.volley_arrow_placed.disconnect(_volley_bar.on_arrow_placed)
	if Events.volley_arrow_released.is_connected(_volley_bar.on_arrow_released):
		Events.volley_arrow_released.disconnect(_volley_bar.on_arrow_released)
	if _armed_stack != null and _armed_stack.attack_plan_state_changed.is_connected(_refresh):
		_armed_stack.attack_plan_state_changed.disconnect(_refresh)
	if _reset_button.pressed.is_connected(_reset_plan):
		_reset_button.pressed.disconnect(_reset_plan)
	if _launch_button.pressed.is_connected(_on_launch_pressed):
		_launch_button.pressed.disconnect(_on_launch_pressed)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_on_can_act_changed):
		_input_ctl.player_can_act_changed.disconnect(_on_can_act_changed)
	if _quiver != null and _quiver.bin_changed.is_connected(_on_bin_changed):
		_quiver.bin_changed.disconnect(_on_bin_changed)
	_quiver = null
	if _reload_button.pressed.is_connected(_on_reload_pressed):
		_reload_button.pressed.disconnect(_on_reload_pressed)
	if _volley_bar.step_requested.is_connected(_on_bar_step):
		_volley_bar.step_requested.disconnect(_on_bar_step)
	if _volley_bar.set_requested.is_connected(set_n):
		_volley_bar.set_requested.disconnect(set_n)
	_disconnect_card(_base_card)
	for card in _special_cards:
		_specials.remove_child(card)
		card.queue_free()
	_special_cards.clear()


func _on_can_act_changed(_can: bool) -> void:
	_refresh()


func _on_bin_changed(_type_id: StringName) -> void:
	_refresh()


func _connect_card(card: AmmoCard) -> void:
	card.set_requested.connect(_on_card_set)
	card.all_requested.connect(set_all)
	card.none_requested.connect(set_none)
	card.fill_toggled.connect(set_fill)


func _disconnect_card(card: AmmoCard) -> void:
	if card.set_requested.is_connected(_on_card_set):
		card.set_requested.disconnect(_on_card_set)
		card.all_requested.disconnect(set_all)
		card.none_requested.disconnect(set_none)
		card.fill_toggled.disconnect(set_fill)


# --- composition controls -------------------------------------------------

func _plan() -> RangedAttackPlan:
	return _armed_plan() as RangedAttackPlan


func _aimed() -> RangedAttackPlan:
	var plan := _plan()
	return plan if plan != null and plan.target != null else null


func max_n() -> int:
	var plan := _aimed()
	return plan.max_n() if plan != null else 0


## Arrows in the volley as currently composed (Σ of the plan's counts).
func n() -> int:
	var plan := _aimed()
	return plan.n() if plan != null else 0


func fill() -> bool:
	return _pref().fill


## Bar set / scroll: N as a volley size. Turns fill off and holds the base
## at `N − Σ specials` (never below 0 — specials past N grow N to fit).
func set_n(value: int) -> void:
	var pref := _pref()
	pref.fill = false
	var plan := _aimed()
	var specials := 0
	if plan != null:
		for c in _clamped_specials(plan.max_n(), plan.is_scout_shot()).values():
			specials += int(c)
	pref.special_counts[_BASE] = maxi(0, value - specials)
	_refresh()


func adjust_n(delta: int) -> void:
	set_n(n() + delta)


## `M`: back to max, which is fill on.
func reset_n_to_max() -> void:
	set_fill(true)


## Turning fill off holds the base at what it fires now, so the volley does
## not jump on the toggle.
func set_fill(on: bool) -> void:
	var pref := _pref()
	if pref.fill != on:
		var plan := _aimed()
		if not on and plan != null:
			pref.special_counts[_BASE] = plan.count_of(_BASE)
		pref.fill = on
	_refresh()


func toggle_fill() -> void:
	set_fill(not _pref().fill)


## The base card's bar: an explicit base count, so fill turns off.
func set_base(value: int) -> void:
	var pref := _pref()
	pref.fill = false
	pref.special_counts[_BASE] = maxi(0, value)
	_refresh()


## Under fill, lowering a special by more than the base bin can absorb would
## be topped straight back up, so fill turns off with the base held where it
## is: the volley then shrinks instead.
func set_special(type_id: StringName, value: int) -> void:
	if type_id == _BASE:
		set_base(value)
		return
	value = maxi(0, value)
	var pref := _pref()
	var plan := _aimed()
	if plan != null and pref.fill:
		var before := plan.count_of(type_id)
		var base_now := plan.count_of(_BASE)
		var base_room := _stock_for(_ROSTER.base_type(), plan.is_scout_shot()) - base_now
		if before - value > base_room:
			pref.fill = false
			pref.special_counts[_BASE] = base_now
	pref.special_counts[type_id] = value
	_refresh()


## The count label's left click: min(bin, room).
func set_all(type_id: StringName) -> void:
	var plan := _aimed()
	if plan == null:
		return
	var t := _ROSTER.by_id(type_id)
	var counts := _counts_of(plan)
	var v := mini(_stock_for(t, plan.is_scout_shot()), _room_for(type_id, counts, plan.max_n()))
	set_special(type_id, maxi(v, 0))


## The count label's right click.
func set_none(type_id: StringName) -> void:
	set_special(type_id, 0)


func _on_card_set(type_id: StringName, value: int) -> void:
	if type_id == _BASE:
		set_base(value)
	else:
		set_special(type_id, value)


## The base card first, then the special cards in card order.
func cards() -> Array[AmmoCard]:
	var out: Array[AmmoCard] = [_base_card]
	out.append_array(_special_cards)
	return out


## Per reaching leaf, in firing rank: `{node, shots, range, damage}`, the
## range and damage node-local as the plan reads them.
func leaf_readouts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var plan := _plan()
	if plan == null or plan.target == null:
		return out
	var shots: Dictionary[SkillNode, int] = {}
	var order: Array[SkillNode] = []
	for shot in plan.get_firing_schedule():
		if not shots.has(shot.firing_node):
			order.append(shot.firing_node)
		shots[shot.firing_node] = shots.get(shot.firing_node, 0) + 1
	for leaf in plan.get_reaching_firing_positions():
		if not shots.has(leaf):
			order.append(leaf)
	for leaf in order:
		var dmg: Variant = leaf.get_local_value(&"ranged_damage")
		out.append({
			"node": leaf,
			"shots": shots.get(leaf, 0),
			"range": plan.get_node_range(leaf),
			"damage": float(dmg) if dmg != null else 0.0,
		})
	return out


## Cumulative wave sizes strictly below [param cap]: with wave-major fill,
## wave w holds every reaching leaf with more than w shots left.
static func wave_notches(shots_left: Array[int], cap: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var total := 0
	var wave := 0
	while true:
		var size := 0
		for s in shots_left:
			if s > wave:
				size += 1
		if size == 0:
			break
		total += size
		if total >= cap:
			break
		out.append(total)
		wave += 1
	return out


# --- rebuild ----------------------------------------------------------------

## The card order: [member VolleyPreference.order], then every roster type it
## misses in the roster's authored order. An empty preference is the roster.
func _type_order() -> Array[AmmoType]:
	var out: Array[AmmoType] = []
	for id in _pref().order:
		var t := _ROSTER.by_id(id)
		if t != null and not out.has(t):
			out.append(t)
	for t in _ROSTER.sorted():
		if not out.has(t):
			out.append(t)
	return out


## Each special's sticky count clamped, in card order, to its bin and to what
## [param cap] still holds — earlier cards win. Specials only, `{id: n > 0}`.
func _clamped_specials(cap: int, scout_shot: bool) -> Dictionary:
	var counts: Dictionary = {}
	var sum_special := 0
	var special_counts := _pref().special_counts
	for t in _type_order():
		if t.id == _BASE:
			continue
		var c := clampi(special_counts.get(t.id, 0), 0, mini(_stock_for(t, scout_shot), cap - sum_special))
		if c > 0:
			counts[t.id] = c
		sum_special += c
	return counts


## The explicit composition as the plan's ordered list, in card order. Reads
## the preference, never writes it: every clamp lives in the plan only.
## Fill ON: base takes the room the specials leave. Fill OFF: base is the
## held count in `special_counts[BASE_ID]` (read only while fill is off),
## clamped to its bin and to the room — specials win the room.
func _compose(plan: RangedAttackPlan) -> Array[Dictionary]:
	var cap := plan.max_n()
	# A scout shot (#1036, a sensed-only target): only scout arrows fly into
	# fog, so every other bin reads as empty here.
	var scout_shot := plan.is_scout_shot()
	var pref := _pref()
	var order := _type_order()
	var counts := _clamped_specials(cap, scout_shot)
	var sum_special := 0
	for c in counts.values():
		sum_special += int(c)
	var base_stock := _stock_for(_ROSTER.base_type(), scout_shot)
	var base := 0
	if pref.fill:
		base = mini(cap - sum_special, base_stock)
		# The base bin cannot fill the room: top up the specials in card order
		# (at max = stock this is "every arrow fires"). Keeps a scout shot's
		# default composition all scouts, where base reads 0 in fog.
		var shortfall := cap - sum_special - base
		for t in order:
			if shortfall <= 0:
				break
			if t.id == _BASE:
				continue
			var have := int(counts.get(t.id, 0))
			var extra := mini(shortfall, _stock_for(t, scout_shot) - have)
			if extra > 0:
				counts[t.id] = have + extra
				shortfall -= extra
	else:
		base = clampi(int(pref.special_counts.get(_BASE, 0)), 0, mini(base_stock, cap - sum_special))
	if base > 0:
		counts[_BASE] = base
	var list: Array[Dictionary] = []
	for t in order:
		if counts.has(t.id):
			list.append({"type": t.id, "count": int(counts[t.id])})
	return list


func _counts_of(plan: RangedAttackPlan) -> Dictionary:
	var out: Dictionary = {}
	for entry in plan.ammo:
		out[StringName(entry.type)] = int(entry.count)
	return out


## The bin the composer may draw on: the quiver's stock, or 0 for a non-scout
## type while the target is a sensed-only node.
func _stock_for(t: AmmoType, scout_shot: bool) -> int:
	if _quiver == null or t == null:
		return 0
	if scout_shot and not t.is_scout():
		return 0
	return _quiver.stock_of(t.id)


func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var plan := _aimed()
	if plan != null:
		var list := _compose(plan)
		if list != plan.ammo:
			plan.ammo = list
			plan.state_changed.emit()
	_paint(_plan(), plan != null)
	_refreshing = false


func _paint(plan: RangedAttackPlan, has_target: bool) -> void:
	var yield_by_type: Dictionary = _player.reload_yield() if _player != null else {}
	var cap := plan.max_n() if has_target else 0
	var counts: Dictionary = {}
	var n_now := 0
	if has_target:
		for entry in plan.ammo:
			counts[StringName(entry.type)] = int(entry.count)
			n_now += int(entry.count)
	_sync_cards(yield_by_type, counts, cap)

	var segments: Array[Dictionary] = []
	var notches := PackedInt32Array()
	if has_target:
		# Plan-list order: the bar reads left to right as the volley fires.
		for entry in plan.ammo:
			if int(entry.count) > 0:
				segments.append({"type_id": StringName(entry.type), "count": int(entry.count)})
		var shots: Array[int] = []
		for leaf in plan.get_reaching_firing_positions():
			shots.append(leaf.shots_left())
		notches = wave_notches(shots, cap)
	# A launching plan HOLDS the bar: the drained slices stay until the first
	# refresh after control resumes (`is_launching` false before `_reset`).
	var launching := _battle_system != null and _battle_system.is_launching
	_volley_bar.set_volley(n_now, cap, notches, segments, launching)

	var parts: PackedStringArray = []
	for r in leaf_readouts():
		parts.append("%d" % int(r.shots))
	_leaves_label.text = ("%s · %d leaves in range" % [" + ".join(parts), parts.size()]) if has_target else "—"
	_hint.visible = not has_target
	# Informative only (owner: "0 pressure"): no colour, no blocking.
	_capacity_hint.visible = has_target and n_now < cap
	_capacity_hint.text = "room for %d more" % maxi(cap - n_now, 0)

	var total_yield := 0
	for v in yield_by_type.values():
		total_yield += int(v)
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_reload_button.text = "⟳ Reload  +%d  −1 AP" % total_yield
	_reload_button.disabled = not (can_act and _player != null and _player.can_reload())
	# No AP term on purpose: a volley costs 0 AP (#957); `can_afford` is what
	# says so, and it answers 0-AP true for ranged.
	var affordable := _input_ctl == null or _input_ctl.can_afford(plan)
	_launch_button.set_enabled(has_target and plan.is_valid() and can_act and affordable)


## The base card always; a special card per type with stock or reload gain,
## in card order. Special cards are reused across rebuilds and only rebuilt
## when that set changes.
func _sync_cards(yield_by_type: Dictionary, counts: Dictionary, cap: int) -> void:
	var wanted: Array[AmmoType] = []
	for t in _type_order():
		if t.id == _BASE:
			continue
		if _bin(t.id) > 0 or int(yield_by_type.get(t.id, 0)) > 0:
			wanted.append(t)
	var same := wanted.size() == _special_cards.size()
	if same:
		for i in wanted.size():
			if _special_cards[i].type != wanted[i]:
				same = false
				break
	if not same:
		for card in _special_cards:
			_specials.remove_child(card)
			card.queue_free()
		_special_cards.clear()
		for t in wanted:
			var card := _AMMO_CARD_SCENE.instantiate() as AmmoCard
			card.setup(t)
			_connect_card(card)
			_specials.add_child(card)
			_special_cards.append(card)
	_base_card.set_fill(_pref().fill)
	for card in cards():
		var id := card.type.id
		card.set_stock(_bin(id), int(yield_by_type.get(id, 0)))
		card.set_count(int(counts.get(id, 0)), mini(_bin(id), _room_for(id, counts, cap)))


func _bin(type_id: StringName) -> int:
	return _quiver.stock_of(type_id) if _quiver != null else 0


## What "all" may give a type: the base takes the room past every special; a
## special the room past the OTHER specials (the base yields to it).
func _room_for(type_id: StringName, counts: Dictionary, cap: int) -> int:
	var others := 0
	for id in counts:
		if id != _BASE and id != type_id:
			others += int(counts[id])
	return maxi(cap - others, 0)


# --- input ------------------------------------------------------------------

func _on_bar_step(delta: int, by_wave: bool) -> void:
	var plan := _plan()
	if plan == null or plan.target == null:
		return
	if by_wave:
		var leaves := plan.get_reaching_firing_positions().size()
		delta *= maxi(1, leaves)
	adjust_n(delta)


func _on_reload_pressed() -> void:
	if _input_ctl != null:
		_input_ctl.request_reload()


func _unhandled_key_input(event: InputEvent) -> void:
	if _battle_system == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.is_action_pressed(&"ui_volley_fill"):
		toggle_fill()
		get_viewport().set_input_as_handled()
		return
	var plan := _plan()
	if plan == null or plan.target == null:
		return
	match key.physical_keycode:
		KEY_M:
			reset_n_to_max()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if plan.is_valid() and (_input_ctl == null or (_input_ctl.can_player_act() and _input_ctl.can_afford(plan))):
				_battle_system.launch_attack(_armed_plan())
				get_viewport().set_input_as_handled()


func _on_launch_pressed() -> void:
	_battle_system.launch_attack(_armed_plan())
