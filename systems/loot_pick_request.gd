class_name LootPickRequest
extends RefCounted

## A pick-ONE-from-M loot choice passed over `Events.loot_pick_requested`; there
## is no pick count (N is [member SkillDustAddon.rounds], one request per round).
## `emit()` is synchronous: a UI consumer sets [member claim] to LOCAL inside its
## handler, and the emitter auto-resolves a random pick if it is still UNCLAIMED.
## `claim` is tri-state because a REMOTE human is picking elsewhere: park, do not
## auto-resolve. [method resolve] is idempotent.
## See docs/domain/loot-system.md "The handshake".

## Who is answering this request. See the handshake note above.
enum Claim {
	UNCLAIMED,  ## Nobody took it — the emitter auto-resolves a random pick.
	LOCAL,      ## A HUD on THIS machine is presenting it.
	REMOTE,     ## A human on another peer is picking; park and wait for the pick.
}

## Correlates a [PickLootCommand] back to the request that asked, since several
## can be queued at once (`ui/hud/hud_root.gd` `_enqueue_pick`). 0 means "not
## registered" — an unparked request is answered by its own picker, not by a
## command, and needs no id.
##
## [b]Minted by [LootPickRegistry], not here (#522).[/b] This was a per-process
## `static var _next_request_id` counter, which is exactly what a wire id must
## not be: two processes mint the same id for different requests the moment
## their request COUNTS diverge, and a peer that never auto-resolves an NPC pick
## diverges immediately. One authority minting into one id space also lets
## [PickLootCommand] address a [SpellLootRequest] with the same field and no
## kind discriminator.
var request_id: int = 0

## The entity claiming the relic — whose core the chosen mods will land on.
var collector: Entity = null

## The M drawn node-mod candidates offered for the choice. The emitter only
## routes here when there are at least 2 — one survivor is auto-granted rather
## than presented as a choice of one.
var candidates: Array[StatModifier] = []

## Set SYNCHRONOUSLY by a consumer that takes over the pick (the player
## picker). Left `UNCLAIMED` by everyone else → emitter auto-resolves.
var claim: Claim = Claim.UNCLAIMED

## Emitted once, from [method resolve], BEFORE the resolver callback. The
## `await`-able face of the same event: [SkillDustAddon] runs a round inside a
## [LootRoundCommand]'s application and parks on this, which is what makes the
## applier stay `is_applying` for the whole pick — and therefore what makes
## "no ending the turn while picking" fall out of the existing
## `can_player_act` gate instead of needing a gate of its own (#522).
signal settled(chosen: Array)

var _resolver: Callable
var _resolved: bool = false


func _init(collector_: Entity, candidates_: Array[StatModifier], resolver: Callable) -> void:
	collector = collector_
	candidates = candidates_
	_resolver = resolver


## Grant the chosen modifier. Takes an Array rather than a single [StatModifier]
## because an empty one means "forfeited this round" — the resolver's own
## documented branch. Idempotent: a second call is a no-op, so a picker that
## fires on both "confirm" and a "closed" fallback can't double-grant.
func resolve(chosen: Array[StatModifier]) -> void:
	if _resolved:
		return
	_resolved = true
	settled.emit(chosen)
	if _resolver.is_valid():
		_resolver.call(chosen)


func is_resolved() -> bool:
	return _resolved
