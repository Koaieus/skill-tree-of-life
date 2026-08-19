@tool
class_name LootSystem
extends Node

## Authority for killing-blow rewards (#68 XP, #69/#173 SkillDust loot,
## #204 spellbook draft). Reacts to `Events.entity_dying(victim)` — the
## PRE-cleanup phase, while the corpse still owns its nodes (so the XP payout
## can count the territory held at death, and the spell draft can still
## read core-sourced spells before the strip). The phase split guarantees this
## runs before AllocationSystem's `entity_died` strip; no tree-order /
## connection-order dependency. On the bus:
##   * XP reward — the killer gains XP for every node this attack took off the
##     victim, the core included, fed through the normal `xp` pool so it converts
##     to SP / levels via the existing replenished cascade
##     (Entity._on_xp_replenished). Don't bypass the pool — a raw `set_current`
##     would skip the level-up. The complementary per-node trickle rides
##     BattleSystem's `cascade_started` instead of this phase.
##   * SkillDust drop (#323 re-cut) — a weighted draw over THREE provenance
##     buckets (node grants on the victim's owned subgraph, class/register
##     grants, board innates) is attached to the victim's former core node as a
##     [SkillDustAddon]. The underlying node modifiers still return to the
##     graph on the death strip — only a duplicated COPY enters the loot pool.
##     Offered as N rounds of pick-1-of-3, `would_cycle`-filtered per round
##     against the collector's live board at claim time (not draw time — the
##     claimant isn't known until someone allocates the relic). See
##     docs/domain/loot-system.md.
##   * Spell draft (#204, re-cut #4xx) — every spell the victim currently knows
##     (core, innate, AND territory-sourced) is snapshotted onto the SAME
##     [SkillDustAddon] relic as a terminal BONUS round, offered AFTER every
##     stat round has resolved. The offer is filtered against whoever actually
##     CLAIMS the relic (allocates the node) — not the killer — minus spells
##     that claimant already knows permanently; the chosen spell lands on the
##     claimant's core via a [SpellGrant]. See the "#204: Spellbook loot draft"
##     section below.
##
## KILLER ATTRIBUTION lives here, not on the entity or the bus: death fires
## SYNCHRONOUSLY inside the attacker's turn (core-HP overflow + cascade chip
## damage both run in the attacker's `launch_attack` call stack), so
## `turn_manager.current_entity` at death IS the killer. Resolving it in the
## rewards authority keeps Entity dumb and keeps reward logic out of BattleSystem
## (which owns attacks, not rewards). Thorns / counter-damage would kill on the
## defender's turn — when those land this needs real source-threading.

## Injected so this system can attribute the killing blow. DI per the
## scene-composition rule (NodePath @export, wired in game_root.tscn) — the same
## pattern BattleSystem / AllocationSystem use for their TurnManager dependency.
@export var turn_manager: TurnManager

## The attack authority — LootSystem rides its `attack_launched` /
## `cascade_started` signals to keep the per-attack removal ledger (see below).
## Null in headless fixtures that never run a cascade.
@export var battle_system: BattleSystem

## Per-side-effect kill-switches. A sandbox tab (a GameRoot-inherited scene) flips
## these in the inspector to neuter a reward path while keeping 1:1 wiring with
## the real system — ONE declarative guard at the data boundary, not guards
## littered through call sites, and no mock subclass needed for simple on/off.
## (For wholesale behaviour replacement, override the node's `script` to a
## `DevLootSystem extends LootSystem` in the inherited scene instead — same
## NodePaths, swapped logic. See docs/domain/sandbox-framework.md.)
@export var award_xp_on_kill: bool = true
@export var award_xp_on_node_kill: bool = true
@export var drop_skill_dust_on_death: bool = true
@export var award_spell_loot_on_death: bool = true

## ── XP reward (#68, #173, reworked off `level`) ───────────────────────────────
## XP is paid for TERRITORY REMOVED and nothing else. One currency, one axis:
##
##   per node removed    = xp_per_node_killed                    (the trickle)
##   entity killing blow = xp_per_node_killed
##                         * (|removed_this_attack UNION held_at_death| + 1)
##                         * entity_kill_bonus, minus the trickle already paid
##
## The killing blow multiplies EVERY node this attack took off the defender —
## the ones the cascade already stripped (`removed_this_attack`, the ledger),
## the ones still standing when the core popped (`held_at_death`), and the core
## itself. The two sets OVERLAP mid-cascade (the ledger is recorded before the
## strip loop walks it), so they're unioned, not summed — and the union is
## invariant: a node moves from one side to the other as the loop progresses and
## the total doesn't move.
##
## THAT INVARIANCE IS THE POINT. Reading only `held_at_death` made the payout
## depend on *where in BattleSystem's cascade loop* the chip damage happened to
## kill the core — measured at 35 XP vs 15 XP for the identical attack on an
## identical victim, differing only in the defender's starting health. Worse, it
## paid you LESS the more of the victim you had actually destroyed. Same defect
## on the magic path: a fork that killed on hop 2 left later hops landing on an
## already-stripped corpse. The ledger is what makes the payout a function of
## what the player removed rather than of internal loop ordering.
##
## `level` used to be the base term's axis (`xp_per_victim_level * victim.level`)
## and it was a double-count dressed as a second signal: D-19 pins an enemy's
## level to its starting node count, so "level" and "territory" were already the
## same number, and killing a grown empire paid twice for one fact. Node count is
## the honest axis — it's what the player actually fought through — so the level
## term is gone and the territory term is the whole reward.
##
## Why XP and not looted stats: territory modifiers are only LENT by the graph
## (granted on allocation, released back to neutral on death), so copying them
## into loot would duplicate mods still on the battlefield and re-claimable. XP
## is the honest reward for the scale of the kill; the stat loot draws strictly
## from the core (see `_draw_payload`). See #173 discussion.

## XP for removing one node — the whittling trickle (#182). Paid per node the
## attack takes off the board: the node actually depleted AND everything the
## cascade islands off it. Islanded nodes are not "collateral" — they left the
## defender's subgraph because of your hit, and the arm you severed is the thing
## you destroyed.
@export var xp_per_node_killed: float = 5.0

## Multiplier on the entity killing blow, on top of the per-node rate. The kill
## is worth strictly more than dismantling the same territory node by node —
## that premium is what makes going for the throat a real alternative to
## grinding the limbs.
@export var entity_kill_bonus: float = 2.0

## Flat base of the per-kill tier bonus (#300): a kill pays
## `tier_xp_base × victim.entity_tier²` on top of the territory term. With the
## default 10.0 that's +10 / +40 / +90 for a tier 1 / 2 / 3 victim — the axis
## that lets a removable blocker be worth a fixed, size-shaped reward
## (blockers land on 20/50/100 after the territory formula pays its one node).
@export var tier_xp_base: float = 10.0

## ── Core loot draw (#173) ─────────────────────────────────────────────────────
## The SkillDust draw is CORE-ONLY: the victim's class-identity mods plus
## whatever was permanently accreted onto its core (previously-looted mods).
## These are the modifiers that VANISH with the entity — everything on its owned
## nodes merely returns to the graph, so drawing those would duplicate live mods.
## The whole core set is offered as pick-N-from-M candidates (M = core supply);
## N (keep-count) equals the victim's [member Entity.entity_tier] (#300), so a
## higher-tier kill lets you keep more of their identity. When N >= M there's no
## real choice → auto-grant all.
##
##   N = victim.entity_tier, clamp [0, M]

## Optional packed scene for the dust addon (inspector-set). Falls back to a bare
## `SkillDustAddon.new()` when unset — the addon's visual is script-driven, so the
## fallback still renders.
@export var skill_dust_scene: PackedScene = null

## ── Provenance buckets (#323) ─────────────────────────────────────────────────
## The draw is a weighted union of three source-array reads — see [method
## _draw_payload]. All equal by default; numbers unset by design (docs — the
## RE-CUT comment thread on #323), tune in the inspector.
@export var weight_bucket_node: float = 1.0
@export var weight_bucket_class: float = 1.0
@export var weight_bucket_innate: float = 1.0


## ── The attack-scoped removal ledger ─────────────────────────────────────────
## defender → the SET of its nodes the CURRENT attack has removed so far.
## A set, not a count: the cascade set is recorded up front (before the strip
## loop runs), so while the loop is mid-flight a node is simultaneously "in the
## ledger" and "still held". Counting both would double-pay it; the kill payout
## unions the two instead.
## Cleared on every `attack_launched`, so the scope is one attack: a node broken
## in an earlier attack (or an earlier turn) already collected its trickle and
## is not re-counted at bonus rate by a later kill. That's what preserves the
## whittle-vs-snipe distinction — it's now decided by *which attack* removed the
## node, a player-visible and player-controlled fact, instead of by cascade
## iteration order.
##
## Attack-scoped, not turn-scoped: the bonus means "this blow". Deliberately
## plain state on this system rather than a payload on the bus — the ledger is
## transient attack bookkeeping, not a domain fact anyone else should read.
var _removed_this_attack: Dictionary[Entity, Dictionary] = {}


func _ready() -> void:
	Events.entity_dying.connect(_on_entity_dying)
	# The cascade is the only place that knows the full removal set (impact node
	# + everything it islanded) AND the defender it came off — `owned_by` is
	# cleared by the strip that same loop, so the fact has to be read here or not
	# at all. BattleSystem emits this BEFORE the strip; see its `cascade_started`.
	# No warning on a null `battle_system` — the export documents it as a
	# supported headless-fixture configuration (test_spell_loot.gd is one).
	# What that configuration must NOT do is leave the ledger accumulating,
	# which is why `_on_entity_dying` clears per victim rather than relying on
	# `_on_attack_launched` alone.
	if battle_system == null:
		return
	battle_system.attack_launched.connect(_on_attack_launched)
	battle_system.cascade_started.connect(_on_cascade_started)


## Pre-cleanup phase — corpse still owns its nodes (see Events.entity_dying).
func _on_entity_dying(victim: Entity) -> void:
	if victim == null:
		return
	var killer := _resolve_killer(victim)
	_award_kill_xp(victim, killer)
	_drop_skill_dust(victim)
	# Retire this victim's ledger the moment it has been paid out. The other
	# clear (`_on_attack_launched`) is wired only when `battle_system` is set,
	# so an unset export left the ledger to accumulate across attacks while
	# `_award_kill_xp` read it unconditionally — a later kill then counted an
	# earlier attack's territory at the kill-bonus rate. Clearing here makes
	# the read self-consistent no matter how the system is wired.
	#
	# ERASE, not a paid-tombstone, and that is checked rather than assumed: a
	# LATER `cascade_started` for this same victim would rebuild the ledger from
	# {} and re-pay those nodes at 1x on top of the bonus rate. It cannot
	# happen. `BattleSystem._on_node_depleted` emits `cascade_started` at the
	# TOP, before the strip loop that chips health and can kill; and once death
	# has stripped ownership, its own `defender = node.owned_by; if defender ==
	# null: return` guard turns every subsequent depletion for this victim into
	# an early return. So no cascade for a victim can follow its `entity_dying`.
	_removed_this_attack.erase(victim)
	# Still the pre-strip world: the corpse owns its nodes, so an effect can
	# inspect the territory it just took (the Predator's BLITZ will want this).
	if killer != null:
		killer.dispatch(&"_on_killing_blow", [victim])


## The entity holding the turn at the synchronous death is the killer. Guarded
## against the victim itself (non-attack death — self-islanding, scripted) and a
## missing TurnManager (headless tests without one).
func _resolve_killer(victim: Entity) -> Entity:
	if turn_manager == null:
		return null
	var killer := turn_manager.current_entity
	return killer if killer != victim else null


# ── #68: XP reward ───────────────────────────────────────────────────────────

func _award_kill_xp(victim: Entity, killer: Entity) -> void:
	if not award_xp_on_kill:
		return
	if killer == null or killer.is_dead:
		return
	# #384/#386: XP is a payment for a HOSTILE kill only — an ally kill (or the
	# self-kill `_resolve_killer` already excludes) earns nothing.
	if killer.attitude_to(victim) != Entity.Attitude.HOSTILE:
		return
	# Everything this attack took off the victim, whichever side of the cascade
	# it currently sits on, plus the core it died on. `_held_nodes` excludes
	# the core (it answers "territory"), but for the reward the core IS a node the
	# killer had to destroy — and without it a landless enemy (D-19's core-only
	# elite) would be worth a flat zero.
	var removed: Dictionary = _removed_this_attack.get(victim, {})
	# UNION, not sum: mid-cascade, a node sits in both sets (the ledger records
	# the whole cascade before the strip loop walks it). The union is what makes
	# the payout invariant to where in that loop the core happened to die.
	var counted := removed.duplicate()
	for n in _held_nodes(victim):
		counted[n] = true
	var total := xp_per_node_killed * float(counted.size() + 1) * entity_kill_bonus
	# The ledger's nodes already collected their trickle at 1x — pay only the
	# difference, so the kill is worth exactly `total` however the attack was
	# sequenced.
	var already_paid := xp_per_node_killed * float(removed.size()) \
			if award_xp_on_node_kill else 0.0
	# #300: tier bonus — a flat size-shaped reward on top of the territory term,
	# paid once per kill (not per node). Scales quadratically so a large blocker
	# is worth meaningfully more than several small ones, not just linearly more.
	var tier_bonus := tier_xp_base * float(victim.entity_tier * victim.entity_tier)
	_grant_xp(killer, total - already_paid + tier_bonus)


## A fresh attack — the ledger is scoped to one attack, so nothing carries over.
func _on_attack_launched(_mode: int, _spell: SpellDef) -> void:
	_removed_this_attack.clear()


## Per-node removal trickle (#182). `layers` is BattleSystem's BFS-layered
## cascade set — the depleted node plus everything it islanded — emitted BEFORE
## the strip, so the defender is still knowable. Pays the whole set, and records
## it so a kill later in the same attack can upgrade it to the bonus rate
## instead of double-paying or losing it.
func _on_cascade_started(layers: Array, defender: Entity) -> void:
	if defender == null:
		return
	var ledger: Dictionary = _removed_this_attack.get(defender, {})
	var newly := 0
	for layer in layers:
		for n in (layer as Array):
			if n == null or ledger.has(n):
				continue
			ledger[n] = true
			newly += 1
	_removed_this_attack[defender] = ledger
	if newly <= 0 or not award_xp_on_node_kill:
		return
	var killer := _resolve_killer(defender)
	if killer == null or killer.is_dead:
		return
	# #384/#386: same HOSTILE gate as the kill bonus — see `_award_kill_xp`.
	if killer.attitude_to(defender) != Entity.Attitude.HOSTILE:
		return
	_grant_xp(killer, xp_per_node_killed * float(newly))


## Pour `amount` XP onto `entity`'s pool. Always through `replenish` — a raw
## `set_current` would skip `on_pool_filled` and thus the level-up cascade.
func _grant_xp(entity: Entity, amount: float) -> void:
	if amount <= 0.0 or entity == null:
		return
	var board := entity.stat_board
	if board == null or board.xp == null:
		return
	board.xp.replenish(amount)


# ── #69/#173: SkillDust loot drop (core-only) ─────────────────────────────────

## Attaches the SkillDust relic — stat rounds (#173/#323) PLUS, as a terminal
## bonus round, the victim's spell draft (#204). Each side is gated by its own
## kill-switch independently (`drop_skill_dust_on_death` zeroes only the stat
## payload, `award_spell_loot_on_death` zeroes only the spell payload) so the
## addon still attaches — and still offers whichever half is on — when only
## one switch is set. See [SkillDustAddon]'s terminal-round doc for why the
## spell offer/filter/grant happens at CLAIM time instead of here: the
## claimant isn't known until someone allocates the relic.
func _drop_skill_dust(victim: Entity) -> void:
	var core := victim.core_location
	if core == null:
		return
	var empty_draw: Dictionary = {
		"candidates": [] as Array[StatModifier], "weights": [] as Array[float], "pick_count": 0
	}
	var draw := _draw_payload(victim) if drop_skill_dust_on_death else empty_draw
	var candidates: Array[StatModifier] = draw["candidates"]
	var spell_candidates: Array[SpellDef] = []
	if award_spell_loot_on_death:
		spell_candidates = _spell_candidates(victim)
	if candidates.is_empty() and spell_candidates.is_empty():
		return
	var dust: SkillDustAddon = null
	if skill_dust_scene != null:
		dust = skill_dust_scene.instantiate() as SkillDustAddon
	if dust == null:
		dust = SkillDustAddon.new()
	dust.candidates = candidates
	dust.weights = draw["weights"]
	dust.pick_count = draw["pick_count"]
	dust.victim_color = victim.color
	dust.spell_candidates = spell_candidates
	_attach_addon(core, dust)


## Build the loot draw (#323 re-cut): a weighted union of THREE provenance
## buckets, each a straight source-array read (no `StatBoard.modifiers[]` to
## filter — see the RE-CUT comment on #323). `weights` is parallel to
## `candidates` (index-aligned) so the claimant can do weighted round-robin
## sampling per pick-1-of-3 round (see [SkillDustAddon]) without needing the
## bucket structure itself.
##
## `would_cycle` is DELIBERATELY NOT checked here — the claimant (whoever
## allocates the relic node) isn't known at draw/death time, so cycle-safety
## is a claim-time concern, filtered per round against the collector's live
## board (see [method SkillDustAddon._on_carrier_owner_changed]).
##
## `pick_count` (N rounds) scales with victim level exactly as before, now
## against the TOTAL pool across all three buckets. When N >= supply there's
## no real choice, so at least one candidate is always left on the table
## (supply >= 2) — same "keep the draw a genuine choice" invariant as #173.
## Every entry is `duplicate(true)`d so the dust owns independent copies.
## Returns { "candidates": Array[StatModifier], "weights": Array[float],
## "pick_count": int }.
func _draw_payload(victim: Entity) -> Dictionary:
	var candidates: Array[StatModifier] = []
	var weights: Array[float] = []
	var buckets := [
		[_expand_for_loot(_node_grant_modifiers(victim)), weight_bucket_node],
		[_expand_for_loot(_core_modifiers(victim)), weight_bucket_class],
		[_expand_for_loot(_innate_modifiers(victim)), weight_bucket_innate],
	]
	for bucket in buckets:
		var mods: Array = bucket[0]
		var weight: float = bucket[1]
		for m in mods:
			candidates.append((m as StatModifier).duplicate(true))
			weights.append(weight)

	var supply := candidates.size()
	var pick_count := clampi(victim.entity_tier, 0, supply)
	# Keep the draw a genuine choice whenever one is possible. N == M is a
	# no-choice by construction (the addon auto-grants and the picker skips it),
	# so a keep-count that saturates the supply silently deletes the entire
	# pick-1-of-3-per-round feature. Leaving at least one modifier on the table
	# is what makes it a decision.
	if supply >= 2:
		pick_count = mini(pick_count, supply - 1)

	return {"candidates": candidates, "weights": weights, "pick_count": pick_count}


## The non-core nodes the victim still owns at death — the TERRITORY signal
## feeding the kill-XP payout (was the loot draw pre-#173-rework). Reads the
## owned-subgraph mirror, so cascade-stripped nodes are already excluded — which
## is exactly why the payout unions this with the removal ledger rather than
## trusting it alone.
func _held_nodes(victim: Entity) -> Array[SkillNode]:
	var out: Array[SkillNode] = []
	if victim.navigator == null:
		return out
	var core := victim.core_location
	for n in victim.navigator.get_mirrored_nodes():
		if n != null and n != core:
			out.append(n)
	return out


## NODE-GRANT bucket (#323): the modifiers authored on every non-core node the
## victim still owns at death (`_held_nodes` — pre-strip, since this runs
## during `entity_dying`). These mods are NOT removed from the node — they
## still return to the graph on the strip exactly as before; only a
## `duplicate(true)`d copy (done by the caller, [method _draw_payload]) enters
## the loot pool.
func _node_grant_modifiers(victim: Entity) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for n in _held_nodes(victim):
		out.append_array(n.modifiers)
	return out


## BOARD-INNATE bucket (#323): the victim's own [member
## EntityStatBoard.intrinsic_modifiers] — rules true of every entity that plays
## by this board, not this entity's particular build.
func _innate_modifiers(victim: Entity) -> Array[StatModifier]:
	if victim.stat_board == null:
		return []
	return victim.stat_board.intrinsic_modifiers


## CLASS/REGISTER bucket (#323): [member Entity.core_modifiers] — the granted-
## atom register. This is the ONLY bucket for anything ever permanently granted
## onto the core: original class-template grants AND previously-looted grants
## both live here (there is no separate "looted" bucket — see the RE-CUT
## comment on #323). `_is_lootable`'s old `scales_with(&"level")` exclusion is
## GONE (#323) — stealing a level-scaler is the intended roguelite loop now,
## not a hazard to filter out.
func _core_modifiers(victim: Entity) -> Array[StatModifier]:
	return victim.core_modifiers


## Expands each [CompositeStatModifier] whose [member
## CompositeStatModifier.loots_as_unit] is `false` into its children — separate
## loot candidates, filtered per-leaf by [method _is_lootable] afterwards — and
## leaves every other entry (a plain modifier, or a `true` pack) whole as one
## candidate. Runs BEFORE the lootability filter so a `false` pack whose
## children mix level-scaling and static entries filters per-leaf instead of
## excluding the whole pack over one scaling child (D-27, #279).
func _expand_for_loot(mods: Array[StatModifier]) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	var untyped: Array = mods  # untyped: element `is` narrows cleanly (see stats-system.md)
	for m in untyped:
		if m == null:
			continue
		if m is CompositeStatModifier and not (m as CompositeStatModifier).loots_as_unit:
			out.append_array(StatModifier.flatten_all([m]))
		else:
			out.append(m)
	return out


func _attach_addon(node: SkillNode, addon: SkillNodeAddon) -> void:
	node.add_child(addon)


# ── #204: Spellbook loot draft (widened to the victim's full spellbook,
# re-cut to fire on CLAIM, not on kill) ───────────────────────────────────────
## The draft draws from every spell the victim currently knows — core-sourced,
## innate, AND territory-sourced. #204 originally restricted this to the
## PERMANENT subset (core ∪ innate), reasoning that a territory-sourced spell
## would "duplicate a spell still live on the battlefield" (re-obtainable by
## allocating the same node). In practice every entity starts from the same
## shared spellbook_default.tres and a SpellGrant landing on any given
## entity's OWN core node is rare, so `permanent_spells` almost never diverges
## between claimant and victim — the draft had nothing to offer. Widening to
## the full spellbook is a deliberate design change, not the original spec:
## whoever permanently claims the relic (allocates the node — the SAME actor
## SkillDust's stat rounds already pay, not necessarily the killer) claims a
## spell the victim currently held by ANY means, territory included.
##
## Only the SNAPSHOT happens here, at `entity_dying` (pre-strip) — reading
## `victim.spellbook` any later would miss a core-sourced spell once
## AllocationSystem's `entity_died` strip revokes it. The offer/filter/grant
## itself runs on [SkillDustAddon] at claim time, as a bonus round appended
## AFTER every stat round has resolved — see that class's doc.
func _spell_candidates(victim: Entity) -> Array[SpellDef]:
	var victim_book := victim.spellbook
	if victim_book == null or victim.core_location == null:
		return []
	return victim_book.spells.duplicate()
