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


## Sets [param status]'s def and copies [param landing]'s shared facts onto it
## ([method HitLanding.copy_facts_to]) — the one stamping
## for a status hit an on-hit effect decides at land. Power, overlays and stack
## fields are the caller's own writes after the call.
static func stamp_landing(status: StatusInstance, p_def: StatusDef, landing: HitLanding) -> void:
	status.def = p_def
	landing.copy_facts_to(status)


## A status rider lands before its paired hit, so its effect (a curse floor,
## a sunder, a mark) lifts that hit (ADR 0067). A blast's status or a
## splash copy ([member HitInstance.blast_mark] / [member HitInstance.land_mask],
## both stamped before the landing is placed) is damage-shaped and stays after.
func land_priority() -> int:
	if blast_mark != null or land_mask != 0:
		return LandPriority.AFTER
	return LandPriority.BEFORE


## Land the status on [param node] (a [NodeCombat]: a shadow slice mid-resolve,
## or the live slice on a real landing / a peer's replay). Falls through to the
## ENTITY iff the node is its owner's cracked core. Stacks are folded once on
## the authority (scaling, [member stack_terms], crit, Greed) and a rebuilt hit
## lands its recorded number as-is. See docs/domain/status-effects.md
## "StatusInstance.land_on".
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
