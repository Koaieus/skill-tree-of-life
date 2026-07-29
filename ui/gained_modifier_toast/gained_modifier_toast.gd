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
## ## Concurrent batches, never replace
## A rapid second allocation (fast clicking, no turn-gate mid-dwell in some
## flows) must NOT cut off the stack that's still being read. Each call to
## [method show_gains] spawns its own independent batch — its own reveal,
## dwell, and absorb timeline — appended BELOW whatever rows are currently on
## screen. Batches absorb independently and in whatever order their own dwell
## finishes; [method _reflow] then closes the gap by sliding every remaining
## batch's rows up to a contiguous stack, so the pile never grows a permanent
## hole. Nothing here assumes batches finish in the order they were spawned.

## Where the first row lands, in this node's OWN local space (i.e. relative to
## [member float_anchor] once [method show_gains] has repositioned this node
## onto it — see [method _snap_to_anchor]). The absorb exit tweens every row's
## `position` back to [constant Vector2.ZERO], which is exactly the avatar's
## point — that convergence IS the "slide into the avatar" motion.
@export var stack_offset := Vector2(140.0, 6.0)
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
## How long a still-lingering batch takes to slide up and close a gap left by
## an earlier-finishing batch below it (see [method _reflow]).
@export var reflow_duration := 0.2

## World/UI anchor this layer sits on and absorbs into — the Hero avatar's
## float anchor (`HeroSigilCard.float_anchor`). Injected by the composer; see
## the class docstring's "Mount" section. May be null (e.g. a bare unit test
## that only cares about row content/replace behaviour) — [method show_gains]
## simply skips repositioning when so.
@export var float_anchor: Node2D

const _ROW_SCENE: PackedScene = preload("res://ui/tooltip_fan/mod_slab_row.tscn")

## One in-flight allocation's rows + the tween currently driving them (reveal,
## then reassigned to the absorb tween once dwell elapses). Plain inner class
## rather than a Dictionary so callers/tests get typed `.rows` / `.tween`.
class _Batch:
	var rows: Array[ModSlabRow] = []
	var tween: Tween = null

## Batches in spawn order — oldest (topmost on screen) first. A batch is
## erased from this array the instant its absorb finishes, in
## [method _finish_batch], regardless of where it sits in this list; batches
## do not necessarily finish in spawn order (a smaller batch's dwell can lapse
## before a bigger one started earlier).
var _batches: Array[_Batch] = []

# Editor-preview only — lets the layer be tuned in the inspector without
# booting the whole game (mirrors FloaterToaster's own debug button).
@export_tool_button("+ Show sample gains") var _preview_btn: Callable = _show_sample_gains


## Public entry point. Flattens [param modifiers] (composites expand to their
## leaves via [method StatModifier.flatten_all] — one row per leaf, #305/#306)
## and shows them as a new batch, staggered in below whatever rows are already
## on screen, held for [member dwell_duration], then absorbed. Never replaces
## or interrupts a batch already in flight — see the class docstring's
## "Concurrent batches, never replace".
func show_gains(modifiers: Array) -> void:
	var leaves := StatModifier.flatten_all(modifiers)
	if leaves.is_empty():
		return
	_snap_to_anchor()
	var batch := _spawn_batch(leaves)
	_play_reveal(batch)


## Snaps this node onto [member float_anchor]'s current screen position via a
## round-trip through the shared viewport space — copies
## [FloaterToaster]'s `_on_target_moved` technique verbatim (see there for why
## a straight `global_position` assignment isn't safe): the anchor may live in
## a different [CanvasLayer] than this toast. No-op (and no repositioning) when
## [member float_anchor] is unset, e.g. a bare content/replace test. Safe to
## call with older batches already on screen: the anchor is stationary HUD
## geometry, so re-snapping doesn't perturb their (node-local) positions.
func _snap_to_anchor() -> void:
	if not is_instance_valid(float_anchor):
		return
	var canvas_pos: Vector2 = float_anchor.get_global_transform_with_canvas().origin
	global_position = get_canvas_transform().affine_inverse() * canvas_pos


func _total_row_count() -> int:
	var total := 0
	for batch in _batches:
		total += batch.rows.size()
	return total


func _spawn_batch(leaves: Array[StatModifier]) -> _Batch:
	var batch := _Batch.new()
	var start_index := _total_row_count()
	for i in leaves.size():
		var row := _ROW_SCENE.instantiate() as ModSlabRow
		add_child(row)
		row.bind(leaves[i])
		row.position = stack_offset + Vector2(0.0, (start_index + i) * row_height)
		row.set_progress(0.0)
		batch.rows.append(row)
	_batches.append(batch)
	return batch


## Staggered reveal for one batch: each row's `set_progress` tweens 0 → 1,
## delayed by its index × [member stagger] (TooltipFan-style — this layer owns
## the stagger, ModSlabRow has none of its own). Once every row in THIS batch
## has settled and it has held for [member dwell_duration], [method
## _play_absorb] fires for this batch alone — other in-flight batches keep
## their own independent timeline. Chained via `tween_callback` + `set_delay`
## (the same idiom `FloaterToast.animate` uses for its own reveal → hold → exit
## chain) rather than an `await`, so a test can force the whole chain with one
## `Tween.custom_step`.
func _play_reveal(batch: _Batch) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	var last_start := 0.0
	for i in batch.rows.size():
		var row := batch.rows[i]
		var delay := i * stagger
		last_start = maxf(last_start, delay)
		tween.tween_method(row.set_progress, 0.0, 1.0, entry_duration).set_delay(delay)
	tween.tween_callback(_play_absorb.bind(batch)).set_delay(last_start + entry_duration + dwell_duration)
	batch.tween = tween


## The absorb exit for one batch: every row in it fades (`set_progress` 1 → 0)
## while sliding its `position` to [constant Vector2.ZERO] — the avatar's
## exact point, since this node was snapped onto it in [method _snap_to_anchor].
## The motion is the message: rows don't neutral-fade, they visibly travel INTO
## the avatar. Frees the batch's rows once the absorb finishes, then closes the
## gap it leaves via [method _reflow].
func _play_absorb(batch: _Batch) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	for row in batch.rows:
		if not is_instance_valid(row):
			continue
		tween.tween_method(row.set_progress, 1.0, 0.0, exit_duration)
		tween.tween_property(row, "position", Vector2.ZERO, exit_duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_batch.bind(batch)).set_delay(exit_duration)
	batch.tween = tween


func _finish_batch(batch: _Batch) -> void:
	for r in batch.rows:
		if is_instance_valid(r):
			remove_child(r)
			# free(), not queue_free(): the absorb tween that drove this row
			# has already finished by the time this callback runs, so nothing
			# is mid-tween against it — an immediate free avoids a frame of
			# orphan-node lag in tests.
			r.free()
	_batches.erase(batch)
	_reflow()


## Slides every remaining batch's rows up to a contiguous stack starting at
## [member stack_offset], in [member _batches] order — closes whatever gap the
## just-finished batch left, regardless of whether it sat above or below the
## survivors. A no-op per row whose target position hasn't changed (the common
## case: nothing shifts until a batch above it actually finishes).
func _reflow() -> void:
	var offset := 0
	for batch in _batches:
		for i in batch.rows.size():
			var row := batch.rows[i]
			if not is_instance_valid(row):
				continue
			var target_pos := stack_offset + Vector2(0.0, (offset + i) * row_height)
			if not row.position.is_equal_approx(target_pos):
				var tween := create_tween()
				tween.tween_property(row, "position", target_pos, reflow_duration) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		offset += batch.rows.size()


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
