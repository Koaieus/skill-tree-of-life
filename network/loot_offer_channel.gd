class_name LootOfferChannel
extends LinkChannel
## #646's downward offer, split off [CommandLink] (#1179): "show this collector
## a pick screen, here is the draw" ([LootPickOffer]). NOT a [Command]: it
## mutates nothing on arrival, so it never touches [CommandApplier] at all.
## Rides [signal LootPickRegistry.offer_parked], host-side only —
## [method LootPickRegistry.peer_for] resolves who it is addressed to; nobody
## but the picker needs to know until the pick lands as a [LootRoundCommand].
##
## [member LinkChannel.deferred_until_world] is true: an offer names a
## `collector_id` the applier's graph resolves against (null mid-generation),
## binds a [signal Entity.died] handler on an entity a resync is about to
## reconcile, and parks [code]LootSystem._pending_mirror_request[/code]. It also
## cannot be FOR a peer still joining — an offer follows its collector's own
## claim, and a joining peer has taken no action to claim from — and the whole
## window is pre-HUD, so nothing is listening to answer it either way.

## Wire envelope keys — the offer's own key, not merged into the payload: one
## key per concept even where several nest a plain [Dictionary].
const KEY_OFFER := "offer"
const KIND_LOOT_OFFER := "loot_offer"

## The outstanding-pick book. Null is supported (no registry wired): the offer
## leg simply never sends, and nothing arrives to hand off.
@export var loot_pick_registry: LootPickRegistry


func _init() -> void:
	deferred_until_world = true


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_connect_registry()


func _on_attached() -> void:
	_connect_registry()


func _connect_registry() -> void:
	if loot_pick_registry != null and not loot_pick_registry.offer_parked.is_connected(_on_offer_parked):
		loot_pick_registry.offer_parked.connect(_on_offer_parked)


func kinds() -> Array[String]:
	return [KIND_LOOT_OFFER]


func receive(_kind: String, payload: Dictionary) -> void:
	if link != null and link.role != NetworkConfig.Role.CLIENT:
		return
	var offer := LootPickOffer.from_dict(payload.get(KEY_OFFER, {}))
	if loot_pick_registry != null:
		loot_pick_registry.receive_offer(offer)
	_log("← loot offer (request %d, collector %d)" % [offer.request_id, offer.collector_id])


## [method LootPickRegistry.park] only ever parks a REMOTE claim
## ([LootRoundCommandHandler]'s `_await_pick`), so every [signal
## LootPickRegistry.offer_parked] this connects to is, by construction, a pick
## that owes a downward offer — ADDRESSED to [method LootPickRegistry.peer_for]'s
## answer.
func _on_offer_parked(request: Variant) -> void:
	var peer_id := loot_pick_registry.peer_for(request.collector)
	if peer_id == 0:
		_log("✗ loot offer: no peer seats the collector")
		return
	send_loot_offer(_offer_for(request), peer_id)


func _offer_for(request: Variant) -> LootPickOffer:
	if request is SpellLootRequest:
		return LootPickOffer.for_spell_request(request as SpellLootRequest)
	return LootPickOffer.for_stat_request(request as LootPickRequest)


## Send [param offer] to [param peer_id] alone. Mutates nothing and carries no
## [Command].
func send_loot_offer(offer: LootPickOffer, peer_id: int) -> void:
	if link == null or offer == null:
		return
	if link.send_to(peer_id, {NetworkLink.KEY_KIND: KIND_LOOT_OFFER, KEY_OFFER: offer.to_dict()},
			NetworkConfig.Role.HOST):
		_log("→ loot offer (request %d, collector %d) to peer %d" %
				[offer.request_id, offer.collector_id, peer_id])


func _log(line: String) -> void:
	if link != null:
		link.logged.emit(line)
