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
## ROUNDS ARE DRIVEN FROM OUTSIDE (#1138). This addon is a node addon: it holds
## the draw, answers "what do you offer now" ([method offers_for]) and lands a
## decided outcome ([method grant_mod], [method grant_spell], [method finish]).
## It announces a pickup with [signal claimed] and nothing more. The round loop
## — phase sequencing, the human pick, minting the wire round (#522/#646) and
## the host gate — lives with the command-side loot round controller, which
## [LootSystem] connects to [signal claimed]. See docs/domain/loot-system.md.
##
## TERMINAL SPELL ROUND (#204 re-cut): once every stat round has resolved,
## [member spell_candidates] (if non-empty) offers ONE MORE pick — a spell the
## victim knew, filtered against the collector's PERMANENTLY known spells —
## before the relic frees itself. Deliberately the LAST thing this relic
## offers, never concurrent with a stat round: it used to fire synchronously
## on kill via a standalone `Events.spell_loot_requested` emit in LootSystem,
## which queued it in front of the player's HUD BEFORE they'd even seen (let
## alone claimed) the relic it was conceptually part of. Folding it into this
## relic's own phase order ([enum Phase]), as the round after the last stat round, is
## what makes "on pick, after the regular picks" true by construction instead
## of by call-order coincidence.
##
## Visual (#168): scene-composed (defs/skill_dust_addon.tscn) with a child
## InnerDisk instance, per .claude/rules/scene-composition.md — the gold/mix
## knobs below are only actually inspector-tunable because they live on a
## scene, not a script that's always bare `.new()`'d. The disk's authored
## `carve_shape = GemCarveShape.SHARED` (see inner_disk.gd) etches the loot gem
## cut; this script forces `allocated = true` on it — the "hijack the
## allocation-state render" option from #168, scoped to this addon's OWN disk
## instance so nothing needs to be faked on the carrier
## SkillNode/AllocationSystem. `skill_dust_scene` on LootSystem is required
## (#1292) — there is no bare-script fallback; an unset scene skips the drop
## instead of minting a script-only addon.

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
## the pick request's own `pick_count` — the same name for "how many rounds" and "how
## many picks per round" is what kept turning "pick 1 out of M, N times" into
## "pick N of M" in write-ups. The per-round one is gone; this is the only
## count, and it counts rounds.
@export var rounds: int = 0

## The victim's full spellbook snapshot (#204 re-cut) — every spell known at
## `entity_dying`, core/innate/territory alike, UNFILTERED (the permanent-known
## exclusion is a claim-time concern, same reasoning as `would_cycle` above:
## the claimant isn't known at death). Consumed as ONE terminal bonus round
## after every stat round resolves — see [method offers_for]. Empty when
## the victim had no spellbook or LootSystem's spell kill-switch is off.
@export var spell_candidates: Array[SpellDef] = []

## Offer is capped at this many spell candidates (M = min(this, remaining)).
const _SPELL_OFFER_CAP: int = 3


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


## Which kind of round the claim is on. Authority-side only — a peer never
## walks this, it replays whatever arrives.
enum Phase {
	STAT,      ## Pick-1-of-3 stat rounds, [member rounds] of them.
	SPELL,     ## The terminal spell draft (#204).
	TERMINAL,  ## Nothing left to offer; free the relic.
}

## The carrier gained an owner — someone is picking this relic up. The addon
## only announces it; whoever drives claims ([LootSystem], through
## the loot round controller) decides whether THIS machine opens the rounds.
signal claimed(collector: Entity)

## Claim state, latched by [method begin_claim] and walked by the round
## controller across possibly-async picks. Only
## ever set on the machine that drives the claim; a replaying peer leaves it
## untouched.
var claim_collector: Entity = null
## Stat rounds left to offer — counts down from [member rounds].
var rounds_remaining: int = 0
var phase: Phase = Phase.STAT


## Pickup == the carrier gaining an owner. A death-strip or deallocation
## (owner -> null) is not a pickup. Emitted on every peer that applies the
## allocation; the host gate lives with the listener, not here.
func _on_carrier_owner_changed() -> void:
	if Engine.is_editor_hint() or carrier == null:
		return
	var collector := carrier.owned_by
	if collector == null:
		return
	claimed.emit(collector)


## Latch [param collector] as the claimant and rewind to the first stat round.
func begin_claim(collector: Entity, rounds_count: int = rounds) -> void:
	claim_collector = collector
	rounds_remaining = rounds_count
	phase = Phase.STAT


## Is the latched claimant still able to receive a grant?
func has_live_claimant() -> bool:
	return is_instance_valid(claim_collector) and not claim_collector.is_dead


## What this relic offers the claimant in [param for_phase], right now. Empty
## means the phase has nothing left to offer.
##
##   * [constant Phase.STAT] — filters the REMAINING [member candidates] by
##     `would_cycle` against the claimant's CURRENT board (not the board at
##     draw time: an earlier round's grant is already bound, which is what
##     closes the joint-cycle gap a single up-front filter would leave), then
##     weighted-samples up to 3. One survivor means no real choice — the
##     controller auto-grants it without a picker.
##   * [constant Phase.SPELL] — the victim's spells minus the claimant's
##     PERMANENTLY known ones, shuffled and capped. Single-shot: consumes
##     [member spell_candidates] whatever the outcome.
func offers_for(for_phase: Phase) -> Array:
	if not has_live_claimant():
		return []
	match for_phase:
		Phase.STAT:
			return _stat_offer()
		Phase.SPELL:
			return _spell_offer()
	return []


func _stat_offer() -> Array[StatModifier]:
	var offer: Array[StatModifier] = []
	if rounds_remaining <= 0 or candidates.is_empty():
		return offer
	var board := claim_collector.stat_board
	var safe_indices: Array[int] = []
	for i in candidates.size():
		if board == null or not board.would_cycle(candidates[i]):
			safe_indices.append(i)
	for i in _weighted_sample(safe_indices, mini(3, safe_indices.size())):
		offer.append(candidates[i])
	return offer


func _spell_offer() -> Array[SpellDef]:
	if spell_candidates.is_empty():
		return [] as Array[SpellDef]
	var offerable := _exclude_permanently_known(spell_candidates, claim_collector)
	spell_candidates = []
	offerable.shuffle()
	return offerable.slice(0, mini(_SPELL_OFFER_CAP, offerable.size()))


## Take a picked stat off the pool so it cannot be re-offered, and count the
## round. The un-picked offer members stay eligible for a later round's fresh
## sample ("single pick, then new draw", #322). A null [param chosen] (forfeit,
## dead claimant) still counts the round rather than stalling the relic.
func consume_stat_round(chosen: StatModifier) -> void:
	if chosen != null:
		var idx := candidates.find(chosen)
		if idx != -1:
			candidates.remove_at(idx)
			weights.remove_at(idx)
	rounds_remaining -= 1


## Every stat round has resolved (or none could run): drop the pool and move
## to the spell round.
func end_stat_phase() -> void:
	candidates = []
	weights = []
	phase = Phase.SPELL


## The relic has nothing left to give; it frees itself on every peer.
func finish() -> void:
	queue_free()


## Grant one spell onto [param collector]'s core — a [SpellGrant], the same
## mechanism as an authored or earned core spell. Shared by the authority's own
## round and by a peer's replay, so the two cannot drift.
func grant_spell(collector: Entity, spell: SpellDef) -> void:
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
## Entity.absorb_core_modifier] (#775) rather than a raw `stat_board.add_modifier`
## — an equivalent existing grant (same stat/op/formula) adds coefficients
## instead of holding another copy; a genuinely new one still lands in
## [member Entity.core_modifiers] exactly like a class grant, which is what
## makes a `loots_as_unit` pack survive ANOTHER loot round-trip if this
## collector later dies (closes #185's re-lootability gap via the register).
## The `stat_modifier_changed` emit (#70: per-leaf on append, the merged
## target on a merge) lives on that method now, not here.
func grant_mod(collector: Entity, m: StatModifier) -> void:
	if collector.core_location == null:
		return
	collector.absorb_core_modifier(m)


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
