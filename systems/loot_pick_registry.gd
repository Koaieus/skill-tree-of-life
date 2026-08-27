@tool
class_name LootPickRegistry
extends Node

## The outstanding loot picks nobody has answered yet — the registry
## [CommandApplier]'s `PickLootCommand` branch said #510 deliberately did not
## build (#522).
##
## Two jobs, and they are the same job seen from either end of the wire:
##
## [b]1. It mints request ids.[/b] [LootPickRequest] used to mint its own from a
## per-process `static var`, which is precisely what a wire id must not be: two
## processes mint the same id for different requests the moment their request
## COUNTS diverge, and a peer that never auto-resolves an NPC pick diverges on
## the first relic. One authority minting into one id space also means
## [PickLootCommand] can address a [LootPickRequest] and a [SpellLootRequest]
## with the same field and no kind discriminator — which is what let
## [SpellLootRequest] gain a plain `request_id` instead of a second counter.
##
## [b]2. It parks a request that a REMOTE human owes an answer to[/b], so the
## returning [PickLootCommand] has something to land on. Without this the host
## has no local HUD to claim such a request, auto-resolves it randomly on the
## very next line, and the pick that arrives a round trip later hits an
## already-resolved request and is silently dropped.
##
## [b]A MIRROR peer's registry is inert, always (#564).[/b] [SkillDustAddon]'s
## whole claim chain is HOST-GATED at `_on_carrier_owner_changed` — a peer never
## opens a round on its own, it only replays a [LootRoundCommand] as it arrives
## — so [method park] is never called there. [method pending_count] reads 0 for
## the entire span of a mirror peer's loot round, by construction: there is no
## local state to strand, so there is nothing to leave unresolved. Do not add a
## client-side park/await — see `.claude/rules/multiplayer-sync.md` and the
## owner call this class's issue settled (a mirror decides nothing and
## reproduces nothing it can be told; the resolved outcome rides down as a
## confirmed [LootRoundCommand] instead).
##
## [b]The upward channel and the roster correlation both exist now (#564).[/b]
## The intent channel (#548: [CommandLink] `MIRROR` sends,
## [method CommandApplier._submit_upward] routes a [PickLootCommand] there) and
## the roster CAN say which peer a participant sits at
## ([member Participant.peer_id], [method Participant.is_local] — never
## [SeatPolicy], which is the per-machine half and deliberately never feeds
## anything a peer must reproduce). The other half — mapping a live [Entity]
## back to the [Participant] that seats it — is [member Entity.participant_id],
## set once at [method GameRoot.apply_roster] time. [method is_remote_collector]
## looks the collector's [member Entity.participant_id] up in [member roster]
## and answers from [method Participant.is_local]. Everything the harness could
## already reach without this — a local human picking, an NPC auto-picking, a
## headless auto-resolve — still rides down as a [LootRoundCommand] and needs
## none of it; this only turns on the remote-human branch.
##
## [b]The one thing #463 must not undo.[/b] An answer to a parked request must
## NOT be submitted onto [CommandApplier]'s queue. A round runs inside its own
## [LootRoundCommand]'s application, so the queue is blocked on the very await
## the answer releases, and an enqueued answer can never be reached — a hang,
## not a delay. [method CommandApplier._answer_loot_pick] is the door, and
## [method CommandApplier.submit] routes [PickLootCommand] there rather than
## enqueueing it.

## Injected by [method GameRoot._ready] (#564), never read off an autoload
## in here — a leaf system takes its dependencies, it doesn't go fetch them.
## Null outside an active [GameSession] run (a hand-authored sandbox with no
## lobby); [method is_remote_collector] treats that as "nobody is remote"
## rather than an error.
var roster: ParticipantRoster = null

## This machine's [member Participant.peer_id], from [member GameSession.local_peer_id].
## 0 outside a versus run — see [member GameSession.local_peer_id]'s own doc.
var local_peer_id: int = 0

## Never reused; 1-based, so 0 keeps meaning "no request". An instance member
## rather than a static: two worlds in one process (which the multiplayer
## harness avoids by using two OS processes, but tests do not) must not share a
## counter.
var _next_id: int = 1

## request_id -> the parked [LootPickRequest] or [SpellLootRequest]. Untyped
## values on purpose: the two request classes are deliberately NOT folded
## together (see [SpellLootRequest]'s own note), and this only ever calls
## `resolve` / `is_resolved` on them.
var _parked: Dictionary[int, Variant] = {}


## Stamp [param request] with a fresh id and hold it until a [PickLootCommand]
## answers. Takes either request kind. Returns the minted id.
func park(request: Variant) -> int:
	if request == null:
		return 0
	var id := _next_id
	_next_id += 1
	request.request_id = id
	_parked[id] = request
	return id


## Answer a parked request — the working half of [CommandApplier]'s
## `PickLootCommand` branch. Returns false when the id names nothing (a stale or
## duplicate pick, both of which are normal outcomes rather than errors) or when
## the index is not a member of what was actually offered.
##
## [b]Host-side membership validation lives here[/b], per the owner call that
## the client "may well shuffle" the offer and "all that matters is they send 1
## legal pick back each time". A `chosen_index` of -1 forfeits the round — the
## resolver's documented empty-`chosen` branch, which has to survive the wire
## (an empty array read back as index 0 would silently grant the first
## candidate, which is why [member PickLootCommand.chosen_index] is a signed int
## rather than an array).
func resolve_pick(request_id: int, chosen_index: int) -> bool:
	var request: Variant = _parked.get(request_id)
	if request == null:
		return false
	_parked.erase(request_id)
	if request.is_resolved():
		return false
	if chosen_index < 0:
		request.resolve(_empty_like(request))
		return true
	var candidates: Array = request.candidates
	if chosen_index >= candidates.size():
		push_warning("LootPickRegistry: pick %d is not in the %d-candidate offer for request %d"
				% [chosen_index, candidates.size(), request_id])
		request.resolve(_empty_like(request))
		return false
	request.resolve(_one_like(request, candidates[chosen_index]))
	return true


## [b]There is deliberately no `has_outstanding(entity)` here[/b], though the
## issue's acceptance sketch asked for one to gate End Turn. It would be dead
## code: a round runs INSIDE its [LootRoundCommand]'s application, so
## [member CommandApplier.is_applying] is true for the whole pick and
## [method PlayerInputController.can_player_act] already returns false — the
## End Turn button greys out through the existing `player_can_act_changed`
## path. The same fact makes the collector-death case unreachable rather than
## merely unlikely: no other entity can take a turn while the queue is blocked,
## so nothing can kill a collector mid-pick. Add this back only if a round ever
## stops holding the queue.


## The peer holding [param entity] dropped off the link. NOT "escaping the
## pick" — the player left — so the round forfeits rather than deadlocking
## everyone else's turn order. #463 scopes reconnect out entirely ("LAN, one
## room — a desync is a restart"), so this is as blunt as that.
func forfeit_for(entity: Entity) -> void:
	for id: int in _parked.keys().duplicate():
		var request: Variant = _parked[id]
		if request.collector != entity:
			continue
		_parked.erase(id)
		if not request.is_resolved():
			request.resolve(_empty_like(request))


## Is [param collector] being played by a human on ANOTHER peer? Answers from
## [member roster] via [member Entity.participant_id] — [b]never [SeatPolicy][/b],
## which is the per-machine half of a run's setup and structurally cannot
## answer for a peer (see the class doc, and `.claude/rules/multiplayer-sync.md`).
## False for an NPC (`participant_id == 0`, nothing seats it), false for an
## AI-driven seat (an AI is simulated somewhere, but nobody's *human* input is
## being awaited — see [method Participant.is_local]'s own doc on pairing it
## with a kind check), false for a locally-seated human, true only for a
## human seated by a non-local peer. This is the single place #463 has to
## teach about its roster, and it is deliberately one method rather than a
## condition spread through [SkillDustAddon].
func is_remote_collector(collector: Entity) -> bool:
	if collector == null or roster == null or collector.participant_id == 0:
		return false
	var participant := roster.by_id(collector.participant_id)
	if participant == null or participant.kind == Participant.Kind.AI:
		return false
	return not participant.is_local(local_peer_id)


func pending_count() -> int:
	return _parked.size()


## Drop everything without resolving. Level teardown and test setup only —
## a parked request abandoned mid-flight is a stalled relic, so nothing in
## normal play should call this.
func clear() -> void:
	_parked.clear()


## The correctly-typed empty array for whichever request kind this is. GDScript
## has no generics, so the two candidate types cannot share one helper.
func _empty_like(request: Variant) -> Array:
	if request is SpellLootRequest:
		return [] as Array[SpellDef]
	return [] as Array[StatModifier]


func _one_like(request: Variant, chosen: Variant) -> Array:
	if request is SpellLootRequest:
		return [chosen] as Array[SpellDef]
	return [chosen] as Array[StatModifier]
