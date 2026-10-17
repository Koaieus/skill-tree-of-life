class_name HitLanding
extends RefCounted

## One landing of an attack on one node, in terms every attack mode shares —
## what an [OnHitEffect] reads, whichever mode produced the landing (ADR 0044).
## A spell's landing is the [LandingContext] subclass (this plus spell
## context); an arrow's or a blade contact's is a bare [HitLanding] its
## resolver fills. Field names mirror [HitInstance]'s: the landing IS the
## facts its emitted hits share, so it never disagrees with them.

## The [Entity] whose attack this is — copied onto every emitted hit's
## [member HitInstance.attacker].
var attacker: Entity = null
## What produced the landing ([member HitInstance.source]).
var source: Variant = null
## Where the landing came from — VFX spawn point ([member HitInstance.origin]).
var origin: SkillNode = null
## The attacker-side node the landing reads its local stats from
## ([member HitInstance.read_node]) — resolve-local, never on the wire.
var read_node: SkillNode = null
## The swing-time overlays on [member read_node]'s read of a stat, as
## `(stat_id) -> Array[ModifierBins]` — what a status's stacks fold reads so a
## one-swing temp addon counts like a placed one. Only a blade contact sets it;
## unset means no overlays. Resolve-local, never on the wire.
var read_overlays: Callable = Callable()
## The landed node ([member HitInstance.target]).
var target: SkillNode = null
## The landing's structural position, in its outcome's cadence units
## ([member HitInstance.structural_key]).
var structural_key: float = 0.0
## The primary hit this landing rides on — the arrow's damage hit, the blade
## contact — or null when nothing gates it (a spell). An emitted
## [StatusInstance] carries it as [member HitInstance.paired], which
## gates whether it applies.
var paired: HitInstance = null
## The sink: every [HitInstance] an effect emits ([method emit]) is appended
## here, in authored order, until the builder calls [method place]. Usually
## the outcome's own [member AttackOutcome.hits], by reference.
var hits: Array[HitInstance] = []
## Where this landing's span starts in [member hits]: the paired hit's slot
## ([method riding]), or the spell's first hit at this landing
## ([SpellResolver] stamps it). [method place] orders [code]hits[anchor..][/code];
## [code]-1[/code] = no span, nothing to order.
var anchor: int = -1
## Which hit this is — unique per landing, process-wide monotonic from 1;
## equality is the only thing anyone reads, never order. Every rider the
## landing emits carries it as [member HitInstance.hit_key], so a host can
## tell "another rider of a hit I already answered" from "a new hit" (Greed's
## one spend per hit, [method StatusHost.greed_arm]).
var hit_key: int = 0
## Finder gathers already swept for this landing's compile, keyed
## `[target, finder, reach]` to the gather result BEFORE any ownership mask —
## so one cache serves every mask ([method SplashEffect._reach_of]). A volley
## shares one across all its arrows ([RangedAttackPlan]); a landing that is
## handed none keeps its own empty one and sweeps every time. Dies with the
## compile, so nothing in it goes stale.
var gather_cache: Dictionary = {}
## The multiplier this landing's [StatusInstance]s land their folded stacks
## with — 1.0 is "unscaled", 0.0 lands nothing. Any mode may read it
## ([ApplyStatusEffect] copies it onto every status it mints); today only
## spell context writes it (the reducer's seed in [SpellResolver],
## [ScaleStacksEffect]). Per landing, so it never compounds across hops.
var stack_scale: float = 1.0
## The landing's own amount, raw (pre-crit, pre-mitigation) — the arrow's or
## the contact's damage, a ridden heal's amount, a spell payload's damage — and
## its damage type (unread for a heal). What a [PairedDamageEffect] takes its
## share of; 0 when the landing carries none.
var raw_amount: float = 0.0
var raw_type: DamageInstance.Type = DamageInstance.Type.PHYSICAL
## Who this landing's attack may hit, as [NodeTargeting]'s ownership flag set —
## hostile for an arrow or a blade, the spell's targeting filter for a spell.
## A [SplashEffect] with filter 0 splashes with it. 0 = unknown: such a splash
## reaches nothing. Stamped by the landing's builder.
var target_mask: int = 0
## The dedupe scope of explosive detonations: every node this landing's hit
## already set off, `SkillNode -> true`. Built once per arrow (each
## [method riding] starts empty) and once per spell wave ([SpellResolver]
## stamps one dict on every landing of the wave); a blast's chained
## [DetonateEffect] shares its parent's, so a chain never sets a node off twice.
var detonated: Dictionary = {}

static var _next_hit_key: int = 1


## The landing a non-spell mode's riders run on: [param primary]'s attacker,
## source, origin, read node, target and structural key; [member paired] =
## [param primary] (so every rider is gated by it); [param hits] and
## [param gather_cache] by reference. Stamps the landing's [member hit_key]
## onto [param primary] too, so the primary and its riders are one hit to a
## host. [member raw_amount] comes off [param primary] when it is damage or a
## heal, [member raw_type] when it is damage. Anything mode-specific ([member read_overlays],
## [member target_mask]) is caller-set after.
static func riding(primary: HitInstance, hits: Array[HitInstance], gather_cache: Dictionary = {}) -> HitLanding:
	var landing := HitLanding.new()
	landing.attacker = primary.attacker
	landing.source = primary.source
	landing.origin = primary.origin
	landing.read_node = primary.read_node
	landing.target = primary.target
	landing.structural_key = primary.structural_key
	landing.paired = primary
	landing.hits = hits
	var slot := hits.rfind(primary)
	landing.anchor = slot if slot >= 0 else hits.size()
	landing.gather_cache = gather_cache
	primary.hit_key = landing.hit_key
	var damage := primary as DamageInstance
	if damage != null:
		landing.raw_amount = damage.amount
		landing.raw_type = damage.type
	elif primary is HealInstance:
		landing.raw_amount = primary.amount
	return landing


## Emit [param hit] into this landing — what every [OnHitEffect] writer calls.
## Appends in authored order; the landing's builder calls [method place] once
## its effects have run, which orders the span by priority. Deferred on
## purpose: a [SplashEffect] / [BlastEffect] stamps the hits its inners
## appended by index range, which an insert ahead of it would miss.
func emit(hit: HitInstance) -> void:
	hits.append(hit)


## Order this landing's span ([code]hits[anchor..][/code]) by
## [method HitInstance.land_priority] — BEFORE, then PRIMARY, then AFTER —
## keeping authored order within a priority (a stable three-way partition,
## never a sort). Called once by the landing's builder, after its effects ran.
## Landing-scoped: hits outside the span, another arrow's included, never move.
func place() -> void:
	if anchor < 0 or anchor >= hits.size():
		return
	var buckets: Array = [[], [], []]
	for i in range(anchor, hits.size()):
		var hit := hits[i]
		buckets[clampi(hit.land_priority(), -1, 1) + 1].append(hit)
	var at := anchor
	for bucket: Array in buckets:
		for hit: HitInstance in bucket:
			hits[at] = hit
			at += 1


func _init() -> void:
	hit_key = _next_hit_key
	_next_hit_key += 1
