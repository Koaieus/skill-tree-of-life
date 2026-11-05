@tool
class_name LootPickRegistry
extends Node

## The outstanding loot picks nobody has answered yet. Mints the request ids
## [PickLootCommand] addresses, and parks a request owed an answer by a REMOTE
## human so the returning command has something to land on. A mirror peer's
## registry parks nothing (a relic's claim chain is host-gated); an answer to a
## parked request is never enqueued on [CommandApplier] (the queue is blocked
## on the await it releases). See docs/domain/loot-system.md.

## A request was parked for a REMOTE collector (#646) — [LootOfferChannel] listens
## for this to send the matching [LootPickOffer] to the one peer that owes the
## answer ([method peer_for]). Fired from [method park] itself rather than by the caller,
## so nothing can park a request and forget to announce it.
signal offer_parked(request: Variant)

## An addressed [LootPickOffer] arrived for a collector THIS peer seats —
## [LootSystem] opens its mirror-side picker on this. Emitted by [method
## receive_offer] only after its ownership gate, so a listener never re-asks.
signal offer_received(offer: LootPickOffer)

## The board an incoming offer's `collector_id` resolves against — the receive
## side's one extra dependency, wired by the composing scene. Null (a fixture
## that only parks) means [method receive_offer] can resolve nobody and drops
## every offer.
@export var graph: Graph

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
	offer_parked.emit(request)
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


## [b]`has_outstanding` lives on [CommandApplier], not here (#646).[/b] It used
## to be dead code by construction: a round ran INSIDE its [LootRoundCommand]'s
## application, so [member CommandApplier.is_applying] covered the whole pick
## and nothing else could act — the collector-death case was unreachable for
## the same reason. #646 moved the offer/pick/roll sequence OUTSIDE the command
## pipeline (it has to, so a remote human's pick no longer holds the host's
## queue — issue #646 acceptance 3), so `is_applying` no longer implies "a pick
## is outstanding" and the gate has to exist for real. It is a
## [CommandApplier] concern rather than a registry one because this registry
## only ever hears about REMOTE (parked) picks; a LOCAL or UNCLAIMED round
## still has to hold the SAME gate, and [SkillDustAddon] is the one thing that
## sees all three uniformly.


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


## Is [param collector] played by a human sitting at THIS peer — the receive-side
## question; [method receive_offer] gates on it. Not the negation of
## [method is_remote_collector]: a run with no roster is one machine, so
## everyone is local and nobody is remote. Roster-sourced, never [SeatPolicy].
## See docs/domain/loot-system.md "is_local_collector vs is_remote_collector".
func is_local_collector(collector: Entity) -> bool:
	if collector == null:
		return false
	if roster == null:
		return true
	if collector.participant_id == 0:
		return false
	var participant := roster.by_id(collector.participant_id)
	if participant == null or participant.kind == Participant.Kind.AI:
		return false
	return participant.is_local(local_peer_id)


## The peer that seats [param collector]'s human — where the send side
## ADDRESSES a [LootPickOffer], so nobody else hears of a pick until it lands
## as a [LootRoundCommand]. 0 when no human seats it (NPC, AI seat, no roster,
## unknown participant): there is nobody to ask. Roster-sourced, like both
## predicates below.
func peer_for(collector: Entity) -> int:
	if collector == null or roster == null or collector.participant_id == 0:
		return 0
	var participant := roster.by_id(collector.participant_id)
	if participant == null or participant.kind == Participant.Kind.AI:
		return 0
	return participant.peer_id


## The receive side: an offer arrived off the link. Resolves its collector on
## [member graph] and emits [signal offer_received] only if THIS peer seats
## it ([method is_local_collector]). The offer is addressed, so the gate is a
## sanity check — but it is also what keeps a misaddressed offer from raising
## a picker whose answer would submit a pick for someone else's collector. An
## unresolvable collector drops too: the offer cannot be for this peer.
func receive_offer(offer: LootPickOffer) -> void:
	if offer == null or graph == null:
		return
	var collector := graph.get_by_entity_id(offer.collector_id)
	if collector == null or not is_local_collector(collector):
		return
	offer_received.emit(offer)


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
