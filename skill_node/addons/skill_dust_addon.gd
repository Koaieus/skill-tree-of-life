@tool
class_name SkillDustAddon
extends SkillNodeAddon

## "SkillDust" — the loot a dying entity leaves on its former core node (#69).
## Carries a snapshot of stat modifiers drawn from the dead entity (core-class
## identity + a random sample of its node-granted mods — see [LootSystem]). On
## death the carrier core is neutralised (force-dealloc'd to unowned), so the
## dust sits on a claimable relic.
##
## When ANY entity allocates that relic node, the dust pours its loot onto the
## ALLOCATOR'S CORE — STEAL semantics (permanent, portable core modifiers), not
## onto the relic node itself. The pool is a weighted union of three provenance
## buckets drawn by [LootSystem] (#323 re-cut) — node grants, class/register
## grants, board innates. Offered as N ROUNDS of pick-1-of-3 (#323): each round
## filters the REMAINING pool by `would_cycle` against the collector's LIVE
## board and grants the pick immediately, so a cycle a candidate would close is
## checked against board state that already reflects every earlier round's
## grant — not just the state at draw time. The player picks via the HUD loot
## picker; NPCs auto-pick at random, per round.
## STEAL/PROLIFERATE choice and staining stay deferred (see loot-system.md).
##
## ON THE WIRE (#522, split #646): the offer/pick/roll sequence for each round
## runs entirely OUTSIDE the command pipeline — see [method _run_round]. Only
## once a round's outcome is fully known does the authority mint a
## [LootRoundCommand] with that outcome ALREADY STAMPED and submit it; applying
## one is therefore always a REPLAY, on every peer including the authority
## itself (see [method _land_outcome], which is also where the grant actually
## lands — never at resolve time, or the authority would double-grant: once
## while resolving, again while applying its own command). The ROUND rather
## than the PICK is the wire unit because two of the grant paths below (the
## single-survivor auto-grant, the NPC auto-resolve) never raise a request at
## all. This addon is therefore HOST-GATED at `_on_carrier_owner_changed`:
## `owned_by` flips on every peer that applies the allocation, and only the
## authority may open a chain. A null [member command_applier] means "no
## pipeline" (headless, editor, authored sandbox relic) and self-replays the
## instant an outcome is known — see [method _settle_outcome].
##
## A downward [LootPickOffer] (also #646, NOT a [Command]) tells a REMOTE
## collector's peer to open its own picker; see that class and
## [signal LootPickRegistry.offer_parked].
##
## TERMINAL SPELL ROUND (#204 re-cut): once every stat round has resolved,
## [member spell_candidates] (if non-empty) offers ONE MORE pick — a spell the
## victim knew, filtered against the collector's PERMANENTLY known spells —
## before the relic frees itself. Deliberately the LAST thing this relic
## offers, never concurrent with a stat round: it used to fire synchronously
## on kill via a standalone `Events.spell_loot_requested` emit in LootSystem,
## which queued it in front of the player's HUD BEFORE they'd even seen (let
## alone claimed) the relic it was conceptually part of. Folding it into this
## addon's own round sequencer, as the round after the last stat round, is
## what makes "on pick, after the regular picks" true by construction instead
## of by call-order coincidence.
##
## Visual (#168): scene-composed (skill_dust_addon.tscn) with a child InnerDisk
## instance, per .claude/rules/scene-composition.md — the gold/mix knobs below
## are only actually inspector-tunable because they live on a scene, not a
## script that's always bare `.new()`'d. The disk's authored
## `carve_shape = GemCarveShape.SHARED` (see inner_disk.gd) etches the loot gem
## cut; this script forces `allocated = true` on it — the "hijack the
## allocation-state render" option from #168, scoped to this addon's OWN disk
## instance so nothing needs to be faked on the carrier
## SkillNode/AllocationSystem. LootSystem falls back to `SkillDustAddon.new()`
## when no scene is configured (see `skill_dust_scene` on LootSystem) — that
## bare fallback has no InnerDisk child, so it's intentionally visual-lite
## (sparkles only), not a bug.

## The full drawn candidate pool (#323: all three provenance buckets, unfiltered
## by `would_cycle` — that check happens per round at claim time, not here,
## since the claimant isn't known at draw time). Shrinks as rounds grant picks
## off it. Already `duplicate(true)`d by LootSystem (independent copies —
## formula-mod binding-state safety, see the stats rule).
@export var candidates: Array[StatModifier] = []

## Bucket weight, index-aligned with [member candidates] — which provenance
## bucket each candidate came from, expressed as its draw weight. Used for the
## weighted "roll a bucket, then a member" sample each round (#323).
@export var weights: Array[float] = []

## How many pick-1-of-3 ROUNDS the collector gets (#323; used to mean "N of a
## flat M" pre-re-cut). Each round offers up to 3 cycle-safe survivors of the
## REMAINING pool; a round with 0 or 1 survivor has no real choice and
## auto-grants/skips without popping the picker.
##
## Named `pick_count` until 2026-08-22, which collided with
## `LootPickRequest.pick_count` — the same name for "how many rounds" and "how
## many picks per round" is what kept turning "pick 1 out of M, N times" into
## "pick N of M" in write-ups. The per-round one is gone; this is the only
## count, and it counts rounds.
@export var rounds: int = 0

## The victim's full spellbook snapshot (#204 re-cut) — every spell known at
## `entity_dying`, core/innate/territory alike, UNFILTERED (the permanent-known
## exclusion is a claim-time concern, same reasoning as `would_cycle` above:
## the claimant isn't known at death). Consumed as ONE terminal bonus round
## after every stat round resolves — see [method run_round]. Empty when
## the victim had no spellbook or LootSystem's spell kill-switch is off.
@export var spell_candidates: Array[SpellDef] = []

## Offer is capped at this many spell candidates (M = min(this, remaining)).
const _SPELL_OFFER_CAP: int = 3

## The entity currently claiming this relic, latched for the duration of the
## multi-round claim flow — one [LootRoundCommand] per round, each opening the
## next from its own application, across possibly-async picker confirms).
var _collector: Entity = null
## Rounds left to run — counts down from [member rounds].
var _rounds_remaining: int = 0

## The dying entity's color, injected by LootSystem before this addon enters
## the tree (same timing as `payload`) — mixed into the gold tint below so a
## relic visibly carries whose corpse it came from.
@export var victim_color: Color = Color.WHITE:
	set(value):
		victim_color = value
		_sync_gold_tint()

## Base loot color and how much of `victim_color` tinges it — both exported so
## a scene author can dial the look without touching script (#168).
@export var gold_color: Color = Color(0.95, 0.78, 0.25, 1.0):
	set(value):
		gold_color = value
		_sync_gold_tint()
@export_range(0.0, 1.0, 0.01) var victim_tint_mix: float = 0.3:
	set(value):
		victim_tint_mix = value
		_sync_gold_tint()

## VALUE tier (#392) — gold glistening, not a hand-picked float. Twinkle
## amplitude still rides alpha below, which is the sanctioned use: an
## animated reveal, not a static dimmer.
static var _SPARKLE_COLOR: Color = Emissive.at(Color(1.0, 0.95, 0.75), Emissive.VALUE)
const _SPARKLE_COUNT := 10

## Null when this addon was `.new()`'d directly instead of instanced from
## skill_dust_addon.tscn (LootSystem's headless/no-scene fallback) — every
## use below is null-guarded, so that path just skips the gold diamond disk
## and keeps the sparkle-only look.
## Deliberately untyped: statically typing this as Node2D would make GDScript
## complain about the InnerDisk-specific properties set below (disk_radius,
## carve_shape, entity_tint, ...) — node_visuals_composite.gd sidesteps the
## same issue by reading its InnerDisk child through the `%InnerDisk` unique-
## name accessor, which Godot resolves to the attached script's type; a plain
## get_node_or_null() return is statically just Node, so this stays Variant.
@onready var _inner_disk = get_node_or_null("InnerDisk")

var _radius: float = 32.0
var _t: float = 0.0


func _ready() -> void:
	super._ready()
	if carrier != null:
		_radius = carrier.radius
		# Pickup == the carrier gaining an owner. owner_changed ALSO fires on the
		# death-strip (victim → null); _on_carrier_owner_changed guards that case.
		if not carrier.owner_changed.is_connected(_on_carrier_owner_changed):
			carrier.owner_changed.connect(_on_carrier_owner_changed)
	if _inner_disk != null:
		_inner_disk.carve_shape = GemCarveShape.SHARED
		_inner_disk.allocated = true
		_inner_disk.configure(_radius)
	_sync_gold_tint()
	set_process(not Engine.is_editor_hint())
	queue_redraw()


func configure_visual(r: float) -> void:
	_radius = r
	if _inner_disk != null:
		_inner_disk.configure(r)
	queue_redraw()


func _sync_gold_tint() -> void:
	if _inner_disk == null:
		return
	_inner_disk.entity_tint = gold_color.lerp(victim_color, victim_tint_mix)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ─── Tooltip contract (SkillNodeAddon) ─────────────────────────────────────

func get_tooltip_title() -> String:
	return "SkillDust loot"


func get_tooltip_modifiers() -> Array[StatModifier]:
	return candidates


# ─── Central-emblem contract (docs/domain/skillnode-emblem.md) ────────────

## LOOT-priority carve — a consumed one-off, so it outranks a spell grant until
## allocation consumes the relic (see the class doc above). The carve's actual
## look is the gem-cut height-field dent InnerDisk already bakes from a
## [GemCarveShape] (#168) — handing [GemCarveShape] over is what routes a LOOT
## carve to that renderer. There is nothing to author on that shape (it takes
## no per-instance parameters), so this rides its shared instance rather than
## minting an identical Resource per relic.
const EMBLEM_SPEC = preload("res://skill_node/visuals/emblem/emblem_spec.gd")

func get_emblem() -> Variant:
	return GemCarveShape.SHARED.carve(EMBLEM_SPEC.Priority.LOOT, &"loot")


## Which kind of round the chain is on. Authority-side only — a peer never
## walks this, it replays whatever arrives.
enum Phase {
	STAT,      ## Pick-1-of-3 stat rounds, [member rounds] of them.
	SPELL,     ## The terminal spell draft (#204).
	TERMINAL,  ## Nothing left to offer; free the relic.
}

var _phase: Phase = Phase.STAT

## Injected by [LootSystem] at drop time (DI, not a lookup — the addon is
## created there). Null on every path that has no command pipeline at all: a
## headless fixture, the editor, the dev addon gallery, an authored relic in a
## sandbox scene. That null is a supported configuration, not a degraded one —
## the round then runs INLINE, exactly as it did before #522, which is the same
## "no applier, apply straight" fallback [method BattleSystem.launch_attack]
## uses and is why the existing loot suite needs no applier to stay green.
var command_applier: CommandApplier = null

## Injected by [LootSystem] alongside [member command_applier]. Only consulted
## for a REMOTE collector, which nothing produces today — see
## [LootPickRegistry]'s dormancy note.
var pick_registry: LootPickRegistry = null


## Pickup == the carrier gaining an owner. Latches the collector and opens the
## claim flow (#323) — see [method run_round].
##
## [b]Host-gated (#522).[/b] A peer applies the confirmed [AllocateCommand] into
## its own world, which flips `owned_by` and fires this locally — so without the
## gate the peer would open its OWN round and roll its OWN offer, in parallel
## with the host's and agreeing with it only by luck. The peer's copy of this
## relic is driven purely by the [LootRoundCommand]s that arrive. Same shape as
## `ed11d03`'s host-guard inside [NodeCombat].
##
## A forced deallocation cannot open a round: the `collector == null` early
## return covers it, and a cascade strips to neutral rather than transferring
## ownership — so no loot round ever opens inside a [LaunchAttackCommand]'s
## application.
func _on_carrier_owner_changed() -> void:
	if Engine.is_editor_hint() or carrier == null:
		return
	var collector := carrier.owned_by
	if collector == null:
		return  # death-strip / deallocation — not a pickup
	if command_applier != null and not command_applier.is_authority:
		return  # a peer: its rounds arrive as replays
	_collector = collector
	_rounds_remaining = rounds
	_phase = Phase.STAT
	if command_applier != null:
		command_applier.notify_loot_round_opened()
	_run_round()  # fired, not awaited — see _land_outcome's doc


## The [CommandApplier]'s entry point, and the one place a WIRE loot round
## mutates the world. Always a REPLAY (#646 — see the class doc): by
## construction a [LootRoundCommand] never exists before its outcome does.
## [param collector] is the command's `entity_id` resolved by the applier, so a
## replay grants to the same entity the authority did; legitimately null on a
## terminal round. Decodes the command's payload and hands off to
## [method _land_outcome] — the same landing [method _settle_outcome] uses for
## the no-applier path, so there is exactly one place that grants + frees +
## continues, not two.
func run_round(command: LootRoundCommand, collector: Entity = null) -> bool:
	_land_outcome(command.granted_modifier(), command.granted_spell(),
			command.is_final(), collector)
	return true


## Grant [param granted] / [param spell], free the relic if [param finished],
## and — only on the authority, and only once the grant above has actually
## landed — start resolving the NEXT round. Runs on EVERY peer including the
## authority when reached via [method run_round], which is what makes the
## grant itself safe here: it happens exactly once, at apply time, never twice
## (see the class doc's double-grant note). The no-applier path
## ([method _settle_outcome]) reaches this directly with the exact objects the
## round just picked — no wire round trip, so a headless/editor claim keeps
## granting the SAME [StatModifier] instance it drew, unchanged from pre-#646.
##
## [b]The continuation is fired, never awaited.[/b] [method _run_round] can
## await a human pick, sometimes across a real round trip — awaiting it here
## would hold [member CommandApplier.is_applying] for the whole remaining
## chain again, exactly the queue-blocking this split exists to avoid (issue
## #646 acceptance 3). [CommandApplier] already documents queuing a command
## raised from inside another command's application as by-design, not
## re-entrancy; this is the same shape one level removed — the SUBMIT that
## follows resolution is what re-enters the queue, not this call.
##
## The peer's [member candidates] pool is never trimmed (only the authority's
## resolve path does that), so its tooltip keeps listing an already-granted
## candidate for the seconds the claim takes. Cosmetic and deliberate: trimming
## would need to match a by-value modifier against a by-instance pool, and the
## pool is freed at `finished` anyway.
func _land_outcome(granted: StatModifier, spell: SpellDef, finished: bool,
		collector: Entity) -> void:
	if collector == null and carrier != null:
		collector = carrier.owned_by  # inline path: no applier resolved one for us
	if is_instance_valid(collector) and not collector.is_dead:
		if granted != null:
			_grant_mod(collector, granted)
		if spell != null:
			_grant_spell(collector, spell)
	if finished:
		# Symmetric with the ONE open call in `_on_carrier_owner_changed`, which
		# is authority-gated the same way — a MIRROR peer's applier never
		# opened, so it must not close either, or the counter underflows.
		if command_applier != null and command_applier.is_authority:
			command_applier.notify_loot_round_closed()
		_really_finish()
		return
	if command_applier == null or command_applier.is_authority:
		_run_round()  # fired, not awaited — see the doc above


## Authority side (and the no-applier inline path, which is authority by
## construction): run whichever round the chain is on next, all the way to a
## settled outcome — the offer, the `would_cycle` filter, the weighted sample,
## and the pick itself if one is needed. NEVER grants; see the class doc for
## why the grant lives only in [method _land_outcome]. Ends in
## [method _settle_outcome], which is what actually mints/submits (or
## self-replays) the round's [LootRoundCommand].
func _run_round() -> void:
	match _phase:
		Phase.STAT:
			@warning_ignore("redundant_await")
			await _run_stat_round()
		Phase.SPELL:
			@warning_ignore("redundant_await")
			await _run_spell_round()
		_:
			_run_terminal_round()


## One stat round (#323). Filters the REMAINING [member candidates] by
## `would_cycle` against the collector's CURRENT board — not the board as it
## stood at draw time, so a grant from an EARLIER round in this same relic is
## already reflected. This is what structurally closes the joint-cycle gap a
## single up-front filter would leave open (two candidates each individually
## safe but jointly cyclic): by the time the second is considered, the first is
## already bound and `would_cycle` sees it.
##
##   * no cycle-safe survivor left → the stat phase is over.
##   * exactly one survivor → no real choice, auto-grant it, don't pop a picker.
##   * 2-3 survivors → weighted-sample up to 3 and offer a real pick-1 choice.
func _run_stat_round() -> void:
	if not is_instance_valid(_collector) or _collector.is_dead \
			or _rounds_remaining <= 0 or candidates.is_empty():
		_enter_spell_phase()
		return

	var board := _collector.stat_board
	var safe_indices: Array[int] = []
	for i in candidates.size():
		if board == null or not board.would_cycle(candidates[i]):
			safe_indices.append(i)
	if safe_indices.is_empty():
		_enter_spell_phase()
		return

	var offer_indices := _weighted_sample(safe_indices, mini(3, safe_indices.size()))
	if offer_indices.is_empty():
		_enter_spell_phase()
		return
	if offer_indices.size() == 1:
		_settle_stat_round(candidates[offer_indices[0]])
		return

	var offer: Array[StatModifier] = []
	for i in offer_indices:
		offer.append(candidates[i])

	var request := LootPickRequest.new(_collector, offer, Callable())
	Events.loot_pick_requested.emit(request)
	@warning_ignore("redundant_await")
	var chosen: Array = await _await_pick(request, offer)
	_settle_stat_round(chosen[0] if not chosen.is_empty() else null)


## Remove the pick from [member candidates] so it can't be re-offered (the
## NEXT round's `would_cycle` check sees the grant once [method _land_outcome]
## actually lands it, not here — resolving never grants, see the class doc),
## and settle this round's outcome. The other 2 un-picked offer members are NOT
## removed — they stay eligible for a later round's fresh 3-sample ("single
## pick, then new draw, the next pick is always clean", per the #322 comment
## thread this shape came from). A null `chosen` (a forfeited round, or a
## collector who died mid-pick) records no grant rather than stalling the
## relic.
func _settle_stat_round(chosen: StatModifier) -> void:
	if not (is_instance_valid(_collector) and not _collector.is_dead):
		chosen = null
	if chosen != null:
		var idx := candidates.find(chosen)
		if idx != -1:
			candidates.remove_at(idx)
			weights.remove_at(idx)
	_rounds_remaining -= 1
	_settle_outcome(chosen, null, false)


## Every stat round has resolved (or there were none to run) — move to the
## terminal spell round. No command to reuse any more (#646) — a phase
## transition is bookkeeping a peer never sees either way, now simply because
## nothing is minted until an outcome exists.
func _enter_spell_phase() -> void:
	candidates = []
	weights = []
	_phase = Phase.SPELL
	@warning_ignore("redundant_await")
	await _run_spell_round()


## The terminal bonus round (#204 re-cut). Guarded the same way a stat round is
## — `_collector` can already be invalid here, and reading `_collector.spellbook`
## on a freed Object crashes at the typed assignment (see gdscript-pitfalls.md),
## not at a null check.
func _run_spell_round() -> void:
	if spell_candidates.is_empty() or not is_instance_valid(_collector) or _collector.is_dead:
		_enter_terminal_phase()
		return

	var offerable := _exclude_permanently_known(spell_candidates, _collector)
	spell_candidates = []  # single-shot bonus — consumed regardless of outcome
	if offerable.is_empty():
		_enter_terminal_phase()
		return

	offerable.shuffle()
	var offer_count := mini(_SPELL_OFFER_CAP, offerable.size())
	var offer: Array[SpellDef] = offerable.slice(0, offer_count)

	var request := SpellLootRequest.new(_collector, offer, Callable())
	Events.spell_loot_requested.emit(request)
	@warning_ignore("redundant_await")
	var chosen: Array = await _await_pick(request, offer)
	_settle_spell_round(chosen[0] if not chosen.is_empty() else null)


## Spell round resolver: settles the chosen spell's outcome (#204) — the actual
## grant, a [SpellGrant] on the collector's CORE node, only lands once this
## round's [LootRoundCommand] applies (see the class doc). There is no further
## offer after this one.
func _settle_spell_round(chosen: SpellDef) -> void:
	if not (is_instance_valid(_collector) and not _collector.is_dead):
		chosen = null
	_phase = Phase.TERMINAL
	_settle_outcome(null, chosen, false)


func _enter_terminal_phase() -> void:
	_phase = Phase.TERMINAL
	_run_terminal_round()


## Nothing left to offer. The ONE outcome that frees the relic on every peer,
## whichever of the five ways the chain ended got us here.
func _run_terminal_round() -> void:
	_settle_outcome(null, null, true)


## The one place a round's decided outcome becomes a [LootRoundCommand] (#646)
## — the constructor takes the outcome, so by construction there is no way to
## build one before this point. With a pipeline, submit it and let
## [method run_round] land the grant uniformly for every peer, authority
## included (see the class doc). Without one (headless / editor / authored
## sandbox relic — pre-#522 behaviour, unchanged in effect), there is no queue
## to land it on, so self-replay immediately.
## [param spell] is the actual [SpellDef] this round chose, never just its id —
## the no-applier branch below hands it straight to [method _land_outcome]
## unchanged, so a headless/editor claim keeps granting the SAME instance it
## offered (which matters for a test-minted, uncatalogued [SpellDef] just as
## much as it does for a [StatModifier]; see [method _land_outcome]'s doc).
## Only the WIRE branch narrows it to `spell.id`, because that is the one
## direction where the receiving peer resolves it back through
## [SpellCatalog] — an authored spell has a real identity there, unlike a
## runtime-minted [StatModifier].
func _settle_outcome(granted: StatModifier, spell: SpellDef, finished: bool) -> void:
	if command_applier == null:
		_land_outcome(granted, spell, finished, _collector)
		return
	var collector_id := _collector.entity_id if is_instance_valid(_collector) else 0
	var carrier_id := 0
	if command_applier.graph != null:
		carrier_id = command_applier.graph.get_stable_id(carrier)
	var spell_id := spell.id if spell != null else &""
	command_applier.submit(LootRoundCommand.new(collector_id, carrier_id, granted, spell_id, finished))


## Park on the pick, whoever is making it. THE HANDSHAKE (see [LootPickRequest]):
## a HUD that intends to present the choice claims it SYNCHRONOUSLY, inside the
## emit above — so by the time we get here `claim` already says who is picking.
##
##   * `LOCAL` — a picker on this machine is up; await its confirm.
##   * `REMOTE` — a human on another peer owes the answer; park it in the
##     registry so the returning [PickLootCommand] can land, and await that.
##     [method LootPickRegistry.park] is also what fires the downward
##     [LootPickOffer] ([CommandLink] listens for
##     [signal LootPickRegistry.offer_parked]) that tells the remote peer's HUD
##     to open a picker at all. `is_remote_collector` still returns false today
##     (#646 note in [LootPickRegistry]'s class doc), so this branch is wired
##     but unreached in real play until that lands.
##   * `UNCLAIMED` — NPC / headless / no HUD. Auto-resolve a random 1 of the
##     offer. This stays a HOST-ONLY roll and is exempt from the seeding rule
##     per `.claude/rules/multiplayer-sync.md`: the peer receives the result, it
##     does not reproduce it.
##
## [b]Owner call 2026-08-27: a collector that dies while this await is parked
## forfeits the round[/b], rather than leaving it stuck forever. This used to
## be unreachable — the whole chain ran inside [member CommandApplier.is_applying],
## so nothing else could act to kill the collector — but #646 moves the
## offer/pick/roll sequence outside the queue between rounds specifically so a
## remote pick no longer holds it, which is what makes this reachable now.
## [method LootPickRegistry.forfeit_for] already existed for a disconnected
## peer and only ever reaches a PARKED (REMOTE) request; resolving [param
## request] directly here covers LOCAL and lingering UNCLAIMED awaits too,
## since this is the one place that sees all three claims uniformly.
func _await_pick(request: Variant, offer: Array) -> Array:
	if request.claim == LootPickRequest.Claim.UNCLAIMED \
			and pick_registry != null and pick_registry.is_remote_collector(_collector):
		request.claim = LootPickRequest.Claim.REMOTE
		pick_registry.park(request)
	if request.claim == LootPickRequest.Claim.UNCLAIMED:
		var pool := offer.duplicate()
		pool.shuffle()
		return [pool[0]]
	if request.is_resolved():
		return []
	var forfeit_on_death := Callable()
	if is_instance_valid(_collector):
		forfeit_on_death = func() -> void:
			if not request.is_resolved():
				request.resolve(_forfeit_like(request))
		_collector.died.connect(forfeit_on_death, CONNECT_ONE_SHOT)
	@warning_ignore("redundant_await")
	var chosen: Array = await request.settled
	if forfeit_on_death.is_valid() and is_instance_valid(_collector) \
			and _collector.died.is_connected(forfeit_on_death):
		_collector.died.disconnect(forfeit_on_death)
	return chosen


## The correctly-typed empty array for whichever request kind [param request]
## is — GDScript has no generics, so this can't be shared with
## [method LootPickRegistry._empty_like] across files.
func _forfeit_like(request: Variant) -> Array:
	if request is SpellLootRequest:
		return [] as Array[SpellDef]
	return [] as Array[StatModifier]


func _really_finish() -> void:
	queue_free()


## Grant one spell onto [param collector]'s core — a [SpellGrant], the same
## mechanism as an authored or earned core spell. Shared by the authority's own
## round and by a peer's replay, so the two cannot drift.
func _grant_spell(collector: Entity, spell: SpellDef) -> void:
	if spell == null or collector.core_location == null:
		return
	var grant := SpellGrant.new()
	grant.spell_def = spell
	collector.core_location.add_effect(grant)      # persist on the node, resync the emblem
	collector.grant_effect(grant, collector.core_location) # -> book.add_spell(spell, core_node)


## Territory-known (temporary) spells stay offerable as an upgrade — only
## PERMANENTLY-known spells are excluded, so the offer is a genuine addition.
func _exclude_permanently_known(cands: Array[SpellDef], collector: Entity) -> Array[SpellDef]:
	if collector.spellbook == null or collector.core_location == null:
		return cands
	var known := collector.spellbook.permanent_spells(collector.core_location)
	var out: Array[SpellDef] = []
	for s in cands:
		if not known.has(s):
			out.append(s)
	return out


## Weighted sample WITHOUT replacement, `count` indices out of `pool_indices`
## (each weighted by [member weights]) — "roll a bucket by weight, then a
## member", per the #323 RE-CUT comment. `maxf(w, 0.0001)` keeps a zero-weight
## bucket sampleable (excluded, not erased) rather than a divide-by-zero.
func _weighted_sample(pool_indices: Array[int], count: int) -> Array[int]:
	var remaining := pool_indices.duplicate()
	var out: Array[int] = []
	for _i in count:
		if remaining.is_empty():
			break
		var total := 0.0
		for idx in remaining:
			total += maxf(weights[idx], 0.0001)
		var roll := randf() * total
		var chosen_pos := remaining.size() - 1
		var acc := 0.0
		for pos in remaining.size():
			acc += maxf(weights[remaining[pos]], 0.0001)
			if roll <= acc:
				chosen_pos = pos
				break
		out.append(remaining[chosen_pos])
		remaining.remove_at(chosen_pos)
	return out


## Pour ONE mod onto the collector. Routes through [method
## Entity.grant_core_modifier] (#323) rather than a raw `stat_board.add_modifier`
## — a looted grant re-enters the collector's [member Entity.core_modifiers]
## register exactly like a class grant, which is the only thing that makes a
## `loots_as_unit` pack survive ANOTHER loot round-trip if this collector later
## dies (closes #185's re-lootability gap via the register).
func _grant_mod(collector: Entity, m: StatModifier) -> void:
	if collector.core_location == null:
		return
	collector.grant_core_modifier(m)
	# #70: emit per LEAF — honest about each stat gained. A bundle's buff and
	# debuff are separate floaters; either alone may be no "mythic" at all.
	for leaf in m.flatten():
		Events.stat_modifier_changed.emit(collector, leaf, ModifierBinding.Kind.CORE, true)


## Shimmering sparkle ring (#168) — richer than the old static 8-dot draw:
## each dot twinkles on its own phase offset so the ring reads as animated
## glimmer rather than fixed decoration. Addon-owned rather than a
## SkillNodeVisual family member — this FX is relic-specific, not a reusable
## node-visual component.
func _draw() -> void:
	if _radius <= 0.0:
		return
	var step := TAU / float(_SPARKLE_COUNT)
	for i in _SPARKLE_COUNT:
		var theta := i * step + float(i % 2) * step * 0.5
		var dist := _radius * (0.55 + 0.12 * float(i % 3))
		var p := Vector2.from_angle(theta) * dist
		var phase := _t * 1.6 + float(i) * 1.7
		var twinkle := 0.5 + 0.5 * sin(phase)
		var c := _SPARKLE_COLOR
		c.a = _SPARKLE_COLOR.a * (0.35 + 0.65 * twinkle)
		draw_circle(p, _radius * (0.035 + 0.04 * twinkle), c)
