@tool
class_name CommandApplier
extends Node

## The one place a [Command] becomes a world mutation (#510,
## `docs/domain/multiplayer-sync-model.md`). Every peer — host included — runs
## its confirmed commands through exactly one of these, in submission order.
##
## [b]One serial queue.[/b] [method submit] enqueues and, if nothing is being
## applied, drains. If a drain is already in flight it just enqueues and
## returns: a command raised from inside another command's application is
## QUEUED, never applied re-entrantly. That is not a hardening pass bolted on
## later — the codebase already re-enters on the temp-upgrade path
## (`ui/gauges/capacity_blips.gd`'s `pip_clicked -> ... -> _rebuild()` note),
## so the guard ships on day one.
##
## [b]The queue is ASYNC.[/b] Two verbs are not synchronous:
## [MoveCoreCommand] waits a beat between hops so the slides read as a cascade,
## and [EndTurnCommand] runs [method TurnManager.end_turn], which ticks
## initiative and can start an AI turn. A command may therefore take seconds,
## and [member is_applying] must survive the whole await. This copies the shape
## [member BattleSystem.is_launching] already proved works; it deliberately
## does not reuse that flag, which keeps answering the narrower question "is an
## attack in flight" (owner's clarification on #510).
##
## [b]Signal order is load-bearing.[/b] [signal command_applied] fires INSIDE
## the guard, so a fallback handler that submits (the deallocate -> cascade
## offer does exactly this) is queued rather than re-entering.
## [signal applying_changed] fires after the flag clears — the same ordering
## `battle_system.gd:282-289` documents for `is_launching`, and for the same
## reason: the listener reads the flag the instant the signal arrives.
##
## The flip side of that ordering: a [signal command_applied] handler that
## submits UNCONDITIONALLY never lets the drain end. The queue is FIFO and
## terminates exactly when handlers stop feeding it — there is no re-entrancy
## depth to run out of, so a runaway handler is an infinite loop, not a stack
## overflow. Every fallback here latches (PIC's cascade offer fires only on a
## failed deallocate, and the request it opens waits on the player).

## One command finished applying. [param success] is the gated system's own
## verdict — a command that fails its gate is a normal outcome, not an error,
## and never stalls the ones behind it. Emitted while [member is_applying] is
## still true, on purpose (see above).
signal command_applied(command: Command, success: bool)

## One command's WIRE PAYLOAD is final and it is GOING to be applied — mirror it
## now. Fires at most once per command, always before that command's
## [signal command_applied], and never for a command that failed its gate.
##
## [b]Since #540 this fires BEFORE the mutation, not after it.[/b] That is the
## ordering flip: [method _validate] is the gate, so "validated" already means
## "will apply", and the authority no longer has to finish mutating before it can
## tell anyone. Confirm-after-apply structurally put every peer one full mutation
## window behind the authority — see #534.
##
## [b]Why this is not just [signal command_applied].[/b] Two separate reasons,
## and both still hold:
##   * Application spans more than mutation. [method BattleSystem._commit] keeps
##     awaiting after the world has settled, holding `is_launching` until the
##     animation tail finishes so a player cannot arm and fire again mid-swing.
##     Mirroring off `command_applied` made a peer wait out the HOST's animation
##     before starting its own (#511 shipped that way) — lag proportional to
##     spell length.
##   * `command_applied` fires for a REFUSED command too, with success false. A
##     refusal changed nothing and must never cross the wire.
##
## [b]No verb opts out of this ordering (#545).[/b] [LaunchAttackCommand] was the
## last that did — its [AttackRecord] was computed inside the apply, so
## confirming first would have broadcast an empty record that a peer reads as an
## initiate it cannot run. Moving that compute into
## [method BattleSystem.prepare_launch_command], which [method _validate] calls,
## made its payload final at the same point as everyone else's, and the hook it
## opted out through is gone rather than left standing with no callers.
signal command_confirmed(command: Command)

## [member Command.pre_fingerprint] has just been written for a command that is
## about to be validated — the instant this peer's pre-state for it is knowable,
## and BEFORE the gate, so a command that goes on to be refused is still
## compared (#756).
##
## Exists so the divergence check happens at the same point of the same queue on
## both peers. [method CommandLink._on_remote_command] used to compare on
## ARRIVAL, gated on the applier being idle, which meant a burst of commands was
## compared once and the first one to actually diverge could not be named. The
## host's number rides in on [member Command.host_fingerprint]; this is where
## the mirror's own is produced.
signal command_stamped(command: Command)

## A command was submitted on a peer that does NOT decide (#548) — send it
## upward as an INTENT. Carries the command with its [member Command.intent_id]
## already minted; the authority echoes that id back verbatim on the confirm.
##
## A signal rather than a [CommandLink] reference, for the same reason
## [signal command_confirmed] is one: the applier does not know a transport
## exists, and offline it simply has no listener.
signal intent_submitted(command: Command)

## [member is_applying] transitioned. Consumers gate input off this
## ([method PlayerInputController.can_player_act]); it is not an outcome
## signal.
signal applying_changed(applying: bool)

## [member is_awaiting_confirmation] transitioned. Same job as
## [signal applying_changed] and the same ordering guarantee — the flag is
## already updated when this arrives — so the two feed one refresh route in
## [PlayerInputController], never two.
signal awaiting_confirmation_changed(awaiting: bool)

## [method has_outstanding_loot] transitioned (#646). A relic's offer/pick/roll
## sequence now runs OUTSIDE this queue between rounds (see
## [SkillDustAddon]'s class doc), so [member is_applying] no longer implies "a
## pick is outstanding" — this is the gate that has to exist explicitly instead,
## per the owner's 2026-08-27 pick-gate decision. Same signal shape as
## [signal applying_changed] / [signal awaiting_confirmation_changed] so
## [PlayerInputController] wires it the same way.
signal outstanding_loot_changed(has_outstanding: bool)

## Beat between hops of a [MoveCoreCommand]; authored on the handler that
## waits it out, re-exported here because [CameraDirector] and [SkillNode]
## time their slides against it by this name.
const CORE_HOP_SLIDE_DELAY := MoveCoreCommandHandler.CORE_HOP_SLIDE_DELAY

@export var graph: Graph
@export var allocation_system: AllocationSystem
@export var battle_system: BattleSystem
@export var turn_manager: TurnManager

## The outstanding-loot-pick book, for [PickLootCommand] (#522).
@export var loot_pick_registry: LootPickRegistry

## #556: how long [method _pre_roll] holds the drain for a non-local actor's
## command, so [CameraDirector] has time to pan there before the mutation
## lands. Authored independently of [member CameraDirector.default_focus_duration]
## — 0.35 in spirit, but this applier must not read the director. `0.0` (or no
## [member seat_policy]) disables the pre-roll entirely.
@export_range(0.0, 2.0, 0.05) var pre_roll_seconds: float = 0.35

## Who THIS MACHINE plays (#556) — the same [SeatPolicy] [GameRoot] pushes onto
## [CameraDirector], asked here rather than re-derived. `null` until pushed, the
## same as the director's own field: no gate means no pre-roll, which is also
## every fixture's default and why no existing test needed to change.
var seat_policy: SeatPolicy = null

## Is this peer the one that DECIDES, or the one that is told? True offline,
## true on the host, false only while [member CommandLink.mode] is `MIRROR` —
## that setter is the single writer, so nothing has to be kept in sync by hand
## and no scene grows a second role flag.
##
## Almost nothing reads this: a command's application is deliberately the same
## code on every peer, and [LaunchAttackCommand] carries which half of the work
## is already done in its own payload rather than asking about a role. The
## exception is a mutation a peer STARTS on its own, from a local reaction
## rather than from a received command — [SkillDustAddon]'s claim flow opens on
## `owner_changed`, which fires on every peer that applies the allocation. That
## one needs gating; see its `_on_carrier_owner_changed`.
var is_authority: bool = true

## Who this peer is on the link, for minting a globally-unique
## [member Command.intent_id] (#548). Written by [CommandLink]'s `mode` setter
## alongside [member is_authority] — one place, one lifetime — and left at 0
## offline, where there is nobody to collide with.
var local_peer_id: int = 0

## True from the first [method submit] that starts a drain until the queue is
## empty — spanning every await inside every command, not just the mutation.
var is_applying: bool = false

## [b]Submitted, awaiting confirmation[/b] (#541) — a command has been handed to
## this applier and the authority has not yet decided it is going ahead. The
## world has not moved and the player must not act.
##
## [b]Zero-length locally for every verb (#545).[/b] [method submit] drains
## synchronously down to [method _validate], so on a peer that DECIDES this is
## true for a stack frame. It is not dead code: it is the round trip on a peer
## that is told, which is what #463 opens, and it is the only phase name that
## fits the window — [member BattleSystem.is_launching] means "an attack is in
## flight" and [member is_applying] means "a mutation is under way", and neither
## is true yet.
##
## [b]#548 opened that round trip.[/b] On a peer that is TOLD, this is true from
## [method _submit_upward] until the authority's confirm lands in
## [method apply_remote] carrying the same [member Command.intent_id] — or until
## [method refuse_intent] closes it on a refusal. Still zero-length on a peer
## that decides.
##
## The attack used to be the exception and the LONG one, spanning its whole
## resolve + mutation loop because it confirmed late. It no longer is: its
## resolve happens inside the validate this flag closes on, so the window is a
## stack frame here too — the same shape, not a special case with a shorter tail.
##
## [b]Nested inside [member is_applying] everywhere but one place.[/b] The gate
## is an OR ([method PlayerInputController.can_player_act]) and on every path but
## that one the OR cannot change the answer. The exception is the first
## [method submit] of a drain: this flips true BEFORE `is_applying` does, which
## is both the honest reading — the command is submitted, nothing is applying
## yet — and the only moment the third gate is the sole reason the player cannot
## act. Do not "simplify" it to a read after the pop.
var is_awaiting_confirmation: bool = false

## How many relic claim chains this applier is currently driving OUTSIDE the
## queue (#646) — see [method notify_loot_round_opened]. A count, not a bool,
## so two relics claimed back to back (or concurrently, on separate carriers)
## don't stomp each other's close.
var _outstanding_loot_rounds: int = 0

var _queue: Array[Command] = []

## The command [method _drain] has popped and not finished reporting, or null
## between commands. Exists only so [method _refresh_awaiting] can DERIVE its
## answer rather than have it assigned from five places — a `command_applied`
## handler that submits (the deallocate -> cascade offer does) opens a fresh
## pending window on the line before the outgoing command would have closed one,
## and a derived flag gets that right without an ordering rule to remember.
var _in_flight: Command = null

## The command [method confirm] has already announced, so [method _drain] does
## not announce it twice. A single slot, not a set: the queue is serial and
## non-re-entrant, so only one command is ever mid-apply.
var _confirmed: Command = null

## The intent this peer sent upward and has not yet heard back about (#548), or
## null. It is the fourth thing [method _refresh_awaiting] derives from, and the
## only one that can outlive a stack frame — on a peer that is TOLD, this is the
## whole round trip.
##
## A held COMMAND rather than a bare id because a refusal has to hand the very
## command back to [signal command_applied], which is what
## [method PlayerInputController._on_command_applied] already renders.
var _pending_intent: Command = null

## Mint counter for [member Command.intent_id]. Starts at 1, so a minted id is
## never 0 — 0 is what "unminted" means, and what [method Command.to_dict]
## omits.
var _next_intent: int = 1


## Claim the [BattleSystem] as ours to call back into. Set from here rather
## than by a second NodePath export on [BattleSystem] so the applier it
## submits to and the applier that applies for it are the same object by
## construction — two exports could name two.
## `@tool` so a sandbox panel can drive the real queue in-editor (the melee tab
## does). Nothing auto-drives: a drain only ever starts from [method submit].
func _ready() -> void:
	if battle_system != null:
		battle_system.command_applier = self


## Enqueue [param command]. Drains immediately when idle; when a drain is
## already running this returns at once and the in-flight drain picks the
## command up. Never blocks the caller — even the synchronous verbs finish
## inside this call only because they happen to have nothing to await.
##
## [PickLootCommand] is the one exception and bypasses the queue
## ([method CommandHandler.bypasses_queue]) — see [PickLootCommandHandler] for
## why the queue is exactly the wrong place for it.
func submit(command: Command) -> void:
	if command == null:
		return
	# Mint-if-absent, and NEVER unconditionally (#548). A locally-originated
	# command arrives with 0 and gets an id; a decoded INTENT arrives non-zero
	# and is preserved verbatim, because the authority puts a received intent
	# through this same method. An unconditional mint here would overwrite the
	# client's id with a host one, the confirm would echo the host's, and the
	# client's gate would never close.
	if command.intent_id == 0:
		command.intent_id = _mint_intent_id()
	if not is_authority:
		_submit_upward(command)
		return
	var handler := _handler_for(command)
	if handler.bypasses_queue():
		handler.apply(command, _context())
		return
	_enqueue(command)


## A peer that is TOLD does not queue its own command (#548): the intent goes
## up, and the authority's confirm comes back down through
## [method apply_remote] like any other. No local pre-application, no second
## apply path, no prediction (settled, #548 decision 5).
##
## [PickLootCommand] crosses the wire but deliberately does NOT open the
## awaiting gate — it bypasses the queue locally too
## ([PickLootCommandHandler]), so it has never touched
## [member is_awaiting_confirmation] on any peer, and opening a window here that
## nothing closes is exactly the hang this issue exists to not ship.
func _submit_upward(command: Command) -> void:
	if not _handler_for(command).bypasses_queue():
		_pending_intent = command
		_refresh_awaiting()
	intent_submitted.emit(command)


## A command the authority has already CONFIRMED, arriving down the wire — it
## enters the one serial queue exactly as a local one does (#548). Separate from
## [method submit] only because `submit` is now the *intent* door and would send
## this straight back up.
##
## [b]This peer still runs the full [method _drain].[/b] It validates, it
## [method confirm]s — so [signal command_confirmed] fires HERE too, on every
## peer that applies, not only on the authority. #525's camera director hangs
## off that signal; making the confirm authority-only would leave a mirror
## peer's camera dead.
func apply_remote(command: Command) -> void:
	if command == null:
		return
	# The gate closes on THE CONFIRM THIS PEER IS WAITING FOR, and on nothing
	# else: a confirmed command carrying a different id (or none — a
	# host-originated command has an id this peer never minted) leaves the
	# window open. That exactness is what buys `intent_id` over matching on
	# `entity_id`, which any host-raised command for this entity would falsely
	# close.
	if _pending_intent != null and command.intent_id != 0 \
			and command.intent_id == _pending_intent.intent_id:
		_pending_intent = null
	_enqueue(command)


## Unique across peers by construction: the peer id owns the high half, a
## per-peer counter the low half. Never 0 — [member _next_intent] starts at 1.
func _mint_intent_id() -> int:
	var minted := (local_peer_id << 32) | _next_intent
	_next_intent += 1
	return minted


## The queue door both [method submit] and [method apply_remote] arrive at.
func _enqueue(command: Command) -> void:
	_queue.append(command)
	# Ahead of the `is_applying` bail, deliberately — see
	# [member is_awaiting_confirmation]. On the first submit of a drain this is
	# the transition that fires while nothing is applying yet, and a listener
	# reading the gate in that handler must see it closed.
	_refresh_awaiting()
	if is_applying:
		return
	_drain()


## The authority refused the intent [param intent_id] (#548). Closes this peer's
## awaiting window and reports the refusal through the SAME
## [signal command_applied] route a local refusal takes, so
## [method PlayerInputController._on_command_applied] renders it with no new
## feedback path.
##
## [b]It must never [method confirm].[/b] A refused command changed nothing, and
## #525's camera director pans on [signal command_confirmed] — a confirm here
## would pan to a node that did not move.
##
## [param reason] is an enum-ish [StringName], never a UI string; see
## [constant CommandLink.REASON_REFUSED].
func refuse_intent(intent_id: int, reason: StringName = &"") -> void:
	if intent_id == 0 or _pending_intent == null:
		return
	if _pending_intent.intent_id != intent_id:
		return
	var refused := _pending_intent
	last_refusal_reason = reason
	_pending_intent = null
	_refresh_awaiting()
	command_applied.emit(refused, false)


## The link the pending intent went up on is gone — the host quit, the socket
## dropped — so neither the confirm nor the refusal this peer is waiting for
## will ever arrive. Without this the awaiting window stays open forever:
## [member is_awaiting_confirmation] keeps
## [method PlayerInputController.can_player_act] closed on every click, with
## nothing on screen to say why — a silent hang, which is what
## [method NetworkSession._on_link_lost] exists to not ship.
##
## Not routed through [method refuse_intent]: that one insists on a matching
## non-zero id, and here the whole point is that nobody is left to name one.
## Reports through the same [signal command_applied] refusal route so whatever
## renders a refusal renders this.
func abandon_pending_intent(reason: StringName = &"link_lost") -> void:
	if _pending_intent == null:
		return
	var abandoned := _pending_intent
	last_refusal_reason = reason
	_pending_intent = null
	_refresh_awaiting()
	command_applied.emit(abandoned, false)


## Why the authority refused this peer's last intent, for a diagnostic to read.
## A [StringName] code, never presentation text.
var last_refusal_reason: StringName = &""


## How many commands are waiting behind the one being applied. Tests read this;
## nothing in production should need it.
func pending_count() -> int:
	return _queue.size()


## A relic's claim chain opened on THIS applier (#646) — called only from the
## authority side of [SkillDustAddon]'s `_on_carrier_owner_changed`, since a
## MIRROR peer never drives a chain, only replays it. Paired with
## [method notify_loot_round_closed], called from the same authority-gated
## site once the chain's terminal round lands.
func notify_loot_round_opened() -> void:
	_outstanding_loot_rounds += 1
	if _outstanding_loot_rounds == 1:
		outstanding_loot_changed.emit(true)


func notify_loot_round_closed() -> void:
	if _outstanding_loot_rounds <= 0:
		return
	_outstanding_loot_rounds -= 1
	if _outstanding_loot_rounds == 0:
		outstanding_loot_changed.emit(false)


## Is a relic claim chain being driven right now, whether or not this queue is
## also empty? [PlayerInputController.can_player_act] gates on this exactly as
## it does [member is_applying] / [member is_awaiting_confirmation] — see
## [signal outstanding_loot_changed]'s note for why this stopped being implied
## by [member is_applying] alone.
func has_outstanding_loot() -> bool:
	return _outstanding_loot_rounds > 0


## "This command's payload is final and it is going to be applied" — announce it
## to the mirror. [method _drain] calls this for every verb at the flip point,
## and since #545 nothing else calls it in production; it stays public and
## idempotent because that is what makes the flip point the ONLY announcement
## even when something announces twice.
##
## Only ever call it once the command is known to be GOING AHEAD — a refused
## command changed nothing and must not cross the wire. Idempotent, and safe to
## call from a verb that is running without an applier only because the caller
## null-checks first.
func confirm(command: Command) -> void:
	if command == null or _confirmed == command:
		return
	_confirmed = command
	# BEFORE the announcement, so a [signal command_confirmed] handler —
	# [CommandLink]'s broadcast is one — reads a flag that already accounts for
	# this decision. Same hazard [signal applying_changed] documents, one signal
	# earlier. (It stays true if something is queued behind: the flag asks
	# "anything undecided", not "is THIS one decided".)
	_refresh_awaiting()
	command_confirmed.emit(command)


## [b]validate -> confirm -> apply[/b] (#540), for every verb without exception
## (#545). The ordering flip: the authority decides a command is legal, announces
## it, and only THEN mutates — so [method _apply] is the shared
## post-confirmation apply every peer runs, authority included, instead of the
## authority's mutation being what a confirm reports after the fact.
##
## [b]The gate moved; it did not multiply.[/b] [method _validate] asks the same
## `can_*` queries the mutating verbs already ask themselves
## ([method AllocationSystem.can_allocate] and friends), so a command that
## validates is a command that will apply. That is what makes confirming first
## safe, and it is why the gate must never be re-derived here — a second copy of
## a rule is the shape `.claude/rules/` forbids.
##
## [b]One verb's validate also PRODUCES.[/b] [LaunchAttackCommand]'s gate is
## "resolve the attack, then check the attacker can afford what came out", and
## the resolution it has to run IS the command's wire payload. So
## [method BattleSystem.prepare_launch_command] resolves (on a shadow — nothing
## real moves) and stamps the record from inside the validate, which is what let
## #545 delete the last confirm-after-apply exception. Do not read `_validate` as
## side-effect-free; read it as "the command is final and legal, or it is
## refused".
##
## The two verbs where validate cannot fully answer for apply are known and
## deliberate: [MoveCoreCommand] can only vet its FIRST hop (a partial core walk
## is a legal observable state, #458 decision 4), and [MassAllocateCommand]
## re-computes its affordable count at apply time on purpose (#458 — a stale
## sender must never dictate how much the authority spends). Both still land
## identically on every peer, because every peer applies the same command
## through this same method.
func _drain() -> void:
	is_applying = true
	applying_changed.emit(true)
	while not _queue.is_empty():
		var command: Command = _queue.pop_front()
		_in_flight = command
		# Stamped BEFORE the gate, for EVERY command on EVERY peer (#540
		# decision 4) — this is the world the command is about to be applied to,
		# and both sides compare pre-state against pre-state. Uniform rather than
		# staged: nothing has to unwind when [LaunchAttackCommand] stops being
		# an exception. See [member Command.pre_fingerprint].
		if graph != null:
			command.pre_fingerprint = WorldFingerprint.compute(graph)
		# The one moment this peer's pre-state is knowable for THIS command, and
		# therefore the only honest place to compare it against the host's stamp
		# (#756). Emitted for every command on every peer; [CommandLink] is the
		# only listener and it answers on a MIRROR only.
		command_stamped.emit(command)
		var success := _validate(command)
		if success:
			# THE FLIP, and since #545 there is no branch around it: every verb
			# reaches here with its whole payload final, the attack included —
			# [method BattleSystem.prepare_launch_command] stamped its record
			# inside the validate above.
			confirm(command)
			await _pre_roll(command)
			@warning_ignore("redundant_await")
			success = await _apply(command)
		# Inside the guard, deliberately — see the class note. Fires for a
		# validate-fail too, with success false: a refused command is a normal
		# outcome and [method PlayerInputController._on_command_applied] is what
		# turns it into player feedback, including the deallocate -> cascade
		# offer. Skipping the emit on a validate-fail would silently delete that.
		command_applied.emit(command, success)
		# Cleared only once this command is fully reported, so the de-dup covers
		# a `command_applied` handler that confirms too. Nothing is leaked by
		# holding it one line longer: the next iteration overwrites it.
		_confirmed = null
		_in_flight = null
		# After BOTH are cleared, or the derivation below would read "in flight,
		# unconfirmed" and re-open a window that just closed. This is where a
		# command REFUSED by [method _validate] releases — it never confirmed, so
		# nothing else would have.
		_refresh_awaiting()
	is_applying = false
	applying_changed.emit(false)


## #556: a fixed pause between a command's confirmation and its mutation, for a
## NON-LOCAL actor only, so [CameraDirector] has time to pan there before the
## world changes under it. Called from inside [method _drain]'s :385-:422
## bracket, so [member is_applying] is already true across it — the same
## guarantee that already spans [MoveCoreCommand]'s inter-hop beat.
##
## [b]A fixed timer, never a wait on the camera.[/b] Awaiting presentation
## itself would put presentation on the mutation path
## (`.claude/rules/presentation-clock.md`); this is a clock, not a dependency.
##
## [b]The seat predicate is the SAME question [CameraDirector] asks[/b]
## ([method SeatPolicy.seats], pushed here by [GameRoot] the same way it is
## pushed onto the director) — not a second copy of the rule. An actor that
## fails to resolve is treated as unframeable, exactly as
## [method CameraDirector._build_command_request] treats it, rather than as
## "not seated": falling through would delay every command whose actor this
## applier cannot look up.
##
## [b]Seat-gated on purpose, confirmed safe under the sync model (#556).[/b]
## [method _drain] runs identically on every peer, so this makes a
## seat-dependent peer apply at a different wall-clock moment than another —
## timing drift, not divergence, under host-authoritative
## confirmed-command-down: outcomes come from the command itself, never from
## when `_drain` happens to resume. See `docs/domain/multiplayer-sync-model.md`.
func _pre_roll(command: Command) -> void:
	if seat_policy == null or graph == null or pre_roll_seconds <= 0.0:
		return
	var actor := graph.get_by_entity_id(command.entity_id)
	if actor == null or seat_policy.seats(actor):
		return
	await get_tree().create_timer(pre_roll_seconds).timeout


## Recompute [member is_awaiting_confirmation] from what the queue actually
## holds, and announce a transition. Derived rather than assigned: "something is
## submitted and undecided" is exactly `queued, or popped and not yet
## confirmed`, and every call site below is a point where one of those changed.
##
## Flag first, emit second — [method PlayerInputController._emit_gate_changed]
## reads the gate the instant the signal arrives, and a listener that saw a stale
## "still pending" would leave `AttackModeBar` disabled forever (#541; the same
## hazard `battle_system.gd:489-494` documents for `is_launching`).
func _refresh_awaiting() -> void:
	var awaiting := not _queue.is_empty() \
			or (_in_flight != null and _confirmed != _in_flight) \
			or _pending_intent != null
	if awaiting == is_awaiting_confirmation:
		return
	is_awaiting_confirmation = awaiting
	awaiting_confirmation_changed.emit(awaiting)


## Is [param command] legal against the world as it stands right now? The gate,
## and since #540 the ONLY gate that decides whether a command confirms.
##
## For [LaunchAttackCommand] it is also where the payload is produced — see
## [method _drain]'s note, and do not assume every handler's gate is read-only.
##
## One lookup, same as [method _apply] — [CommandRegistry] is the ONE table of
## verbs, so the two can never disagree about which verb a command is (#999).
## No handler re-implements a verb's rules: each forwards to the owning
## system's own `can_*` query, which the mutating call then asks again. That
## second ask is not a duplicate check, it is the mutating method keeping its
## own guarantees for its non-command callers.
##
## Diagnostics for an unresolvable id live in the handler's `validate` rather
## than its `apply`, because a command that fails to resolve fails before the
## apply runs — leaving the warning downstream would lose it.
func _validate(command: Command) -> bool:
	return _handler_for(command).validate(command, _context())


## Run the verb — the shared post-confirmation apply, run by every peer
## including the authority. The handler's null-guards are structural, not
## gates: [method _validate] has already resolved the same ids and reported
## anything that failed, so they return quietly rather than warning twice.
func _apply(command: Command) -> bool:
	@warning_ignore("redundant_await")
	return await _handler_for(command).apply(command, _context())


## The verb's [CommandHandler], or a refusing placeholder for a tag the
## registry does not know — a decoded command always has one (the codec is the
## same table), so this only fires for a hand-built command of a type that
## forgot its registration line, which `test_command_registry.gd` catches.
func _handler_for(command: Command) -> CommandHandler:
	var handler := CommandRegistry.handler_for(command)
	if handler == null:
		push_warning("CommandApplier: no handler for command tag '%s'" % command.type_tag())
		return CommandHandler.new()
	return handler


## The system bundle a handler mutates through — built per call rather than
## cached, so a system wired after `_ready` (every test fixture does this) is
## seen, and no handler ever holds a system reference across calls.
func _context() -> CommandContext:
	var ctx := CommandContext.new()
	ctx.graph = graph
	ctx.allocation_system = allocation_system
	ctx.battle_system = battle_system
	ctx.turn_manager = turn_manager
	ctx.loot_pick_registry = loot_pick_registry
	ctx.tree = get_tree()
	return ctx
