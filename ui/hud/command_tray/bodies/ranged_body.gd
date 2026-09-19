@tool
class_name RangedBody
extends CommandTrayBodyBase
## Ranged tab content — the Quiver's view (#954), as the magic body is the
## [SpellBook]'s: an ammo card per owned type, one notched [VolleyBar] for
## the whole volley, the reload row with its projected yield, and Launch.
##
## Composition rule (owner, 2026-09-19): the player sets N and each
## SPECIAL's count; **base arrows are the remainder** `N − Σ specials`. N
## defaults to max on every target pick and is not kill-snapped; special
## counts are STICKY across target picks within the body's life, clamped to
## their bin (and to N) on every rebuild. If the specials exceed N, N grows
## to fit. The body writes exactly one thing into the plan —
## [member RangedAttackPlan.ammo_counts] — and submits one command,
## [ReloadCommand] via [method PlayerInputController.request_reload].
##
## Readouts, all of them: `N / max` on the bar with the typed segments,
## notches at the wave boundaries, the per-leaf contribution ("2+2+1") with
## each leaf's range / damage read from the PLAN (node-local, so a
## Watchtower on one leaf moves that leaf's readout only — never the entity
## board), each card's stock / `+N on reload` / effect, and the reload
## button's `+yield (1 AP)`. No kills text anywhere (owner: "TMI").
##
## Input: scroll on the bar ±1 (Shift = ±wave), `M` back to max, steppers on
## each special card, `Enter` launches; `R` reloads via the input controller.
## No per-frame work: one rebuild per plan state change / adjustment.

const _AMMO_CARD_SCENE := preload("res://ui/hud/command_tray/bodies/ammo_card.tscn")
const _ROSTER: AmmoTypeRoster = preload("res://attack/ammo/ammo_type_roster.tres")

@onready var _hint: Label = %Hint
@onready var _leaves_label: Label = %LeavesLabel
@onready var _volley_bar: VolleyBar = %VolleyBar
@onready var _roster: HBoxContainer = %Roster
@onready var _reload_button: Button = %ReloadButton
@onready var _reset_button: Button = %ResetButton
@onready var _launch_button: LaunchAttackButton = %LaunchButton

## Sticky special counts `{type_id: n}` — the player's last setting per
## special, re-clamped on every rebuild.
var _special_counts: Dictionary[StringName, int] = {}
## N while the player has moved it off max; ignored while [member _n_at_max].
var _n: int = 0
## Owner: "default N : max" — true until the player adjusts N, reset on a
## new target, restored by `M` / [method reset_n_to_max].
var _n_at_max: bool = true
var _last_target: SkillNode = null
var _cards: Array[AmmoCard] = []
var _quiver: Quiver = null
var _refreshing := false


func _on_bound() -> void:
	_reset_button.pressed.connect(_battle_system.reset_plan)
	_launch_button.pressed.connect(_battle_system.launch_attack)
	_reload_button.pressed.connect(_on_reload_pressed)
	_volley_bar.step_requested.connect(_on_bar_step)
	_volley_bar.set_requested.connect(set_n)
	_battle_system.attack_plan_state_changed.connect(_refresh)
	if _input_ctl != null:
		_input_ctl.player_can_act_changed.connect(_refresh.unbind(1))
	_quiver = _player.stat_board.arrows as Quiver if _player != null and _player.stat_board != null else null
	if _quiver != null:
		_quiver.bin_changed.connect(_refresh.unbind(1))
	_special_counts.clear()
	_n_at_max = true
	_last_target = null
	_refresh()


func teardown() -> void:
	if _battle_system != null:
		if _battle_system.attack_plan_state_changed.is_connected(_refresh):
			_battle_system.attack_plan_state_changed.disconnect(_refresh)
		if _reset_button.pressed.is_connected(_battle_system.reset_plan):
			_reset_button.pressed.disconnect(_battle_system.reset_plan)
		if _launch_button.pressed.is_connected(_battle_system.launch_attack):
			_launch_button.pressed.disconnect(_battle_system.launch_attack)
	if _input_ctl != null and _input_ctl.player_can_act_changed.is_connected(_refresh.unbind(1)):
		_input_ctl.player_can_act_changed.disconnect(_refresh.unbind(1))
	if _quiver != null and _quiver.bin_changed.is_connected(_refresh.unbind(1)):
		_quiver.bin_changed.disconnect(_refresh.unbind(1))
	_quiver = null
	if _reload_button.pressed.is_connected(_on_reload_pressed):
		_reload_button.pressed.disconnect(_on_reload_pressed)
	if _volley_bar.step_requested.is_connected(_on_bar_step):
		_volley_bar.step_requested.disconnect(_on_bar_step)
	if _volley_bar.set_requested.is_connected(set_n):
		_volley_bar.set_requested.disconnect(set_n)
	for card in _cards:
		card.queue_free()
	_cards.clear()


# --- composition controls -------------------------------------------------

func _plan() -> RangedAttackPlan:
	return _battle_system.attack_plan as RangedAttackPlan if _battle_system != null else null


func max_n() -> int:
	var plan := _plan()
	return plan.max_n() if plan != null and plan.target != null else 0


## Arrows in the volley as currently composed (Σ of the plan's counts).
func n() -> int:
	var plan := _plan()
	return plan.n() if plan != null and plan.target != null else 0


func set_n(value: int) -> void:
	_n = value
	_n_at_max = false
	_refresh()


func adjust_n(delta: int) -> void:
	set_n(n() + delta)


func reset_n_to_max() -> void:
	_n_at_max = true
	_refresh()


## Lowering a special by more than the base bin can absorb lowers N with it:
## base is the remainder and never a control, and at N = max every arrow in
## the quiver fires, so the only way to fire fewer specials there is a
## smaller volley.
func set_special(type_id: StringName, value: int) -> void:
	if type_id == AmmoTypeRoster.BASE_ID:
		return
	value = maxi(0, value)
	var plan := _plan()
	if plan != null and plan.target != null:
		var before := int(plan.ammo_counts.get(type_id, 0))
		if value < before:
			var base_now := int(plan.ammo_counts.get(AmmoTypeRoster.BASE_ID, 0))
			var base_bin := _quiver.stock_of(AmmoTypeRoster.BASE_ID) if _quiver != null else 0
			var drop := (before - value) - maxi(0, base_bin - base_now)
			if drop > 0:
				_n = n() - drop
				_n_at_max = false
	_special_counts[type_id] = value
	_refresh()


func step_special(type_id: StringName, delta: int) -> void:
	set_special(type_id, _special_counts.get(type_id, 0) + delta)


func cards() -> Array[AmmoCard]:
	return _cards


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

## Clamp the sticky specials, derive base as the remainder, and write the
## explicit composition into the plan (only when it changed — the plan's
## `state_changed` re-enters here and must find nothing to do).
func _compose(plan: RangedAttackPlan) -> Dictionary:
	var cap := plan.max_n()
	var counts: Dictionary = {}
	var sum_special := 0
	for t in _ROSTER.sorted():
		if t.id == AmmoTypeRoster.BASE_ID:
			continue
		var c := clampi(_special_counts.get(t.id, 0), 0, mini(_quiver.stock_of(t.id) if _quiver != null else 0, cap - sum_special))
		_special_counts[t.id] = c
		if c > 0:
			counts[t.id] = c
		sum_special += c
	var target_n := cap if _n_at_max else clampi(_n, 0, cap)
	target_n = maxi(target_n, sum_special)
	_n = target_n  # N grew to fit the specials: remember the grown value
	var base := mini(target_n - sum_special, _quiver.stock_of(AmmoTypeRoster.BASE_ID) if _quiver != null else 0)
	# The base bin cannot fill N: top up the specials in roster order (at
	# N = max = stock this is simply "every arrow fires").
	var shortfall := target_n - sum_special - base
	if shortfall > 0 and _quiver != null:
		for t in _ROSTER.sorted():
			if shortfall <= 0:
				break
			if t.id == AmmoTypeRoster.BASE_ID:
				continue
			var have := int(counts.get(t.id, 0))
			var extra := mini(shortfall, _quiver.stock_of(t.id) - have)
			if extra > 0:
				counts[t.id] = have + extra
				shortfall -= extra
	if base > 0:
		counts[AmmoTypeRoster.BASE_ID] = base
	return counts


func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var plan := _plan()
	var has_target := plan != null and plan.target != null
	if has_target:
		if plan.target != _last_target:
			_last_target = plan.target
			_n_at_max = true
		var counts := _compose(plan)
		if counts != plan.ammo_counts:
			plan.ammo_counts = counts
			plan.state_changed.emit()
	else:
		_last_target = null
	_paint(plan, has_target)
	_refreshing = false


func _paint(plan: RangedAttackPlan, has_target: bool) -> void:
	var yield_by_type: Dictionary = _player.reload_yield() if _player != null else {}
	var cap := plan.max_n() if has_target else 0
	var counts: Dictionary = plan.ammo_counts if has_target else {}
	var n_now := 0
	for c in counts.values():
		n_now += int(c)
	_sync_cards(yield_by_type, counts, cap, n_now)

	var segments: Array[Dictionary] = []
	var notches := PackedInt32Array()
	if has_target:
		for t in _ROSTER.sorted():
			var c := int(counts.get(t.id, 0))
			if c > 0:
				segments.append({"type_id": t.id, "count": c})
		var shots: Array[int] = []
		for leaf in plan.get_reaching_firing_positions():
			shots.append(leaf.shots_left())
		notches = wave_notches(shots, cap)
	_volley_bar.set_volley(n_now, cap, notches, segments)

	var parts: PackedStringArray = []
	for r in leaf_readouts():
		parts.append("%d" % int(r.shots))
	_leaves_label.text = ("%s · %d leaves in range" % [" + ".join(parts), parts.size()]) if has_target else "—"
	_hint.visible = not has_target

	var total_yield := 0
	for v in yield_by_type.values():
		total_yield += int(v)
	var can_act := _input_ctl == null or _input_ctl.can_player_act()
	_reload_button.text = "+%d (1 AP)" % total_yield
	_reload_button.disabled = not (can_act and _player != null and _player.can_reload())
	_launch_button.set_enabled(has_target and plan.is_valid() and can_act)


## One card per type with stock or reload gain, in roster order; cards are
## reused across rebuilds and only rebuilt when the owned set changes.
func _sync_cards(yield_by_type: Dictionary, counts: Dictionary, cap: int, n_now: int) -> void:
	var wanted: Array[AmmoType] = []
	for t in _ROSTER.sorted():
		var stock := _quiver.stock_of(t.id) if _quiver != null else 0
		if stock > 0 or int(yield_by_type.get(t.id, 0)) > 0:
			wanted.append(t)
	var same := wanted.size() == _cards.size()
	if same:
		for i in wanted.size():
			if _cards[i].type != wanted[i]:
				same = false
				break
	if not same:
		for card in _cards:
			_roster.remove_child(card)
			card.queue_free()
		_cards.clear()
		for t in wanted:
			var card := _AMMO_CARD_SCENE.instantiate() as AmmoCard
			card.setup(t)
			card.step_requested.connect(step_special)
			card.set_requested.connect(set_special)
			_roster.add_child(card)
			_cards.append(card)
	for card in _cards:
		var id := card.type.id
		card.set_stock(_quiver.stock_of(id) if _quiver != null else 0, int(yield_by_type.get(id, 0)))
		var c := int(counts.get(id, 0))
		# A special may grow by what N can still absorb past the other
		# specials — and past N itself, since N grows to fit.
		var others := n_now - c - int(counts.get(AmmoTypeRoster.BASE_ID, 0))
		var room := (cap - others) if cap > 0 else 0
		card.set_count(c, mini(_quiver.stock_of(id) if _quiver != null else 0, maxi(room, 0)))


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
	var plan := _plan()
	if plan == null or plan.target == null:
		return
	match key.physical_keycode:
		KEY_M:
			reset_n_to_max()
			get_viewport().set_input_as_handled()
		KEY_ENTER, KEY_KP_ENTER:
			if plan.is_valid() and (_input_ctl == null or _input_ctl.can_player_act()):
				_battle_system.launch_attack()
				get_viewport().set_input_as_handled()
