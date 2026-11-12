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
## Where the landing's OWN hits end and its riders begin: [code]anchor + 1[/code]
## for a ridden primary, the end of a spell's authored `on_hit_effects` hits at
## this landing. [method place] keeps [code]hits[anchor..lead)[/code] as one
## block in authored order and only moves the riders around it.
var lead: int = -1
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
## Who this landing's attack may hit, as [NodeTargeting]'s ownership flag set —
## hostile for an arrow or a blade, the spell's targeting filter for a spell.
## A [SplashEffect] with filter 0 splashes with it. 0 = unknown: such a splash
## reaches nothing. Stamped by the landing's builder; [method place] hands it
## to the head ([member HitInstance.target_mask]), whose go-offs' copies land
## under it.
var target_mask: int = 0
## What the landing site stamps onto each hit of its span, as
## `func(hit: HitInstance) -> void` — run by [method place] over
## [code]hits[anchor..][/code] once ordered, in placed order. A spell's stamps
## the caster, its crit conditions, the wave ordinal and the head's
## [member HitInstance.hit_load], and files the hit on
## its timeline event; an arrow's stamps its ammo id onto every rider. Unset =
## nothing stamped (a blade contact).
var stamper: Callable = Callable()

static var _next_hit_key: int = 1


## The landing a non-spell mode's riders run on: [param primary]'s attacker,
## source, origin, read node, target and structural key; [member paired] =
## [param primary] (so every rider is gated by it); [param hits] and
## [param gather_cache] by reference. Stamps the landing's [member hit_key]
## onto [param primary] too, so the primary and its riders are one hit to a
## host. Anything mode-specific ([member read_overlays], [member target_mask])
## is caller-set after.
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
	landing.lead = landing.anchor + 1 if slot >= 0 else landing.anchor
	landing.gather_cache = gather_cache
	primary.hit_key = landing.hit_key
	return landing


## Emit [param hit] into this landing — what every [OnHitEffect] writer calls.
## Appends in authored order; the landing's builder calls [method place] once
## its effects have run, which orders the span by priority. Deferred on
## purpose: a [SplashEffect] stamps the hits its inners appended by index
## range, which an insert ahead of it would miss.
func emit(hit: HitInstance) -> void:
	hits.append(hit)


## Copies the eight facts every hit of this landing shares — [member attacker],
## [member source], [member origin], [member read_node], [member target],
## [member structural_key], [member paired], [member hit_key] — onto
## [param hit]: the one landing-to-hit stamping an effect's minted hit takes
## ([method StatusInstance.stamp_landing]). Anything kind-specific is the
## caller's own write.
func copy_facts_to(hit: HitInstance) -> void:
	hit.attacker = attacker
	hit.source = source
	hit.origin = origin
	hit.read_node = read_node
	hit.target = target
	hit.structural_key = structural_key
	hit.paired = paired
	hit.hit_key = hit_key


## Order this landing's span by [method HitInstance.land_priority]: the
## riders after [member lead] that land BEFORE, then the landing's own block
## [code]hits[anchor..lead)[/code] untouched, then the riders that land PRIMARY,
## then AFTER — authored order kept within each (a stable partition, never a
## sort), marks the span's first hit the gather head
## ([member HitInstance.is_head], #1798), then runs [member stamper] over the
## placed span. Called once by the
## landing's builder, after its effects ran.
## Landing-scoped: hits outside the span, another arrow's included, never move.
func place() -> void:
	if anchor < 0 or anchor >= hits.size():
		return
	var own_end := clampi(lead, anchor, hits.size())
	var buckets: Array = [[], hits.slice(anchor, own_end), [], []]
	for i in range(own_end, hits.size()):
		var hit := hits[i]
		match hit.land_priority():
			HitInstance.LandPriority.BEFORE:
				buckets[0].append(hit)
			HitInstance.LandPriority.PRIMARY:
				buckets[2].append(hit)
			_:
				buckets[3].append(hit)
	var at := anchor
	for bucket: Array in buckets:
		for hit: HitInstance in bucket:
			hits[at] = hit
			at += 1
	# The span's first hit is the gather head (#1798): its hit is the span, and
	# its go-offs' copies land under this landing's mask (#1799).
	hits[anchor].is_head = true
	hits[anchor].target_mask = target_mask
	if stamper.is_valid():
		for i in range(anchor, hits.size()):
			stamper.call(hits[i])


func _init() -> void:
	hit_key = _next_hit_key
	_next_hit_key += 1
