---
description: UI color palette ("Arcane Terminal") — source of truth per stat, OKLCH→sRGB values
paths:
  - "stats_system/defs/*.tres"
  - "ui/hud/**"
  - "ui/theme/**"
  - "ui/frontmatter/**"
  - "ui/floating_number_layer/**"
  - "ui/announcement_layer/**"
---

# UI color palette ("Arcane Terminal")

Canonical colors from `docs/design/design_handoff_game_ui/README.md`, converted OKLCH → sRGB once at authoring time (Godot `Color` has no OKLCH constructor). Source of truth for attribute/vital colors is **`StatDef.tint_color`** on the matching `.tres` in `stats_system/defs/` — don't introduce a second palette resource for those. SP-bucket colors aren't per-stat (SkillPointStat is one pool with internal buckets), so they live as `@export` defaults on the Skill Points gauge component instead.

**Hero identity colour is a different axis and has its own resource** (#616): `ui/theme/player_palette.tres` — sixteen colours in two authored tiers (8 canonical brights, then 8 muted "second choice" colours for a roster that outgrows tier one) that the lobby hands out round-robin and a slot's picker overrides. Owner call 2026-09-02 retired #639's runtime `index * stride` walk in favour of baking the separation directly into the array's order — `PlayerPalette.default_for` is just `colors[index % size]` now. It is not a second copy of the stat palette (a hero colour answers "whose is this", not "which stat is this"), and two absences from it are load-bearing: **gold** (reserved, below) and **pure white** (`Participant.color` defaults to it, so `ProcgenPlaySandbox.resolve_spawn_color` uses it as the "nothing chosen" sentinel — a pickable white would silently spawn the level default). Both absences, plus pairwise OKLab separation (dE ≥ 0.14) for a 3- and 6-slot roster, are pinned by `test/unit/ui/test_lobby_roster.gd`.

`ui/theme/editor_swatches.tres` is a `ColorPicker` "save palette" convenience (recent/frequently-used swatches, including the six attribute colors above) — an editor quality-of-life file, not a second source of truth. Don't read values back out of it; read `StatDef.tint_color`.

| Name | OKLCH | sRGB `Color` | Where it lives |
|---|---|---|---|
| STR (Red) | `oklch(0.64 0.21 27)` | `Color(0.9451, 0.2689, 0.2453, 1)` | `stats_system/defs/strength.tres` |
| DEX (Green) | `oklch(0.74 0.16 150)` | `Color(0.3187, 0.7773, 0.4484, 1)` | `stats_system/defs/dexterity.tres` |
| INT (Blue) | `oklch(0.68 0.18 258)` | `Color(0.291, 0.5892, 1.0, 1)` | `stats_system/defs/intelligence.tres` |
| WIS (Gold) | `oklch(0.81 0.14 88)` | `Color(0.9039, 0.7331, 0.2746, 1)` | `stats_system/defs/wisdom.tres` |
| PER (Purple) | `oklch(0.66 0.21 305)` | `Color(0.6935, 0.4045, 0.9676, 1)` | `stats_system/defs/perception.tres` |
| CON (White) | `oklch(0.92 0.02 250)` | `Color(0.8586, 0.9018, 0.9482, 1)` | `stats_system/defs/constitution.tres` — **live since #269**; also the `ap_white` archetype color in `procgen/presets/first_level/first_level.tres` |
| Health (crimson) | `oklch(0.60 0.21 25)` | `Color(0.8878, 0.203, 0.2233, 1)` | `stats_system/defs/health.tres` |
| Mana (cyan) | `oklch(0.72 0.14 220)` | `Color(0.0, 0.72, 0.881, 1)` | `stats_system/defs/mana.tres` — was previously the same blue as INT; now differentiated |
| XP/gold | `oklch(0.80 0.14 88)` | `Color(0.8909, 0.7204, 0.2596, 1)` | `stats_system/defs/xp.tres` |
| SP to-spend | `oklch(0.70 0.16 250)` | `Color(0.2606, 0.6387, 0.9922, 1)` | Skill Points gauge component `@export` default |
| SP wounded | `oklch(0.60 0.20 25)` | `Color(0.8725, 0.2322, 0.2404, 1)` | Skill Points gauge component `@export` default |
| SP staked | `oklch(0.78 0.13 75)` | `Color(0.9084, 0.6684, 0.3042, 1)` | Skill Points gauge component `@export` default |
| SP allocated | `rgba(150,165,200,.30)` | `Color(0.588, 0.647, 0.784, 0.30)` | Skill Points gauge component `@export` default |
| Pool surplus (#152) | — (reuses SP-staked gold) | `Color(0.9084, 0.6684, 0.3042, 0.85)` | `SurplusPoolGauge.surplus_color` `@export` default + `pool_gauge.gdshader` uniform default |

## Gold is reserved for pure positives

**Gold means reward, never harm.** It is already spoken for twice — `FloaterStyles.modifier_core`'s mythic build-defining pickup and `xp_gain` — so a gold *damage* register reads as a jackpot at the moment something is being hurt, and dilutes the two registers that earned the colour.

Owner call, 2026-08-24, choosing the emissive-red crit toast over a gold one after seeing all three candidates side by side in the toast sandbox:

> *punch crit is beautiful, keep this one. indeed the gold is better reserved for pure positive*

**How to apply:** a "this is intense / rare / important" visual for something *bad* escalates on its own hue plus a second channel — emissive lift, size, and above all **motion** — never by borrowing gold. `FloaterStyles.crit` is the worked example: damage red lifted over the bloom threshold, with the intensity carried by the entry animation in `CritPunchToast`.

**Documented carve-out: a critical Healing Beam is gold.** Owner call, 2026-08-30, on issue #675: *"a critical heal is the one unambiguous reward in the spell book and the only earned claim on gold, while crit-red keeps meaning damage everywhere else."* Every other spell's crit stays on the uniform crit-red grammar (#663 D6); Healing Beam's `ImpactRing.crit_color` is set to the XP/gold value above (`Color(0.8909, 0.7204, 0.2596, 1)`) instead, escalating through the same ring-count/PEAK-core grammar as every other crit. This is the one and only sanctioned gold-on-harm-adjacent-but-actually-reward exception — do not generalize it to another spell's crit without a fresh owner call.

Conversion script (Björn Ottosson's OKLab formulas) used to derive these: `/tmp/.../oklch2srgb.py` in the session that authored this table — re-derive with the same math if more design colors need converting; don't eyeball new ones.
