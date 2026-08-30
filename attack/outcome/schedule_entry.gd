class_name ScheduleEntry
extends RefCounted

## One scheduled moment in an attack's presentation — [b]the[/b] surface every
## per-spell visual reads (#543 D6), and the thing landing order now keys off
## (#543 D2).
##
## An entry is one LANDING MOMENT, not one hit: a magic wave that converges two
## branches on a node is one entry holding one hit, and a
## [constant PropagationEvent.Verb.CANCEL] is an entry holding none. It carries
## two kinds of thing, and the distinction is the whole design:
##
##   * [b]Structure[/b] ([member structural_key], [member beat_index],
##     [member convergence_count], [member visit_index], [member is_terminal],
##     [member magnitude]) — what the resolver genuinely produced. Reproducible
##     on any peer from the same inputs, and therefore safe to key gameplay off.
##   * [b]Seconds[/b] ([member launch_at], [member arrive_at]) — what
##     [method OutcomeSchedule.compile] assigned from a [PresentationTempo] and
##     the local rate. Presentation only. [b]Never a sort key, never compared,
##     never on the wire.[/b] They are tempo-dependent and tempo is per-peer.
##
## Before #543 a visual received exactly one integer (`crit_tier`). Every field
## below is data the resolver already computed and then discarded, forwarded to
## the visual duck-typed as `_on_context(entry)` alongside the existing
## `_on_launch` / `_on_progress(t)` / `_on_arrival` / `_on_crit(tier)`.

## Which structural clock [member structural_key] is expressed in — i.e. which
## arithmetic [method OutcomeSchedule.compile] runs to turn it into seconds.
## Stamped on the [AttackOutcome] by the resolver/plan that produced it, one
## per outcome, because an outcome is one mode.
enum Cadence {
	## The key IS the second. The default, used by fixtures, hand-built
	## outcomes and anything with no mode structure to speak of; only the
	## player's rate scales it.
	LITERAL,
	## Magic. The key is the hop/wave index (an ordinal), turned into
	## `beat_lead_in + key * beat_interval`.
	BEAT,
	## Ranged. The key is the shot's normalized position in the volley's
	## DISTANCE span (0 = nearest leaf, 1 = farthest), turned into
	## `volley_draw_time + key * volley_stagger_span` for the launch and
	## `+ volley_flight_time` for the arrival.
	RAMP,
	## Melee. The key is normalized position along the swing (0..1) —
	## genuinely [BladeSim] output, which is why melee's structural parameter
	## is a float a peer replays rather than an ordinal it re-derives.
	SWING,
}

## Position in [member OutcomeSchedule.entries], assigned by the compiler after
## the structural sort. [b]This is the landing-order key[/b] — see
## [method OutcomeApplier.in_arrival_order] for why seconds are forbidden there.
var index: int = -1

## The mode's structural parameter, in the units [member Cadence] names.
var structural_key: float = 0.0

## Which wave this entry belongs to, and how many waves the whole cast has —
## together a normalized hop fraction, which is what a per-hop heat/size ramp
## reads (Lightning attenuates outward, Leafblower grows). For non-magic modes
## this degenerates to [member index] / entry count, which is still the honest
## "nth of n" answer.
var beat_index: int = 0
var beat_count: int = 1

## This entry's total authored hit amount as a fraction of the largest entry in
## the same outcome, in 0..1. 1.0 on the biggest landing, 0.0 for a CANCEL or a
## pure-utility event. The compiler is the only thing that sees the whole
## outcome at once, which is why normalization happens here and not in a visual.
var magnitude: float = 0.0

## How many predecessors converged on this landing — Resonator's entire read.
## 1 for the overwhelming majority (and for every non-magic entry).
var convergence_count: int = 1

## The nth strike on THIS node within this cast, 0-based. Reverberator's
## accumulation read collapses to noise without it: a node struck three times
## reports 0, 1, 2.
var visit_index: int = 0

## True when the walk ENDED here by terminal rule (hops exhausted, no step, no
## candidate left) rather than merely being the last thing in the list — Trail
## Blazer's junction slam. For non-magic modes, the final entry.
var is_terminal: bool = false

## Seconds from the attack's start. A PAIR, deliberately: a visual needs an
## honest window length, and making the compiler own both ends is what stops a
## coordinator re-deriving `launch = arrive - some_constant_it_also_owns`.
var launch_at: float = 0.0
var arrive_at: float = 0.0

## Where the thing travels from / to. Mirrors the event's (or the hit's) own
## endpoints so a visual needs no second lookup.
var origin: SkillNode = null
var target: SkillNode = null

## The landings this moment carries — SHARED references into
## [member AttackOutcome.hits], never copies, exactly as
## [member PropagationEvent.hits] are. Empty for a CANCEL / pure-utility entry.
var hits: Array[HitInstance] = []

## The [PropagationEvent] this entry was compiled from, or null for a
## melee/ranged entry (those modes emit no timeline).
var event: PropagationEvent = null


## Seconds the projectile is in the air — [member arrive_at] minus
## [member launch_at], never negative.
func window() -> float:
	return maxf(0.0, arrive_at - launch_at)


## Normalized hop fraction in 0..1 — 0 on the first beat, 1 on the last. A
## single-beat cast reports 0.0 rather than dividing by zero.
func beat_fraction() -> float:
	if beat_count <= 1:
		return 0.0
	return clampf(float(beat_index) / float(beat_count - 1), 0.0, 1.0)


## The highest [member HitInstance.crit_tier] across [member hits] — the same
## derived read [method PropagationEvent.max_crit_tier] performs, available on
## an entry so a non-magic visual can ask it too.
func max_crit_tier() -> int:
	var best := 0
	for hit in hits:
		best = maxi(best, hit.crit_tier)
	return best


func _to_string() -> String:
	return "<ScheduleEntry #%d b%d/%d k=%.3f %.3f→%.3f mag=%.2f>" % [
		index, beat_index, beat_count, structural_key, launch_at, arrive_at, magnitude]
