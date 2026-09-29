class_name AttackPresenter
extends AttackStage

## The live [AttackStage]: draws a committed attack — [MeleePreview]'s swing
## for melee, a [VFXCoordinator] mounted under [AttackVFX] for ranged/magic —
## and answers the camera's focus. A pure observer: it reads the plan and the
## outcome to time itself and never mutates; [BattleSystem] owns the reveal
## clock, the mutation loop and the cascade. Mounted by `game_root.tscn` and
## wired to `%AttackVFX` / `%MeleePreview`.
##
## [b]Load-bearing invariant: nothing may free the animating node mid-play.[/b]
## A coroutine awaiting a freed object is silently dropped, so [signal finished]
## would never fire and [BattleSystem] would park on it forever — a permanent
## hang, not a cosmetic glitch. It happened to melee once (the cascade fires
## mid-swing, and `MeleePreview._refresh` tore down the blade `launch()` was
## awaiting); `MeleePreview._live_swing` is the guard that closes it. The only
## free of a coordinator is [method AttackVFX.play]'s own, after its await.

## The `AttackVFX` mount ranged/magic coordinators are spawned under. Typed
## [Node2D] and called duck-typed (`mount`, `play`, `RANGED_VOLLEY_COORDINATOR`)
## because `presentation/` ranks below `ui/` in `docs/architecture.md`'s
## layers, and naming the class would be an upward edge.
@export var attack_vfx: Node2D
@export var melee_preview: MeleePreview

## The wind-up SHAPE a committed attack is staged on. Null takes
## [method PresentationTempo.shared_default] — the authored `.tres`, which is
## what every level uses. A plain instance var rather than an `@export`: shape
## is authored content, and a fixture that wants zero-length beats hands over
## its own copy instead of mutating the shared default under every other test.
var presentation_tempo: PresentationTempo = null

## The ranged/magic coordinator mounted for the launch in flight — mounted at
## commit so it answers [method focus] before the mutation loop starts; null
## between launches, for melee, and with no [member attack_vfx].
var _coordinator: Node2D = null

## True while the melee swing is parked in [method MeleePreview.launch]. Set
## BEFORE [method play]'s first await, so the caller's un-awaited call has
## already latched it by the time it asks [method holds_release]; false there
## means "already finished" and [signal finished] is never waited on. Melee
## only: the coordinator modes run fire-and-forget and must never touch it, or
## an un-awaited runner would emit into the NEXT launch's park.
var _swinging: bool = false

## The plan [method mount] was handed, until [method unmount]. Only
## [method focus] reads it — the camera asks without a plan in hand.
var _plan: AttackPlan = null


func tempo() -> PresentationTempo:
	return presentation_tempo if presentation_tempo != null \
			else PresentationTempo.shared_default()


## A mirror's melee draws off `last_trajectory` / `last_events`, which only a
## resolve fills in; this starts it, stepped by the preview's frame pump, so
## [method MeleePreview.launch] may find it already complete. Draw-only per
## ADR 0002, so a spectating peer may downgrade fidelity for free.
func prepare_replay(plan: AttackPlan) -> void:
	if not plan is MeleeAttackPlan or melee_preview == null:
		return
	var low_fidelity := Settings.current.melee_peer_sim_fidelity \
			== GameSettings.PeerSimFidelity.LOW
	var substeps := 1 if low_fidelity else BladeSim.DEFAULT_SUBSTEPS
	melee_preview.begin_replay(plan as MeleeAttackPlan, substeps, not low_fidelity)


## Mount the ranged/magic coordinator: a magic plan's spell names its own
## scene, ranged uses the default volley. Nothing for melee — the preview is
## already mounted and has the ghost.
func mount(plan: AttackPlan, outcome: AttackOutcome) -> void:
	_plan = plan
	_coordinator = null
	if attack_vfx == null or plan is MeleeAttackPlan:
		return
	var coord_scene: PackedScene = null
	var magic_plan: MagicAttackPlan = plan as MagicAttackPlan
	if magic_plan != null and magic_plan.spell != null:
		coord_scene = magic_plan.spell.vfx_coordinator_scene
	if coord_scene == null:
		coord_scene = attack_vfx.RANGED_VOLLEY_COORDINATOR
	_coordinator = attack_vfx.mount(coord_scene)
	if _coordinator != null:
		_coordinator.outcome = outcome


func begin_windup(plan: AttackPlan) -> float:
	var presenter := _focus_for(plan)
	if presenter == null:
		return 0.0
	return presenter.begin_windup(plan, tempo())


func stages(plan: AttackPlan) -> bool:
	return _focus_for(plan) != null


## Melee animates the swing on the same `BladeHitEvent.t` clock the applier
## lands hits on, so the blade visibly reaches a node as it takes its hit.
## Ranged/magic runs its coordinator fire-and-forget and reports nothing: the
## launch releases on [member BattleSystem.release_beat], and
## [method AttackVFX.play] tears the coordinator down when its last arrow fades.
func play(plan: AttackPlan, outcome: AttackOutcome) -> void:
	var schedule: OutcomeSchedule = outcome.schedule if outcome != null else null
	if plan is MeleeAttackPlan:
		if melee_preview == null:
			return
		_swinging = true
		await melee_preview.launch(plan as MeleeAttackPlan, schedule)
		_swinging = false
		finished.emit()
		return
	if _coordinator != null:
		await attack_vfx.play(_coordinator, outcome)


func holds_release(plan: AttackPlan) -> bool:
	return plan is MeleeAttackPlan and _swinging


func focus() -> Node:
	return _focus_for(_plan) if _plan != null else null


func unmount() -> void:
	_plan = null
	_coordinator = null


## [MeleePreview] for melee, the coordinator mounted at commit for
## ranged/magic. Both answer `begin_windup` / `focus_marker` /
## `focus_marker_changed` (ADR 0027) and share no base class, so callers
## duck-type it.
func _focus_for(plan: AttackPlan) -> Node:
	if plan is MeleeAttackPlan:
		return melee_preview
	if _coordinator != null and is_instance_valid(_coordinator):
		return _coordinator
	return null


## [param battle]'s presenter, mounting a bare one as its child when it has no
## stage yet — for a code-composed world (the dev sandboxes, fixtures) that
## wires the preview and the VFX mount onto it afterwards. A level mounts its
## presenter from `game_root.tscn` instead.
static func ensure_on(battle: BattleSystem) -> AttackPresenter:
	var presenter := battle.stage as AttackPresenter
	if presenter == null:
		presenter = AttackPresenter.new()
		presenter.name = "AttackPresenter"
		battle.add_child(presenter)
		battle.stage = presenter
	return presenter
