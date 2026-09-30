---
id: 0035
title: An attack plan, temp upgrades included, is seat-local until launch; the host judges it once in LaunchAttackCommand and checks only that the player can pay
status: accepted
date: 2026-09-30
deciders: owner
supersedes: []
superseded-by: null
revisit-when: "Plan-building rules start affecting other players before launch (e.g. temp addons visible to opponents while planning)"
sources:
  - "#1240"
  - "#1220"
  - "command/launch_attack_command.gd"
  - "command/toggle_temp_upgrade_command.gd"
  - "docs/domain/multiplayer-sync-model.md"
tags: [multiplayer, sync, attack]
---

# ADR 0035 — A plan is seat-local until launch; the host checks only affordability

## Context

Under host-authoritative sync (ADR 0002), a player's attack plan crosses the wire only as `LaunchAttackCommand.plan`. Temp upgrades were the exception: each toggle was its own `ToggleTempUpgradeCommand`, and the host checked it against its own `AttackPlanSlot`. That slot is empty whenever a non-host player is the one building the plan, so their toggles were refused. The plan's wire form did not carry temp upgrades at all.

## Decision drivers

- Local state is much cheaper to change than state kept in sync across the wire.
- A diverged board fails at submit time whatever the plan contains, blade node or upgrade alike.
- One point where the host judges, not one per edit.

## Decision

- "plans are purely local. players can do whatever, and at submit time host is like 'nah' or 'ok, this and that happens now', kinda intentional to keep things more manageable (seat local state manipulation is much easier than communicating everything across the wire)" (owner, 2026-09-30)
- "not sure if the host would need to validate toggles of temp upgrades. as much as it needs to validate which nodes you pick in your blade or which direction the swing goes." (owner, 2026-09-30)
- "host needs to check the launching player can pay the cost for blade nodes (blade size) and upgrades ( also blade size, other costs [soon]), besides that not much to do" (owner, 2026-09-30)

## Consequences

- Temp upgrades are plan content and ride the launch. `ToggleTempUpgradeCommand` has no reason to exist.
- The host's launch check is one affordability total that new cost types join. Plan-building rules (membership, adjacency, where an upgrade sits) are enforced only while planning, on the seat.
- A temporary addon during planning is a preview on the planning seat only.
- On a diverged board, whatever the replay does with the recorded plan is the outcome; nothing refuses it earlier.

## Alternatives considered

### A command per plan edit, checked by the host (the `ToggleTempUpgradeCommand` shape)
Lost on "local is cheap" and "one point where the host judges": the host needs the in-progress plan, which only the planning seat holds. **Most likely to be revived** if opponents must see temp addons before launch.

### The host re-runs every plan-building rule at launch
Lost on the owner's "besides that not much to do". It duplicates local rules for a divergence case that fails at submit time anyway.
