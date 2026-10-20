class_name StatusInstance
extends HitInstance

## A single status application produced by an [ApplyStatusEffect] on-hit
## effect (#878, #868 hub) — [HealInstance]/[DamageInstance]'s sibling for the
## third [enum HitInstance.Kind]. Pure data until [method land_on]: the actual
## mutation is [method NodeCombat.apply_status], run against whichever
## [CombatWorld] the applier hands in — a throwaway shadow for a resolve/
## preview pass, the live world for a real landing or a peer's replay of the
## recorded result (`.claude/rules/attack-timeline.md`).
##
## [member HitInstance.amount] / [member HitInstance.effective_amount] both
## carry [member power] once landed, rather than growing a parallel wire
## field — [AttackRecord] already ships every hit's `effective_amount`, so a
## status rides that array for free (#878, see [method AttackRecord.capture]).

## The status this instance applies. Crosses the wire as
## [member Resource.resource_path] ([AttackRecord] `KEY_HIT_STATUS_DEF`),
## never a live reference — same pattern as [PresentationTempo]
## (`attack_record.gd`'s `_tempo_path` / `_tempo_of`). A [StatusDef] built in
## memory with no backing `.tres` therefore cannot survive a record round
## trip; author one under `test/` for anything that needs to.
var def: StatusDef = null
## Stacks handed to [method NodeCombat.apply_status]. Until [method land_on]
## runs this is the applier's authored per-hit number ([member
## ApplyStatusEffect.power], on a spell, an arrow or a blade); land folds the
## attacker's stacks stat into it exactly once (#963) — or zeroes it when the
## receiving host [method StatusHost.blocks] it — and the LANDED number is
## what [AttackRecord] ships. Resistance below 100% never touches it: the
## host filters the row at effect time (ADR 0031).
var power: float = 0.0
## True once [member power] is the landed number — set by [method land_on]
## on the authority's own resolve and by [method AttackRecord.rebuild], which
## reconstructs the hit flat so a peer's replay lands it rather than scaling
## it a second time (the [member HitInstance.basis] `PERCENT_MAX` precedent).
var power_resolved: bool = false
## A raw transfer ([HaulEffect]): [member power] lands as authored — no
## `stacks_per_hit` fold, no [member stack_terms], no crit, no
## [member stack_scale] — while the block gate and Greed's ×2 still apply.
## Resolve-local: the record ships the landed [member power] and a rebuilt hit
## is [member power_resolved], so a replay never needs it.
var raw: bool = false
## The landing's swing-time overlay lookup ([member HitLanding.read_overlays]),
## folded into the stacks read at [method land_on]. Unset for every landing but
## a blade contact's. Resolve-local, like [member HitInstance.read_node]: the
## record ships the landed [member power], so a peer never reads it.
var read_overlays: Callable = Callable()
## Multiplies the FOLDED stacks at [method land_on] — after the stacks stat,
## beside the crit factor — so a 0 lands 0 however much `stacks_per_hit` is
## invested. Stamped by [ApplyStatusEffect] from a spell landing's
## [member HitLanding.stack_scale]; never shipped, because the landed
## [member power] is (a rebuilt hit is [member power_resolved]).
var stack_scale: float = 1.0
## Extras added to the folded stacks at [method land_on], before crit — copied
## from [member ApplyStatusEffect.stack_terms]. Resolve-local like
## [member stack_scale]: the record ships the landed [member power].
var stack_terms: Array[StackTerm] = []

## Which host the status LANDED on (#996, hub #994). NODE is the ordinary
## landing; ENTITY is the fall-through — the target is its owner's core and
## that core is cracked (`hp.current == 0`) at land time, so the row goes on
## the entity's own [StatusHost] and ticks the `health` pool. Resolved in
## [method land_on] on the authority, alongside [member power_resolved], and
## shipped by [AttackRecord] (`KEY_HIT_STATUS_HOST`) so a peer lands on the
## same host without re-deriving it from node HP.
enum HostKind { NODE, ENTITY }
var host_kind: HostKind = HostKind.NODE

func _init() -> void:
	kind = Kind.STATUS


## Copies [param landing]'s shared facts onto [param status] — the one stamping
## for a status hit an on-hit effect decides at land. Power, overlays and stack
## fields are the caller's own writes after the call.
static func stamp_landing(status: StatusInstance, p_def: StatusDef, landing: HitLanding) -> void:
	status.def = p_def
	status.attacker = landing.attacker
	status.source = landing.source
	status.target = landing.target
	status.origin = landing.origin
	status.read_node = landing.read_node
	status.structural_key = landing.structural_key
	status.paired = landing.paired
	status.hit_key = landing.hit_key


## A status rider lands before its paired hit, so its effect (a curse floor,
## a sunder, a mark) lifts that hit (ADR 0067). A blast's status or a
## splash copy ([member HitInstance.blast_mark] / [member HitInstance.land_mask],
## both stamped before the landing is placed) is damage-shaped and stays after.
func land_priority() -> int:
	if blast_mark != null or land_mask != 0:
		return LandPriority.AFTER
	return LandPriority.BEFORE


## [param node] is a [NodeCombat] — a shadow slice mid-resolve, or the live
## slice on a real landing / a peer's replay (#498 step 3, the same contract
## every other [HitInstance] follows: [member HitInstance.target] stays the
## real identity, [param node] is whichever state this landing mutates).
## [method StatusHost.apply_status] is already a no-op on a null def, a
## non-positive power, and an unallocated host under a `CLEAR` policy (#872),
## so this does not re-gate any of that.
##
## Fall-through (#996, owner 2026-09-20 on #994): the status lands on the
## ENTITY iff [param node] is its owner's core AND that core is cracked
## (`hp.current == 0`) at this moment — damage landed earlier in the same
## `outcome.hits` is visible, so an arrow that cracks the core sends its own
## poison through. Decided once, on the authority, into [member host_kind];
## a rebuilt hit lands on the shipped host without re-reading node HP. A row
## already on the core node does NOT stay there once the core cracks: the
## crack transition in [method NodeCombat.take_damage] moves every node row
## onto the entity (ADR 0066), so a rider that landed before its cracking hit
## reaches the entity too.
##
## Scaling (`docs/domain/effect-system.md` § "Status effects — the DoT model"):
## `StatusDef.stacks_per_hit_at(read slice, power)` — one fold of the stacks
## stat through [member HitInstance.read_node]'s slice in [param world] (entity
## bins, that node's local bins, the authored power as `base_add`), so a shadow
## resolve reads the shadow and a node-local modifier scales only that node's
## hits. No read node (a hand-built hit) falls back to
## `StatusDef.stacks_per_hit(attacker board, power)`; a null attacker, blank id
## or unknown stat leaves it at the authored power.
## Resistance is NOT folded here (ADR 0031): the host filters the row at each
## apply and tick. The one thing decided at land is the 100% gate — the
## RECEIVING host (the landing slice, so a shadow resolve reads the shadow,
## or the entity on fall-through) [method NodeCombat.blocks_status] it and
## the hit resolves to 0, which [method StatusHost.apply_status]'s
## non-positive gate makes a no-op. Resolved once: a rebuilt hit arrives
## [member power_resolved] and lands the recorded number as-is.
##
## Stack terms ([member stack_terms]): each adds `≥ 0` stacks to the fold,
## read against [param world] — the read node's slice and the receiving
## [param node] — before crit, so crit, scale and Greed multiply the whole sum.
## Skipped with no read node and on an ENTITY host.
##
## Crit: a spell's condition-tier crit ([CritRoll], never `crit_chance`)
## lands the folded stacks × `abs(crit_multiplier)` — a separate factor right
## after the fold; a non-crit is ×1. A rebuilt hit arrives resolved, so the
## peer never multiplies twice.
##
## Greed (the defender-side term): a landed, positive, `debuff`-tagged power
## doubles iff the receiving host [method StatusHost.greed_arm]s this hit —
## after the stacks fold and the block gate, so a blocked rider never spends.
## A rebuilt hit's recorded power is already doubled, but it still arms, so
## the live host spends the stack the shadow spent. The host is the landing
## host: entity Greed is read only on a fall-through, node Greed otherwise.
func land_on(node: NodeCombat, world: CombatWorld) -> void:
	if rider_gated(node, world):
		gated = true
		power = 0.0
		amount = 0.0
		effective_amount = 0.0
		return
	if not power_resolved:
		if node.is_core() and node.get_current_hp() <= 0.0:
			host_kind = HostKind.ENTITY
	var host = node
	if host_kind == HostKind.ENTITY:
		host = node.owner()
		if host == null:
			# A replay whose node lost its owner to an earlier hit's cascade:
			# nothing to land on, nothing landed (`apply_status` self-gates
			# only on a node).
			amount = 0.0
			effective_amount = 0.0
			return
	if not power_resolved:
		if def != null:
			if not raw:
				var rn: NodeCombat = world.combat_for(read_node) if world != null else null
				var extra: Array[ModifierBins] = []
				if read_overlays.is_valid():
					extra = read_overlays.call(def.stacks_stat_id())
				power = def.stacks_per_hit_at(rn, power, extra) if rn != null \
					else def.stacks_per_hit(_attacker_board(), power)
				if rn != null and host_kind == HostKind.NODE:
					for term in stack_terms:
						if term != null:
							power += maxf(0.0, term.extra(rn, node))
				power *= absf(crit_multiplier)
				power *= stack_scale
			# The row is integer (ADR 0032): round once, half-up, after crit × scale.
			power = StatusDef.round_half_up(power)
			if host.blocks_status(def):
				power = 0.0
			if _greed_arms(host):
				power *= 2.0
		power_resolved = true
	else:
		_greed_arms(host)
	host.apply_status(def, power, _attacker_camp_id(), _attacker_id())
	amount = power
	effective_amount = power


## Whether this landing is a debuff with stacks AND [param host] arms Greed
## for its hit — spending one stack the first time it sees [member hit_key].
func _greed_arms(host) -> bool:
	return def != null and power > 0.0 and def.tags.has(&"debuff") and host.greed_arm(hit_key)


## The applier's camp for [method StatusDef.group_key]: its faction's id,
## `&""` with no attacker or faction.
func _attacker_camp_id() -> StringName:
	return attacker.faction.id if attacker != null and attacker.faction != null else &""


func _attacker_id() -> int:
	return attacker.entity_id if attacker != null else 0


func _attacker_board() -> StatBoard:
	return attacker.stat_board if attacker != null else null


func _to_string() -> String:
	var name: String = def.display_name if def != null else "<null>"
	return "<StatusInstance %s %.1f → %s>" % [name, power, target]
