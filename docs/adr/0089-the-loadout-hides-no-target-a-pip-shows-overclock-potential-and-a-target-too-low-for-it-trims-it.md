---
id: 0089
title: The loadout hides no target — each target an overqualified caster reaches shows a "+N" pip; once a target is picked the forge knows the range of overqualification among the nodes that can fire at it, and picking one whose best cap is below the loadout trims the loadout to that cap one-shot, with a notice, the target looking muted; a point past the source's cap re-picks a non-aimed spell's source and is refused by an aimed one, whose set aim locks the caster; every AI tier fills to the base cap and overclocking is a habit from FIGHTER up — supersedes 0085 §4's "targets light up for those alone" in part
status: accepted
date: 2026-11-11
deciders: owner
supersedes: [0085]
superseded-by: null
revisit-when: "a trim forced by picking a low-cap target surprises players more than a hidden target did, or the base-cap fill leaves the low AI tiers too weak against an overclocking player"
sources:
  - "#1716"
  - "#1814"
  - "docs/design/elements.md"
  - "docs/adr/0085-the-forge-has-three-kinds-of-slot-and-a-spells-point-cap-grows-with-the-caster-nodes-degree.md"
  - "entity/controller/ai_controller.gd"
tags: [elements, infusion, forge, targeting, spells, ai, ui]
---

# ADR 0089 — The loadout hides no target

## Context
ADR 0085 §4 (2026-11-10) made a loadout of P points act as a higher `min_degree`: the target union admitted only the sources whose capacity carried it, targets lit up for those alone, so a heavier loadout reached fewer targets, and a point added after the pick re-picked the source or the socket refused it. Its own `revisit-when` named the risk of hidden targets reading badly in play. Most spells have no aiming step; the aimed ones (one or two so far) confirm their source through the aim. The AI ladder (`entity/controller/ai_controller.gd:74`) switches habits on per tier (BRAWLER, FIGHTER, TACTICIAN, WARLORD) and never weighs a trick harder. Nothing elemental is built.

## Decision drivers
- **The loadout never hides a target:** what a spell can hit does not shrink with what is socketed.
- **Overclock potential is shown, not discovered:** the player sees where extra points can go.
- **The loadout is the player's** (ADR 0085): a change to it is never silent.
- **Aiming confirms the source; a non-aimed spell's source was never hand-picked.**
- **An AI tier adds habits, never weight** (the ladder's rule).

## Decision
1. **The loadout hides no target** (owner, 2026-11-11: *"hiding casters also hides targets and *those* we don't wanna hide. But we do want to indicate potential to overclock it."*, and *"And "hide no targets" mostly applies to when no target is picked yet (just the spell)."*). While no target is picked, every node the spell's eligible casters reach is a target, whatever the loadout.
2. **A "+N" pip on each target an overqualified caster reaches** (owner, 2026-11-11, picked *pip on targets*: *"Pip on target."*): N is its cap above base from the best caster reaching it, red when the loadout is above it, still pickable.
3. **Once a target is picked, the forge knows the range of overqualification among the nodes that can fire at it** (owner, 2026-11-11: *"When target is picked we know the full range of overqualification amongst the nodes that can fire at it."*).
4. **Picking a target whose best cap is below the loadout trims the loadout to that cap**, one-shot, in the forge's trim order, with a notice (owner, 2026-11-11, picked *trim to its cap*), and that target looks muted (*"Option 1. This means that "target" should look different too. Like secondary or muted or "not using your full spec""*).
5. **A point past the source's cap: a non-aimed spell re-picks its source, an aimed one refuses the point** (owner, 2026-11-11, ticked *aimed spell refuses extra*: *"most spells use no aiming step and repicking is non invasive (they weren't hand picking the source anyway)"*; *"aiming does implicitly confirm the source"*). **An aimed cast with its aim set locks the caster** (owner, 2026-11-11: *"In case of an *aimed* cast and the aim is set, the caster is locked (while aiming the projected area snaps to casters)"*).
6. **The AI overclocks by habit** (owner, 2026-11-11, picked *overclock is a habit*): every tier fills a loadout to the base cap; filling past base to the source's cap, and preferring an overqualified caster, switches on at FIGHTER and up.

**Falls:** 0085 §4's *"targets light up for those alone"*; its consequence *"A heavier loadout reaches fewer targets … and a loadout no owned node can carry has no targets at all"*; §4's re-pick for an aimed spell. **Stands:** 0085 §1–§3; §4's loadout as a higher `min_degree` for the source, the pick among the casters that carry it staying the highest node-local `spell_damage`, and the socket refusing a point no caster can carry.

## Consequences
- Whether a node is a target no longer depends on the loadout; its pip, the pip's colour and the source pick still do.
- A heavy loadout costs no reach: it meets a target that cannot carry it as a visible trim and a muted target, never a vanished one.
- An aimed cast's source is fixed by its aim, so a socket write never moves it; a non-aimed cast's source may move as points are added.
- Low AI tiers never cast past base; overclocking joins the habits a tier switches on, beside FIGHTER's cut-vertex.

## Alternatives considered
### Hide the targets no caster can carry (ADR 0085 §4 as it stood)
Lost on *the loadout never hides a target* (owner, 2026-11-11).
### Re-pick the source for an aimed spell too
Lost on *aiming confirms the source*: the aim is the player's pick of the caster.
### Refuse the extra point for every spell
Lost on *a non-aimed spell's source was never hand-picked*: re-picking it costs the player nothing.
### Clamp the loadout to the picked source's cap on every pick (0085's rejected alternative)
Lost again on *the loadout is the player's*. The trim of §4 is its narrow form: only when the picked target's best cap is below the loadout, said with a notice and shown on the target.
### Every AI tier fills to its source's cap (the reading before the pick)
Lost on *an AI tier adds habits, never weight*. **Most likely to be revived** if the low tiers prove too weak; the owner's first framing was *"Tough AI should spend most points use all their budgets etc, easy AI might underspend or leave slots open idk"*.
