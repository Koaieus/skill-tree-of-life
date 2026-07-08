class_name LevelUpAnnouncementRequest
extends AnnouncementRequest

## TITLE-kind request for a level-up toast. Coalesces by entity (not by
## exact text) so a same-frame multi-level XP grant — Entity.leveled_up
## fires once per level, synchronously, via the XP pool's overflow-cascade
## recursion — merges into a single "+N Skill Points — Level M" toast
## instead of playing N banners back-to-back.

var entity: Entity
var skill_points_gained: int = 1
var new_level: int = 1


static func make_for_level_up(entity: Entity, skill_points_gained: int,
		new_level: int) -> LevelUpAnnouncementRequest:
	var r := LevelUpAnnouncementRequest.new()
	r.entity = entity
	r.skill_points_gained = skill_points_gained
	r.new_level = new_level
	r.kind = Kind.TITLE
	r.style = Style.LEVEL_UP
	r.main_text = "LEVEL UP"
	r.context = {&"entity": entity}
	r._refresh_sub_text()
	return r


func coalesce_key() -> Variant:
	return ["level_up", entity]


func absorb(other: AnnouncementRequest) -> void:
	stack_count += other.stack_count
	var lu := other as LevelUpAnnouncementRequest
	if lu != null:
		skill_points_gained += lu.skill_points_gained
		new_level = lu.new_level
	_refresh_sub_text()


func _refresh_sub_text() -> void:
	var plural := "" if skill_points_gained == 1 else "s"
	sub_text = "+%d Skill Point%s — Level %d" % [skill_points_gained, plural, new_level]
