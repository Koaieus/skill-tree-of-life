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

## The command pipeline a relic's claim flow runs through (#522). Stamped onto
## every [SkillDustAddon] this system drops, so the addon needs no lookup — DI,
## per `.claude/rules/scene-composition.md`. Null is a supported configuration
## (headless fixtures, the editor): the addon then runs its rounds inline, the
## pre-#522 behaviour.
@export var command_applier: CommandApplier

## The outstanding-pick book, stamped onto the relic alongside the applier.
## Only consulted for a REMOTE collector, which nothing reports today — see
## [LootPickRegistry].
@export var pick_registry: LootPickRegistry

## The mirror-side signal source for #564's adapter (see [method
## _on_loot_offer_received], below). Null on the authority side and on any
## no-link configuration (headless fixture, editor, offline sandbox) — a mirror
## peer is the only consumer of [signal CommandLink.loot_offer_received].
@export var command_link: CommandLink

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
	# #564: the mirror-side adapter. Independent of the battle_system-null
	# early return below — a headless fixture that never runs a cascade may
	# still want to exercise the loot-offer adapter, and vice versa.
	if command_link != null:
		command_link.loot_offer_received.connect(_on_loot_offer_received)
	if command_applier != null:
		command_applier.command_applied.connect(_on_command_applied)
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
		"candidates": [] as Array[StatModifier], "weights": [] as Array[float], "rounds": 0
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
	dust.rounds = draw["rounds"]
	dust.victim_color = victim.color
	dust.spell_candidates = spell_candidates
	dust.command_applier = command_applier
	dust.pick_registry = pick_registry
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
## `rounds` (how many pick-1-of-3 rounds) scales with victim level as before, now
## against the TOTAL pool across all three buckets. When N >= supply there's
## no real choice, so at least one candidate is always left on the table
## (supply >= 2) — same "keep the draw a genuine choice" invariant as #173.
## Every entry is `duplicate(true)`d so the dust owns independent copies.
## Returns { "candidates": Array[StatModifier], "weights": Array[float],
## "rounds": int }.
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
	var rounds := clampi(victim.entity_tier, 0, supply)
	# Keep the draw a genuine choice whenever one is possible. N == M is a
	# no-choice by construction (the addon auto-grants and the picker skips it),
	# so a keep-count that saturates the supply silently deletes the entire
	# pick-1-of-3-per-round feature. Leaving at least one modifier on the table
	# is what makes it a decision.
	if supply >= 2:
		rounds = mini(rounds, supply - 1)

	return {"candidates": candidates, "weights": weights, "rounds": rounds}


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


# ── #564: mirror-side loot-pick adapter ───────────────────────────────────────
## Gives [signal CommandLink.loot_offer_received] its first production
## consumer. A remote collector's peer receives a downward [LootPickOffer] (see
## that class + [LootPickRegistry]'s class doc) and has nothing that opens a
## picker for it — this rebuilds the SAME [LootPickRequest] / [SpellLootRequest]
## shape the host's own claim flow raises and re-emits it on the SAME
## `Events.loot_pick_requested` / `Events.spell_loot_requested` bus (owner call
## 2026-08-28: reuse the Events path — [HudRoot] and [LootPicker] /
## [SpellLootPicker] need no second raising path).
##
## [b]The rebuilt request never touches [member pick_registry].[/b] A mirror
## peer's registry stays inert (owner call 2026-08-27, [LootPickRegistry]'s
## class doc) — this request's resolver submits the pick UPWARD as a
## [PickLootCommand] instead of granting or parking anything locally. The
## round's actual outcome only lands when the host's confirmed
## [LootRoundCommand] replays here, same as every other peer.
##
## The one request outstanding at a time on this peer — a relic's claim chain
## is one round at a time by construction (see [SkillDustAddon]'s class doc),
## so there is never more than one rebuilt request open here, same coarse
## assumption [method CommandApplier.apply_remote]'s [PickLootCommand] gate
## already makes ("closes on the NEXT LootRoundCommand this peer receives").
var _pending_mirror_request: Variant = null


## Rebuild [param offer] into a request and raise it. `collector_id` resolves
## through the applier's own graph — the same lookup [method
## CommandApplier._apply_loot_round] uses — never a fresh source; a mirror has
## none.
func _on_loot_offer_received(offer: LootPickOffer) -> void:
	if offer == null:
		return
	_force_settle_pending_mirror_request()
	var graph: Graph = command_applier.graph if command_applier != null else null
	var collector: Entity = graph.get_by_entity_id(offer.collector_id) if graph != null else null
	var request: Variant
	if offer.kind == LootPickOffer.KIND_SPELL:
		var spell_candidates: Array[SpellDef] = []
		for id: StringName in offer.spell_ids:
			var s := SpellCatalog.by_id(id)
			if s != null:
				spell_candidates.append(s)
		request = SpellLootRequest.new(collector, spell_candidates,
				_submit_pick_upward.bind(offer.request_id, offer.collector_id, spell_candidates))
	else:
		request = LootPickRequest.new(collector, offer.stat_candidates,
				_submit_pick_upward.bind(offer.request_id, offer.collector_id, offer.stat_candidates))
	_pending_mirror_request = request
	# Owner call 2026-08-27 (acceptance 3): a collector that dies while this
	# peer's picker is up must not leave it stranded — auto-forfeit and let the
	# forfeit travel upward as `chosen_index == -1`, same shape as
	# [SkillDustAddon]._await_pick's own death guard on the host side.
	if is_instance_valid(collector):
		var forfeit_on_death := func() -> void:
			if not request.is_resolved():
				request.resolve(_mirror_empty_like(request))
		collector.died.connect(forfeit_on_death, CONNECT_ONE_SHOT)
	if offer.kind == LootPickOffer.KIND_SPELL:
		Events.spell_loot_requested.emit(request)
	else:
		Events.loot_pick_requested.emit(request)


## The resolver every rebuilt request shares, bound with the offer's
## `request_id` / `collector_id` / candidate list. `chosen` is whatever the
## picker (or the death-forfeit guard above) resolved the request with — empty
## means forfeit. Submits through [member command_applier], which for a
## MIRROR routes a [PickLootCommand] upward untouched
## ([method CommandApplier.submit] -> [method CommandApplier._submit_upward]);
## nothing new is needed there (#564 verified against master).
func _submit_pick_upward(chosen: Array, request_id: int, collector_id: int,
		candidates: Array) -> void:
	if command_applier == null:
		return
	var chosen_index := -1
	if not chosen.is_empty():
		chosen_index = candidates.find(chosen[0])
	command_applier.submit(PickLootCommand.new(collector_id, request_id, chosen_index))


## Every applied command crosses here (host and mirror alike); a
## [LootRoundCommand] replaying means the round this peer's outstanding request
## belonged to has been decided by the host — whether by this peer's own answer
## (already resolved; this only clears the reference) or by a host-side timeout
## / death forfeit this peer never saw (still open; force it closed so its
## picker modal dismisses instead of hanging — [LootPicker] / [SpellLootPicker]
## listen for `settled` and dismiss on an externally-resolved request).
func _on_command_applied(command: Command, _success: bool) -> void:
	if not (command is LootRoundCommand):
		return
	_force_settle_pending_mirror_request()


func _force_settle_pending_mirror_request() -> void:
	if _pending_mirror_request == null:
		return
	var request: Variant = _pending_mirror_request
	_pending_mirror_request = null
	if not request.is_resolved():
		request.resolve(_mirror_empty_like(request))


## The correctly-typed empty array for whichever request kind [param request]
## is — GDScript has no generics, so this can't be shared with
## [method LootPickRegistry._empty_like] / [method SkillDustAddon._forfeit_like]
## across files.
func _mirror_empty_like(request: Variant) -> Array:
	if request is SpellLootRequest:
		return [] as Array[SpellDef]
	return [] as Array[StatModifier]
