class_name BlastMark
extends RefCounted

## One board blast, as its audience sees it: minted by [BlastEffect] once per
## blast and stamped on every hit the blast appends ([member HitInstance.blast_mark]),
## so [OutcomeApplier] can announce it ([signal Events.blast_landed]) when the
## first of those hits lands on a live world. A presentation fact riding the
## sim, never read by it.

## The node the blast is centred on — the one the triggering hit struck.
var centre: SkillNode = null
## The blast's reach in px: the sim's own [method ExplosiveSpread.radius_for],
## never a visual guess.
var reach: float = 0.0
## The detonation's power ([method DetonateEffect.power_of]); 0 when the
## emitter did not hand [member BlastEffect.power] over.
var power: int = 0
## The identities of the blast's status riders, explosive stripped.
var riders: Array[Identity] = []
## Whose blast it is.
var attacker: Entity = null
