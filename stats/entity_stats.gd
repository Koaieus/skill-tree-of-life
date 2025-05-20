extends Stats
class_name EntityStats

@export var experience: ExpStat = ExpStat.new()
@export var skill_points: SkillPointPoolStat = SkillPointPoolStat.new()
@export var strength: StrengthStat = StrengthStat.new(0)
@export var intelligence: IntelligenceStat = IntelligenceStat.new(0)
@export var dexterity: DexterityStat = DexterityStat.new(0)
