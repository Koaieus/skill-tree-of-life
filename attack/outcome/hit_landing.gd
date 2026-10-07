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
## The sink: every [HitInstance] an effect emits is appended here, in order.
## Usually the outcome's own [member AttackOutcome.hits], by reference.
var hits: Array[HitInstance] = []
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

static var _next_hit_key: int = 1


func _init() -> void:
	hit_key = _next_hit_key
	_next_hit_key += 1
