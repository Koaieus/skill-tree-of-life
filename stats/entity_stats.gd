extends Stats
class_name EntityStats

@export_group('Level and skill points')
@export var experience: ExpStat = ExpStat.new()
@export var experience_gain: ExperienceGainStat = ExperienceGainStat.new()
@export var skill_points: SkillPointPoolStat = SkillPointPoolStat.new()

@export_group('Initiative')
@export var initiative: InitiativeStat = InitiativeStat.new()

@export_group('Battle stats')
@export var strength: StrengthStat = StrengthStat.new(0)
@export var intelligence: IntelligenceStat = IntelligenceStat.new(0)
@export var dexterity: DexterityStat = DexterityStat.new(0)
