@tool
class_name StatBoard
extends Resource

## An entity's stat board. Owns the entity's runtime stats keyed by id.
## Stub for now: Entity can already carry a board reference; the runtime
## stat instances land once `RuntimeStat` is built.
##
## v2 direction (see docs/design/stat_system.md): one stat vocabulary
## shared by all entities under Option A; tighten to typed inheritance
## (PlayerStatBoard extends EntityStatBoard) post first playable slice.

# @export var stats: Array[RuntimeStat] = []   # uncomment when RuntimeStat lands
