---
description: UI color palette ("Arcane Terminal") — source of truth per stat, OKLCH→sRGB values
paths:
  - "stats_system/defs/*.tres"
  - "ui/hud/**"
---

# UI color palette ("Arcane Terminal")

Canonical colors from `docs/design/design_handoff_game_ui/README.md`, converted OKLCH → sRGB once at authoring time (Godot `Color` has no OKLCH constructor). Source of truth for attribute/vital colors is **`StatDef.tint_color`** on the matching `.tres` in `stats_system/defs/` — don't introduce a second palette resource for those. SP-bucket colors aren't per-stat (SkillPointStat is one pool with internal buckets), so they live as `@export` defaults on the Skill Points gauge component instead.

| Name | OKLCH | sRGB `Color` | Where it lives |
|---|---|---|---|
| STR (Red) | `oklch(0.64 0.21 27)` | `Color(0.9451, 0.2689, 0.2453, 1)` | `stats_system/defs/strength.tres` |
| DEX (Green) | `oklch(0.74 0.16 150)` | `Color(0.3187, 0.7773, 0.4484, 1)` | `stats_system/defs/dexterity.tres` |
| INT (Blue) | `oklch(0.68 0.18 258)` | `Color(0.291, 0.5892, 1.0, 1)` | `stats_system/defs/intelligence.tres` |
| WIS (Gold) | `oklch(0.81 0.14 88)` | `Color(0.9039, 0.7331, 0.2746, 1)` | `stats_system/defs/wisdom.tres` |
| PER (Purple) | `oklch(0.66 0.21 305)` | `Color(0.6935, 0.4045, 0.9676, 1)` | `stats_system/defs/perception.tres` |
| CON (White, reserved 6th axis) | `oklch(0.92 0.02 250)` | `Color(0.8586, 0.9018, 0.9482, 1)` | not a live stat yet — reserve for when/if CON ships |
| Health (crimson) | `oklch(0.60 0.21 25)` | `Color(0.8878, 0.203, 0.2233, 1)` | `stats_system/defs/health.tres` |
| Mana (cyan) | `oklch(0.72 0.14 220)` | `Color(0.0, 0.72, 0.881, 1)` | `stats_system/defs/mana.tres` — was previously the same blue as INT; now differentiated |
| XP/gold | `oklch(0.80 0.14 88)` | `Color(0.8909, 0.7204, 0.2596, 1)` | `stats_system/defs/xp.tres` |
| SP to-spend | `oklch(0.70 0.16 250)` | `Color(0.2606, 0.6387, 0.9922, 1)` | Skill Points gauge component `@export` default |
| SP wounded | `oklch(0.60 0.20 25)` | `Color(0.8725, 0.2322, 0.2404, 1)` | Skill Points gauge component `@export` default |
| SP staked | `oklch(0.78 0.13 75)` | `Color(0.9084, 0.6684, 0.3042, 1)` | Skill Points gauge component `@export` default |
| SP allocated | `rgba(150,165,200,.30)` | `Color(0.588, 0.647, 0.784, 0.30)` | Skill Points gauge component `@export` default |

Conversion script (Björn Ottosson's OKLab formulas) used to derive these: `/tmp/.../oklch2srgb.py` in the session that authored this table — re-derive with the same math if more design colors need converting; don't eyeball new ones.
