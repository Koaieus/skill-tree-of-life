@tool
class_name AnnouncementLayer
extends CanvasLayer

## Full-viewport FX layer replacing the old BannerLayer + AnnouncerLayer pair
## (#117, #135). Routes each [AnnouncementRequest] to one of several visual
## bands by [enum AnnouncementRequest.Kind] — [TitleBand] (center, "YOUR
## TURN" / "LEVEL UP") and [CalloutBand] (top, narrow, melee/ranged/spell
## callouts) today, more later. The enum→scene mapping lives in
## [member variant_bindings]: a new visual register is "new Kind + new
## scene", not new plumbing here — every band just needs to extend
## [AnnouncementBand].
##
## Each Kind gets its own FIFO queue + "currently playing" slot, since the
## bands occupy different screen space and can legitimately play in
## parallel (TitleBand and CalloutBand never contend for the same pixels).
##
## Public API ([method enqueue] / [method enqueue_now] / [method clear]) is
## the contract call sites use — see [method HudRoot._on_player_leveled_up]
## for an example building a coalescing [LevelUpAnnouncementRequest].

## Enum→scene contract: pair each [enum AnnouncementRequest.Kind] with the
## [AnnouncementBand] scene that renders it.
@export var variant_bindings: Array[AnnouncementVariantBinding] = []

var _bands: Dictionary = {}  # Kind -> AnnouncementBand
var _queue_by_kind: Dictionary = {}  # Kind -> Array[AnnouncementRequest]
var _current_by_kind: Dictionary = {}  # Kind -> AnnouncementRequest

## Optional turn-state source for staleness checks. When set, requests
## carrying an `{entity}` context get dropped on dequeue if a different
## entity is now acting. See [method AnnouncementRequest.make_for_entity].
var _turn_manager: TurnManager = null
var _battle_system: BattleSystem = null


func _ready() -> void:
	for binding: AnnouncementVariantBinding in variant_bindings:
		if binding == null or binding.scene == null:
			continue
		var band := binding.scene.instantiate() as AnnouncementBand
		if band == null:
			push_error("AnnouncementLayer: %s's scene root doesn't extend AnnouncementBand" % binding.kind)
			continue
		add_child(band)
		band.finished.connect(_on_band_finished.bind(binding.kind))
		_bands[binding.kind] = band
		_queue_by_kind[binding.kind] = []
		_current_by_kind[binding.kind] = null


func bind(battle_system: BattleSystem) -> void:
	if _battle_system != null and _battle_system.attack_launched.is_connected(_on_attack_launched):
		_battle_system.attack_launched.disconnect(_on_attack_launched)
	_battle_system = battle_system
	if _battle_system != null:
		_battle_system.attack_launched.connect(_on_attack_launched)


## Hand in the TurnManager so the layer can drop requests whose entity is no
## longer acting. Optional; without this, all requests play in order.
func bind_turn_manager(tm: TurnManager) -> void:
	_turn_manager = tm


## Standard FIFO, scoped to `req.kind`'s own queue. If `req.coalesce_key()`
## matches the queue's current tail, merges into it (via [method
## AnnouncementRequest.absorb]) instead of appending a second entry. The
## actual dequeue-and-play step is deferred to end-of-frame so a same-frame
## burst (e.g. Entity.leveled_up firing N times synchronously) fully merges
## in the queue before anything displays — see #135.
func enqueue(req: AnnouncementRequest) -> void:
	if req == null:
		return
	var queue: Array = _queue_by_kind.get(req.kind)
	if queue == null:
		push_error("AnnouncementLayer: no band bound for kind %s" % req.kind)
		return
	var key: Variant = req.coalesce_key()
	if key != null and not queue.is_empty() and queue[-1].coalesce_key() == key:
		queue[-1].absorb(req)
	else:
		queue.append(req)
	call_deferred("_pump", req.kind)


## Preempt: drop `req.kind`'s pending queue, interrupt its currently playing
## band (if any), and play [param req] immediately. Use for high-priority
## events that shouldn't wait behind backlog.
func enqueue_now(req: AnnouncementRequest) -> void:
	if req == null or not _queue_by_kind.has(req.kind):
		return
	_queue_by_kind[req.kind] = [req]
	_current_by_kind[req.kind] = null
	_pump(req.kind)


## Drain `kind`'s pending queue without interrupting its currently playing
## band.
func clear(kind: AnnouncementRequest.Kind) -> void:
	if _queue_by_kind.has(kind):
		_queue_by_kind[kind] = []


func _pump(kind: AnnouncementRequest.Kind) -> void:
	if _current_by_kind.get(kind) != null:
		return
	var queue: Array = _queue_by_kind.get(kind)
	if queue == null:
		return
	while not queue.is_empty() and _should_skip(queue[0]):
		queue.pop_front()
	if queue.is_empty():
		return
	var req: AnnouncementRequest = queue.pop_front()
	_current_by_kind[kind] = req
	var band: AnnouncementBand = _bands.get(kind)
	band.play(req)


## True if `req`'s context says the live turn-state has moved past it
## (a different entity is now acting).
func _should_skip(req: AnnouncementRequest) -> bool:
	if req == null or req.context.is_empty() or _turn_manager == null:
		return false
	var ctx_entity := req.context.get(&"entity") as Entity
	if ctx_entity != null and _turn_manager.current_entity != ctx_entity:
		return true
	return false


func _on_band_finished(kind: AnnouncementRequest.Kind) -> void:
	_current_by_kind[kind] = null
	_pump(kind)


func _on_attack_launched(mode: BattleSystem.AttackMode, spell: SpellDef) -> void:
	enqueue(AnnouncementRequest.make(
			_mode_text(mode, spell), "", _mode_style(mode), AnnouncementRequest.Kind.CALLOUT))


func _mode_text(mode: BattleSystem.AttackMode, spell: SpellDef) -> String:
	match mode:
		BattleSystem.AttackMode.MELEE: return "MELEE"
		BattleSystem.AttackMode.RANGED: return "RANGED"
		BattleSystem.AttackMode.MAGIC: return spell.name.to_upper() if spell != null else "MAGIC"
		_: return ""


func _mode_style(mode: BattleSystem.AttackMode) -> AnnouncementRequest.Style:
	match mode:
		BattleSystem.AttackMode.MELEE: return AnnouncementRequest.Style.MELEE
		BattleSystem.AttackMode.RANGED: return AnnouncementRequest.Style.RANGED
		BattleSystem.AttackMode.MAGIC: return AnnouncementRequest.Style.MAGIC
		_: return AnnouncementRequest.Style.DEFAULT
