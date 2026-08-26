class_name Participant
extends Resource

## One seat in a run — a human somewhere, or an AI.
## Plain data; [ParticipantRoster] owns lifecycle, [GameRoot] spawns from it.

## What drives this seat. [b]Absolute, not relative (#562)[/b] — there is no
## local/remote flavour of HUMAN here, because "local" is a RELATION between a
## participant and the machine reading it, and a roster crosses the wire: the
## same row is correctly local on one peer and remote on the other, so any
## answer frozen into the payload is wrong for exactly one of the two readers.
## Ask [method is_local] instead, which compares [member peer_id] against the
## reader's own. Same rule `.claude/rules/ownership-vocabulary.md` already
## draws for `owned_by` vs [member SkillNode.ownership_bit].
enum Kind { HUMAN, AI }

@export var id: int = 0
@export var display_name: String = ""
@export var color: Color = Color.WHITE
@export var camp: Faction = null
## The class branding this seat's hero (#618 D1) — and, riding along on it,
## the sigil the lobby row and the HUD hero card draw. Deliberately NOT a
## separate `sigil` field: [member CoreClass.sigil] already owns that glyph, and
## a second one here would be two sources of truth for one mark.
##
## `null` means "the level's default for this kind" — [ProcgenPlaySandbox]'s
## `core_class` / `enemy_core_class` exports. A roster the lobby authored always
## fills this in; a hand-rolled fallback roster may not.
@export var core_class: CoreClass = null
@export var kind: Kind = Kind.HUMAN
## Which machine this seat sits at. 0 outside a versus run (single-player and
## hot-seat alike — see `session/game_session.gd`), a real transport peer id
## inside one. THE absolute fact about locality; everything relational is
## derived from it.
@export var peer_id: int = 0


## Is this seat at the machine whose own id is [param local_peer_id]?
##
## The one named home for the question [enum Kind] used to answer wrongly
## (#562). A human and an AI alike can be "at" a machine — an AI belongs to the
## peer that simulates it — so this asks locality only; pair it with
## `kind != Kind.AI` when you want "the human I play".
func is_local(local_peer_id: int) -> bool:
	return peer_id == local_peer_id


## Wire form for #528's run-setup replication — plain primitives, the same
## shape [method Command.to_dict] already uses, so this crosses a
## [NetworkTransport] with no extra encoding step.
##
## [member kind] crosses as its raw int and is read back the same way (#562
## decision 3): the enum lost its local/remote human split rather than gaining
## a field, so `HUMAN = 0` and `AI = 1` (AI moved down from 2). No compatibility shim — there are no
## distributed builds, and #546's build-stamp gate refuses a mismatched link.
##
## [member camp] crosses as a resource PATH, not an interned index. #528's own
## acceptance spec calls that acceptable here (unlike #527's per-node
## archetype/addon refs): there are only a handful of factions, so the
## per-node string cost that matters at 2000 nodes doesn't matter at a
## handful of participants. Reuse [GraphSnapshot]'s interning table if this
## ever needs to ride inside a graph snapshot instead of a roster payload.
##
## [member core_class] gets exactly the same treatment (#618 D2) and for the
## same reason: a resource REFERENCE must never enter a wire form
## (`.claude/rules/multiplayer-sync.md`), so it crosses as a path and each peer
## `load()`s its own instance.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"color": color,
		"camp": camp.resource_path if camp != null else "",
		"core_class": core_class.resource_path if core_class != null else "",
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
	var core_path := String(d.get("core_class", ""))
	p.core_class = load(core_path) as CoreClass if core_path != "" else null
	p.kind = int(d.get("kind", Kind.HUMAN)) as Kind
	p.peer_id = int(d.get("peer_id", 0))
	return p
