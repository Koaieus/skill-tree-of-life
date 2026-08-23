@tool
extends PanelContainer

## Outcome playground (#539) — replay a recorded [AttackRecord] with no network
## and no live attack in the loop.
##
## [b]What this instrument is for.[/b] If a recorded outcome plays back
## perfectly timed here, then anything that breaks after #540's ordering flip is
## a MESSAGING bug and cannot be a replay bug. Having that separation in hand
## before the flip is the whole point — building it afterwards would mean
## debugging two things at once (#534).
##
## [b]The unit of replay is a serialized [LaunchAttackCommand] dict[/b] — `plan`
## + `record` + `seed`, exactly what crosses the wire. Capture ▶ fires a real
## attack as the authority and keeps the command it stamped its record onto;
## Replay ▶ pushes that same dictionary, through `var_to_bytes` and
## [CommandCodec], into this world's own [CommandApplier] with **no
## [CommandLink] attached**. That is byte-for-byte the peer path, which is what
## makes this a proof rather than a demo.
##
## [b]Recorded outcomes only.[/b] Authoring an [AttackOutcome] by hand is a
## separate, much bigger tab (#534 fork 4) and a different claim; this loads and
## replays what the game produced. See [OutcomeFixture].
##
## [b]Every replay re-arms first.[/b] A replay MUTATES, so a second one without
## a reset lands on an already-chewed board and cannot reproduce the recorded
## fingerprint. Reading a red ✗ there as a replay bug is the obvious wrong turn,
## so the button does not offer the choice — Replay is arm-then-submit, one
## action, the same as `scenes/dev/outcome_playground_world.gd`'s `arm()` +
## submit in the headless test. (Plain text, not a BBCode link: that builder
## deliberately carries no `class_name`, the same call `sandbox_world.gd` makes,
## so there is nothing for a `[method …]` to resolve against.)
##
## [b]Tempo scale is INERT, on purpose.[/b] It exists as the seam the
## schedule-compiler sibling plugs into later — the control is wired, its value
## is displayed, and nothing reads it. Instant, beside it, is real: it toggles
## [member BattleSystem.instant_mutation], which jumps the world to its settled
## state without the beat clock.

## Hard reset for [SandboxLiveTab]'s Reload button (#144) — a wedged launch, a
## half-applied cascade, a world you no longer trust.
signal reload_requested

const _SANDBOX_WORLD: Script = preload("res://scenes/dev/sandbox_world.gd")
const _PLAYGROUND_WORLD: Script = preload("res://scenes/dev/outcome_playground_world.gd")

## Where Save writes, and where the headless test reads from.
const FIXTURE_DIR := "res://test/fixtures/outcome/"

## Room left around the authored layout when it is fitted to the viewport.
const _FIT_MARGIN: float = 60.0

@onready var _world: SubViewport = %World
@onready var _world_host: Node2D = %WorldHost
@onready var _capture_button: Button = %CaptureBtn
@onready var _replay_button: Button = %ReplayBtn
@onready var _reset_button: Button = %ResetBtn
@onready var _save_button: Button = %SaveBtn
@onready var _spell_list: OptionButton = %SpellList
@onready var _instant_toggle: CheckBox = %InstantToggle
@onready var _tempo_slider: HSlider = %TempoSlider
@onready var _tempo_label: Label = %TempoLabel
@onready var _fixture_name: LineEdit = %FixtureName
@onready var _status: RichTextLabel = %StatusLabel

var _builder: RefCounted
var _graph: Graph
var _alloc: AllocationSystem
var _alloc_vfx: AllocationVFX
var _battle: BattleSystem
var _applier: CommandApplier
var _turn_manager: TurnManager

## The command in hand — captured live, or rebuilt from a loaded fixture.
var _fixture: OutcomeFixture
## Fingerprints of the last run, whichever kind it was.
var _last_before: int = 0
var _last_after: int = 0
## Cascade layer sizes seen during the last run, e.g. `[1, 2]`. Acceptance 3:
## the shatter stagger is driven off these, so a replay that lost its layers
## would show `[3]` (or nothing) where the live run showed `[1, 2]`.
var _last_layers: Array[int] = []
var _live_layers: Array[int] = []
## True while a capture or a replay is in flight — both buttons gate on it, the
## same way [member BattleSystem.is_launching] serialises real launches.
var _busy: bool = false
## Spelled out rather than inferred: `_status` is rebuilt from these.
var _last_kind: String = ""
var _verdict: String = ""


func _ready() -> void:
	_build_world()
	_wire_controls()
	_populate_spells()
	_layout_world()
	_world.size_changed.connect(_layout_world)
	_refresh_status()


## Sandbox-host contract — an [OutcomeFixture] selected in the Inspector becomes
## the loaded one, so the tab doubles as its viewer.
func load_object(obj: Object) -> void:
	if obj is OutcomeFixture:
		load_fixture(obj as OutcomeFixture)


# ── Composition ──────────────────────────────────────────────────────────────

## Real systems through the shared scaffold, plus the shared world builder. The
## builder is what the headless fixture test also calls: two callers, one
## definition of "the board a fixture was captured against".
##
## `attack_vfx` is requested because acceptance 1 is *world state AND VFX are
## identical between the live run and the replay* — with no [AttackVFX] mounted
## the magic branch of `BattleSystem._commit` silently draws nothing and the
## VFX half of that claim could not be observed at all. It is observed here, by
## eye; only the world half is asserted, headlessly, by the fixture test.
func _build_world() -> void:
	_builder = _PLAYGROUND_WORLD.new()
	_graph = _builder.build(_world_host)

	var world = _SANDBOX_WORLD.new()
	world.name = "SandboxWorld"
	_world.add_child(world)
	world.build(_graph, {input = true, attack_vfx = true})
	_alloc = world.allocation_system
	_alloc_vfx = world.allocation_vfx
	_battle = world.battle_system
	_applier = world.command_applier
	_turn_manager = world.turn_manager
	# Who the input channels act AS — without it every click is refused as "not
	# the player's", and the plan's own `attacker` is not enough (#459's setter).
	world.input_controller.player = _builder.attacker
	_battle.cascade_started.connect(_on_cascade_started)
	arm_world()


func _wire_controls() -> void:
	_capture_button.pressed.connect(_on_capture_pressed)
	_replay_button.pressed.connect(_on_replay_pressed)
	_reset_button.pressed.connect(arm_world)
	_save_button.pressed.connect(_on_save_pressed)
	_instant_toggle.toggled.connect(_on_instant_toggled)
	_tempo_slider.value_changed.connect(_on_tempo_changed)
	_on_tempo_changed(_tempo_slider.value)
	_on_instant_toggled(_instant_toggle.button_pressed)


func _populate_spells() -> void:
	_spell_list.clear()
	for spell in SpellCatalog.ALL:
		_spell_list.add_item(spell.name if spell.name != "" else str(spell.id))
	_spell_list.selected = 0


func _selected_spell() -> SpellDef:
	var idx := _spell_list.selected
	return SpellCatalog.ALL[idx] if idx >= 0 and idx < SpellCatalog.ALL.size() else SpellCatalog.SPARK


# ── World state ──────────────────────────────────────────────────────────────

## Back to the canonical pre-state. Also the Reset button.
##
## [AllocationVFX] is muted across it because the strips are genuine
## `force_deallocate` calls — un-muted, resetting would shatter the whole board
## every time, which is presentation for something that is not gameplay.
func arm_world() -> void:
	if _busy or _battle.is_launching:
		return
	_arm()
	_refresh_status()


## The reset itself, past the human-facing guard above — Capture and Replay run
## it while `_busy` is deliberately true, so the guard cannot live in here.
func _arm() -> void:
	# Guarded, not unconditional: `cancel_attack` push_warnings when there is no
	# plan to cancel, which is the COMMON case here — every Reset click with
	# nothing armed, and the first arm inside `_build_world`. An instrument that
	# logs a warning as part of its resting state trains you to ignore its log.
	if _battle.is_attacking:
		_battle.cancel_attack()
	_alloc_vfx.muted = true
	_builder.arm(_alloc, _turn_manager)
	_alloc_vfx.muted = false


func _layout_world() -> void:
	var size := Vector2(_world.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# Measured off the LIVE nodes, not the builder's `LAYOUT` const: the builder
	# is the other half of #539 and its authored table is free to move, while
	# what has to be fitted here is whatever ended up on the board.
	var nodes := _graph.get_skill_nodes() if _graph != null else []
	if nodes.is_empty():
		return
	var bounds := Rect2(nodes[0].position, Vector2.ZERO)
	for node in nodes:
		bounds = bounds.expand(node.position)
	var span := bounds.size + Vector2.ONE * (2.0 * _FIT_MARGIN)
	var factor: float = minf(1.0, minf(size.x / span.x, size.y / span.y))
	_world_host.scale = Vector2.ONE * factor
	_world_host.position = size * 0.5 - bounds.get_center() * factor


# ── Capture / replay ─────────────────────────────────────────────────────────

## Fire a real attack as the AUTHORITY and keep what it stamped. This is the
## ordinary game path — `build_launch_command` then submit — not a shortcut into
## [method BattleSystem.apply_launch_command], so what a fixture records is what
## the game produces.
func _on_capture_pressed() -> void:
	if _busy:
		return
	_busy = true
	_refresh_status()
	_arm()
	_builder.arm_magic(_battle, _selected_spell())
	var before := WorldFingerprint.compute(_graph)
	var command := _battle.build_launch_command()
	if command == null:
		_verdict = "[color=#ff8f6b]nothing launchable — check the plan[/color]"
		_busy = false
		_refresh_status()
		return
	# `.clear()`, not `= []`: assigning an untyped literal to an `Array[int]`
	# is the conversion GDScript refuses at runtime.
	_last_layers.clear()
	await _submit_and_wait(command)
	var after := WorldFingerprint.compute(_graph)
	if command.record.is_empty():
		_verdict = "[color=#ff8f6b]the authority stamped no record[/color]"
		_busy = false
		_refresh_status()
		return
	_fixture = OutcomeFixture.capture(command, before, after,
			"%s cast from a_leaf onto d_gate, captured in the outcome playground."
			% _selected_spell().id)
	_live_layers = _last_layers.duplicate()
	_last_before = before
	_last_after = after
	_last_kind = "captured"
	_verdict = "[color=#8fd6ff]captured — press Replay[/color]"
	_busy = false
	_refresh_status()


## Re-arm, then push the held command through the applier. See the class note on
## why the re-arm is not optional.
func _on_replay_pressed() -> void:
	if _busy or _fixture == null:
		return
	_busy = true
	_refresh_status()
	_arm()
	var before := WorldFingerprint.compute(_graph)
	# Over the wire, not straight out of the resource: `var_to_bytes` is what a
	# transport actually does, and it is the step that would reject a payload
	# holding a live Object.
	var command := _fixture.to_command_over_the_wire()
	if command == null:
		_verdict = "[color=#ff8f6b]fixture payload did not decode[/color]"
		_busy = false
		_refresh_status()
		return
	# `.clear()`, not `= []`: assigning an untyped literal to an `Array[int]`
	# is the conversion GDScript refuses at runtime.
	_last_layers.clear()
	await _submit_and_wait(command)
	_last_before = before
	_last_after = WorldFingerprint.compute(_graph)
	_last_kind = "replayed"
	_verdict = _replay_verdict(before)
	_busy = false
	_refresh_status()


## The ✓/✗ line, and it reports the two halves separately on purpose: a
## pre-state mismatch means the BOARD drifted (re-capture), while a matching
## pre-state with a diverged post-state means the REPLAY PATH changed — which is
## the failure this instrument exists to catch.
func _replay_verdict(before: int) -> String:
	if before != _fixture.world_fingerprint_at_capture:
		return "[color=#ff8f6b]✗ pre-state drifted (%d ≠ %d) — re-capture[/color]" \
				% [before, _fixture.world_fingerprint_at_capture]
	if _last_after != _fixture.expected_fingerprint:
		return "[color=#ff8f6b]✗ world diverged (%d ≠ %d)[/color]" \
				% [_last_after, _fixture.expected_fingerprint]
	if not _live_layers.is_empty() and _last_layers != _live_layers:
		return "[color=#ffd479]⚠ world matched, cascade layers did not (%s vs %s)[/color]" \
				% [str(_last_layers), str(_live_layers)]
	return "[color=#7dffa0]✓ identical[/color]"


## Submit and wait for THIS command, not for the queue to empty — the same loop
## [method BattleSystem.launch_attack] runs, and for the same reasons stated
## there.
func _submit_and_wait(command: Command) -> void:
	var finished: Array[bool] = [false]
	var on_applied := func(applied: Command, _ok: bool) -> void:
		if applied == command:
			finished[0] = true
	_applier.command_applied.connect(on_applied)
	_applier.submit(command)
	while not finished[0] and _applier.is_applying:
		await _applier.command_applied
	_applier.command_applied.disconnect(on_applied)


## Acceptance 3's instrument: [AllocationVFX] staggers its shatter spawn off
## these layers, so recording their SHAPE is how "the cascade replayed with its
## layers intact" becomes something you can read rather than something you hope.
func _on_cascade_started(layers: Array, _defender: Entity) -> void:
	for layer in layers:
		_last_layers.append((layer as Array).size())


# ── Fixture I/O ──────────────────────────────────────────────────────────────

## Adopt a fixture from the Inspector (or from Load) without replaying it.
func load_fixture(fixture: OutcomeFixture) -> void:
	_fixture = fixture
	_live_layers.clear()
	_last_kind = "loaded"
	_verdict = "[color=#8fd6ff]loaded — press Replay[/color]"
	if is_inside_tree():
		_refresh_status()


## Write the held fixture to `test/fixtures/outcome/`. Editor-only: this is how
## a committed fixture is authored, and there is nothing to write to at runtime.
func _on_save_pressed() -> void:
	if _fixture == null:
		return
	if not Engine.is_editor_hint():
		_verdict = "[color=#ff8f6b]saving is editor-only[/color]"
		_refresh_status()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	var stem := _fixture_name.text.strip_edges()
	if stem.is_empty():
		stem = "outcome"
	var path := FIXTURE_DIR + stem + ".tres"
	var err := ResourceSaver.save(_fixture, path)
	if err != OK:
		_verdict = "[color=#ff8f6b]save failed (%d) → %s[/color]" % [err, path]
	else:
		_verdict = "[color=#7dffa0]saved → %s[/color]" % path
		EditorInterface.get_resource_filesystem().scan()
	_refresh_status()


# ── Controls ─────────────────────────────────────────────────────────────────

func _on_instant_toggled(on: bool) -> void:
	_battle.instant_mutation = on
	_refresh_status()


## Wired, displayed, and read by nothing. See the class note — this is the seam
## the schedule-compiler sibling plugs into, not a knob that does something now.
func _on_tempo_changed(value: float) -> void:
	_tempo_label.text = "%.2f× (inert)" % value


func _refresh_status() -> void:
	if not is_inside_tree():
		return
	_capture_button.disabled = _busy
	_replay_button.disabled = _busy or _fixture == null
	_reset_button.disabled = _busy
	_save_button.disabled = _busy or _fixture == null
	var lines: Array[String] = []
	if _fixture == null:
		lines.append("[color=#8b98a8]no command in hand — Capture, or select an OutcomeFixture in the Inspector[/color]")
	else:
		lines.append("fixture: pre [b]%d[/b] → expected [b]%d[/b]%s" % [
			_fixture.world_fingerprint_at_capture, _fixture.expected_fingerprint,
			"  ·  " + _fixture.captured_at if _fixture.captured_at != "" else "",
		])
	if _last_kind != "":
		lines.append("last %s: %d → %d  ·  cascade layers %s" % [
			_last_kind, _last_before, _last_after, str(_last_layers)])
	if _verdict != "":
		lines.append(_verdict)
	lines.append("[color=#8b98a8]%s[/color]" % WorldFingerprint.describe(_graph))
	_status.text = "\n".join(lines)
