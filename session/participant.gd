class_name Participant
extends Resource

## One seat in a run — a human at the keyboard, a remote peer, or an AI.
## Plain data; [ParticipantRoster] owns lifecycle, [GameRoot] spawns from it.

enum Kind { LOCAL_HUMAN, REMOTE_HUMAN, AI }

@export var id: int = 0
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var camp: Faction = null
@export var kind: Kind = Kind.LOCAL_HUMAN
## 0 = local; the versus hook, unused until a network transport exists.
@export var peer_id: int = 0


## Wire form for #528's run-setup replication — plain primitives, the same
## shape [method Command.to_dict] already uses, so this crosses a
## [NetworkTransport] with no extra encoding step.
##
## [member camp] crosses as a resource PATH, not an interned index. #528's own
## acceptance spec calls that acceptable here (unlike #527's per-node
## archetype/addon refs): there are only a handful of factions, so the
## per-node string cost that matters at 2000 nodes doesn't matter at a
## handful of participants. Reuse [GraphSnapshot]'s interning table if this
## ever needs to ride inside a graph snapshot instead of a roster payload.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"color": color,
		"camp": camp.resource_path if camp != null else "",
		"kind": kind,
		"peer_id": peer_id,
	}


static func from_dict(d: Dictionary) -> Participant:
	var p := Participant.new()
	p.id = int(d.get("id", 0))
	p.display_name = String(d.get("display_name", ""))
	p.color = d.get("color", Color.WHITE)
	var camp_path := String(d.get("camp", ""))
	p.camp = load(camp_path) as Faction if camp_path != "" else null
	p.kind = int(d.get("kind", Kind.LOCAL_HUMAN)) as Kind
	p.peer_id = int(d.get("peer_id", 0))
	return p
