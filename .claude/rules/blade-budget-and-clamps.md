---
paths:
  - "attack/plan/melee_attack_plan.gd"
  - "attack/melee/**"
  - "entity/controller/ai_*.gd"
  - "skill_node/addons/clamp_addon.gd"
  - "skill_node/addons/spike_ring_addon.gd"
---

# The blade budget, and how clamps actually make a weapon

## One budget, three things to spend it on

`blade_size` (read node-locally off the **pivot**) is a single budget shared between blade members *and* temp upgrades — `melee_attack_plan.gd`: *"a temp upgrade is a REAL SkillNodeAddon, `add_child`ed exactly like a permanent one (marked `is_temporary`), spent from the same blade_size budget as blade_nodes."*

| spend | cost |
|---|---|
| a plain member | 1 |
| `CLAMP_UPGRADE` | 1 |
| `SPIKE_UPGRADE` | 2 |

**Why:** it is easy to read "clamp node" as a persistent, cross-turn structural investment — #771 was filed on exactly that assumption. It is not. A clamp is a per-swing choice competing directly with one more member of reach, and it is refunded when the plan resets.

**How to apply:** any budget reasoning — AI or UI — must charge upgrades and members against the same `_budget_remaining()`. `blade_size = 1 + STR/20` (base STR 10), so a starting entity has a budget of **2**, and one clamp is half the weapon.

## Clamps compound only when CONSECUTIVE from the pivot

`build_drivers` creates one arc driver per edge **incident to the pivot** — the driven set is radius 1 and fixed. Everything beyond is dragged by distance constraints.

`ClampAddon.append_weld_braces` braces the *neighbours* of the clamped particle. So for `(Pivot)---(C)---(N1)---(N2)`:

- clamp on **C** braces Pivot–N1, making the triangle Pivot-C-N1 rigid, so the pivot's radius-1 driver now effectively drives **N1** at a larger arc radius — greater tangential speed;
- clamp on **N1** too braces C–N2, and the rigid body reaches **N2**, faster still.

**Why:** this is the mechanic behind "a long rigid handle makes the tip fast", and it looks like it should work anywhere on the blade. It does not. A clamp on N2 while N1 is unclamped extends the driven body by **nothing** — it merely stiffens a mid-blade joint.

**How to apply:** to lengthen the driven handle, clamp outward from the pivot with no gaps. A joint already part of a triangle is rigid for free; a node already carrying a procgen `ClampAddon` is rigid for free. Spending on either is a wasted budget point, and `SkillNode.can_attach_addon` will refuse anyway once slots are full (`addon_slots == stake_level`, base 0 — a level-1 node has exactly one slot).

## Scoring a hypothetical clamp needs no board mutation

`ClampAddon.append_weld_braces(state, particle_idx)` is **static** and takes only `(BladeState, int)` — extracted, per its own docstring, *"so ClampAddon.apply_to_blade and any other caller building the same brace geometry share one implementation."* Call it on a built state to score a phantom clamp. Never attach and detach a real addon to evaluate a candidate.

Carry a phantom set as transient plan state, not as a `build_blade_state` parameter: `_resolve_and_score` runs `plan.resolve()`, which builds its own state internally, so a parameter reaches the coarse tier and not the finalist one.
