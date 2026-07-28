@tool
class_name GainedModifierToast
extends Node2D

## "You just got these." (#306, epic #159 Phase 0.) When the player allocates a
## node, shows the node's actual [ModSlabRow] slabs beside the Hero avatar —
## staggered in, held long enough to read, then slid INTO the avatar while
## fading, signalling absorption. Allocation-only by design (loot/level-up gains
## are out of scope, see the issue); batch-per-allocation, not per-modifier.
##
## Its own layer, deliberately NOT routed through [FloaterDirector]/[FloaterToaster]
## — different dwell (much longer, meant to be READ), different anchor (the
## avatar, not the event position), different exit (directional absorb, not
## drift-and-fade). Sharing the floater queue would force its timing model onto
## a surface that exists to be slower.
##
## Fully standalone: instantiate, set [member float_anchor], call
## [method show_gains]. No HUD, no AllocationSystem wiring baked in here — see
## "Mount" below for what a composer (GameRoot/HudRoot, wired elsewhere) needs
## to do.
##
## ## Reuse contract
## Rows are bare [ModSlabRow] instances (#221/#306's "second consumer" of its
## standalone contract) — this layer BINDS them (`bind(m)`) and DRIVES their
## reveal (`set_progress(t)`) itself, exactly per `.claude/rules/tooltip-fan.md`'s
## "content rows take set_progress, driven by their panel" rule. [method
## ModSlabRow.play_entry] does not exist any more and is never called here.
##
## ## Mount (for the integration commit — this scene does not wire itself)
## - Add an instance under HudRoot (or wherever the Hero avatar lives in the
##   scene tree) as a sibling of [HeroSigilCard], so it draws on top.
## - Set `float_anchor = hud_root.hero_sigil_card.float_anchor` — same DI
##   pattern as `scenes/game_root.gd`'s `floater_director.player_anchor` wiring.
## - Connect `AllocationSystem.allocated(node, entity, forced)`, and call
##   `toast.show_gains(node.modifiers)` — gated:
##     - `entity == <the player entity>` — this is the HERO avatar's toast;
##       NPC allocations must not fire it.
##     - `not forced` — mirrors the existing convention for cosmetic gain
##       reactions (`AllocationSystem`'s own docstring: "#71 modifier pulses +
##       #70 floaters gate on `not forced`, so a level's setup allocations
##       don't fire a pulse/floater flurry"). A forced allocation (spawn/procgen)
##       is not a player choice and has nothing for the player to "just got".
##
## ## Replace, never queue
## A second allocation is turn-gated and cannot land mid-dwell in real play, so
## no queue exists. If [method show_gains] is called again before the previous
## stack finished (e.g. a test, or a future rules change), the running
## tween is killed and the old rows are dropped immediately — the new stack
## replaces it outright, it does not stack dwells or wait its turn.

## Where the first row lands, in this node's OWN local space (i.e. relative to
## [member float_anchor] once [method show_gains] has repositioned this node
## onto it — see [method _snap_to_anchor]). The absorb exit tweens every row's
## `position` back to [constant Vector2.ZERO], which is exactly the avatar's
## point — that convergence IS the "slide into the avatar" motion.
@export var stack_offset := Vector2(140.0, -54.0)
## Vertical spacing between stacked rows.
@export var row_height := 26.0

@export_group("Timing")
## Per-row reveal tween (`ModSlabRow.set_progress` 0 → 1).
@export var entry_duration := 0.22
## Per-index delay between rows starting their reveal (TooltipFan-style stagger
## — this layer owns it; ModSlabRow has no delay knob of its own).
@export var stagger := 0.08
## How long the fully-revealed stack holds before absorbing. Deliberately
## longer than a combat floater's hold (`FloaterToast.visible_duration`
## defaults to 1.75s) — the point of this surface is that the player actually
## reads what they got, not a glance-and-gone number.
@export var dwell_duration := 2.2
## The absorb exit: `set_progress` 1 → 0 (fade) run in parallel with `position`
## sliding to [constant Vector2.ZERO] (the avatar).
@export var exit_duration := 0.4

## World/UI anchor this layer sits on and absorbs into — the Hero avatar's
## float anchor (`HeroSigilCard.float_anchor`). Injected by the composer; see
## the class docstring's "Mount" section. May be null (e.g. a bare unit test
## that only cares about row content/replace behaviour) — [method show_gains]
## simply skips repositioning when so.
@export var float_anchor: Node2D

const _ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/mod_slab_row.tscn")

## Current stack, in display order. Source of truth for row count — cleared
## synchronously by [method _clear_rows] (not just `queue_free`d), so a test
## (or an immediate replace) never observes stale members.
var _rows: Array[ModSlabRow] = []
var _tween: Tween = null

# Editor-preview only — lets the layer be tuned in the inspector without
# booting the whole game (mirrors FloaterToaster's own debug button).
@export_tool_button("+ Show sample gains") var _preview_btn: Callable = _show_sample_gains


## Public entry point. Flattens [param modifiers] (composites expand to their
## leaves via [method StatModifier.flatten_all] — one row per leaf, #305/#306)
## and shows them as one staggered stack beside [member float_anchor], held for
## [member dwell_duration], then absorbed. A call made before a previous stack
## finished REPLACES it outright (kills the running tween, drops the old rows
## immediately) — see the class docstring's "Replace, never queue".
func show_gains(modifiers: Array) -> void:
	var leaves := StatModifier.flatten_all(modifiers)
	if leaves.is_empty():
		return
	_reset()
	_snap_to_anchor()
	_spawn_rows(leaves)
	_play_reveal()


## Kills whatever this layer was doing and drops its current rows — the
## "replace" half of the no-queue contract. Safe to call with nothing running.
func _reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_clear_rows()


func _clear_rows() -> void:
	for r in _rows:
		if is_instance_valid(r):
			remove_child(r)
			# free(), not queue_free(): whatever tween drove this row (ours)
			# has already been killed or has already finished by every call
			# site of this method, so nothing is mid-tween against it — an
			# immediate free avoids a frame of orphan-node lag in tests.
			r.free()
	_rows.clear()


func _spawn_rows(leaves: Array[StatModifier]) -> void:
	for i in leaves.size():
		var row := _ROW_SCENE.instantiate() as ModSlabRow
		add_child(row)
		row.bind(leaves[i])
		row.position = stack_offset + Vector2(0.0, i * row_height)
		row.set_progress(0.0)
		_rows.append(row)


## Snaps this node onto [member float_anchor]'s current screen position via a
## round-trip through the shared viewport space — copies
## [FloaterToaster]'s `_on_target_moved` technique verbatim (see there for why
## a straight `global_position` assignment isn't safe): the anchor may live in
## a different [CanvasLayer] than this toast. No-op (and no repositioning) when
## [member float_anchor] is unset, e.g. a bare content/replace test.
func _snap_to_anchor() -> void:
	if not is_instance_valid(float_anchor):
		return
	var canvas_pos: Vector2 = float_anchor.get_global_transform_with_canvas().origin
	global_position = get_canvas_transform().affine_inverse() * canvas_pos


## Staggered reveal: each row's `set_progress` tweens 0 → 1, delayed by its
## index × [member stagger] (TooltipFan-style — this layer owns the stagger,
## ModSlabRow has none of its own). Once every row has settled and the stack
## has held for [member dwell_duration], [method _play_absorb] fires — chained
## via `tween_callback` + `set_delay` (the same idiom `FloaterToast.animate`
## uses for its own reveal → hold → exit chain) rather than an `await`, so a
## test can force the whole chain with one `Tween.custom_step`.
func _play_reveal() -> void:
	_tween = create_tween()
	_tween.set_parallel(true)
	var last_start := 0.0
	for i in _rows.size():
		var row := _rows[i]
		var delay := i * stagger
		last_start = maxf(last_start, delay)
		_tween.tween_method(row.set_progress, 0.0, 1.0, entry_duration).set_delay(delay)
	_tween.tween_callback(_play_absorb).set_delay(last_start + entry_duration + dwell_duration)


## The absorb exit: every row fades (`set_progress` 1 → 0) while sliding its
## `position` to [constant Vector2.ZERO] — the avatar's exact point, since this
## node was snapped onto it in [method _snap_to_anchor]. The motion is the
## message: rows don't neutral-fade, they visibly travel INTO the avatar.
## Frees the rows once the absorb finishes.
func _play_absorb() -> void:
	_tween = create_tween()
	_tween.set_parallel(true)
	for row in _rows:
		if not is_instance_valid(row):
			continue
		_tween.tween_method(row.set_progress, 1.0, 0.0, exit_duration)
		_tween.tween_property(row, "position", Vector2.ZERO, exit_duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_clear_rows).set_delay(exit_duration)


func _show_sample_gains() -> void:
	var samples: Array[StatModifier] = []
	var strength := StatModifier.new()
	strength.stat_id = &"strength"
	strength.operation = StatModifier.Operation.ADD_BASE
	strength.value = 4.0
	samples.append(strength)
	var armor := StatModifier.new()
	armor.stat_id = &"armor"
	armor.operation = StatModifier.Operation.ADD_BONUS
	armor.value = 3.0
	samples.append(armor)
	show_gains(samples)
