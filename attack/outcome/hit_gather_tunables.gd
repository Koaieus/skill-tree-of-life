@tool
class_name HitGatherTunables
extends Resource

## The land-time gather's tunables ([HitGather], #1798). One default
## (`hit_gather_tunables.tres`) is what the gather preloads; a test hands the
## gather its own instance through [member HitGather.tunables].


## The dual-reach dedupe (ADR 0084 §5, ADR 0086 §3; the owner's tentative
## option 2 is `false`). Off, a node two reaches of one hit gather takes one
## entry per reach (concatenate). On, a reached node's entries of one hit and
## one generation merge into one entry at the sum of their shares: damage × Σs
## plus the summed own damages, riders ceil(r × Σs), its terrain riders still
## once at the largest single share. It never merges the hit node's landings
## (the head and its centre copies). It runs over every reach list, whatever
## produced it, so it also decides a cast's shape against another element's
## go-off (#1812). Tentative: entries of different generations stay separate,
## the own damages sum, a merged entry keeps the first list's mark. An
## inspector bool, no editor feedback (no live go-off yet).
@export var dedupe_dual_reach := false
