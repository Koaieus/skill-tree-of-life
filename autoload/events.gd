extends Node

signal skill_node_hovered(node: SkillNode)
signal skill_node_unhovered

signal attack_mode_requested(mode: BattleSystem.AttackMode)
signal attack_mode_denied(current_mode: BattleSystem.AttackMode)
