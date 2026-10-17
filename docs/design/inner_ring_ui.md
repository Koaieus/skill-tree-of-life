---
status: exploring
---

# Inner ring — feature brief (UI/UX)

A feature brief in the shape product teams use before a surface is built:
problem, goals and non-goals, who uses it and when, user stories each with
acceptance criteria, states, constraints, counter-considerations, open
questions. Fill the `?` cells before promoting anything to `Ready`; a
`/swarmify` pass on #1652 fleshes this out with the owner and splits it. The
skeleton is reusable for any new surface — copy the headings.

What the ring *is* (data, points, spending) is settled on #199 and built by
#1651; this brief is only the surface the player sees and touches.

## 1. Problem

An entity earns ring points every few levels and spends them on cells of an
inner aspect ring. The player needs to notice a point arrived, find the ring,
understand what each cell does and what it needs, buy with confidence, and
see at a glance what they have become. Today none of that surface exists; the
HUD shows a level-up banner only.

## 2. Goals / non-goals

**Goals**
- A point is never lost or forgotten: the player always knows unspent points
  exist and where to spend them.
- The ring is legible from across the room: which sector, which spoke, how
  deep, in under a second.
- Buying is a two-click act with no regret: what the cell grants and what it
  needs is readable before the click.
- The hero's identity ("I am Rot") reads on the hero itself, not only inside
  the ring.

**Non-goals**
- Designing T3 signatures or opposition (#1653).
- Per-class bespoke rings (a later `RingDef` per CoreClass).
- Showing an NPC's ring in full (see info gating, story 7).
- Respec / refund.

## 3. Who, when, where

| who | when | where |
|---|---|---|
| local player | a point mints mid-turn; between actions; while planning | the HUD, in-run |
| local player, idle | wants to review the build | the hero portrait, top-left |
| a LAN peer | watches an ally/enemy level | their own HUD; sees only what gating allows |
| an NPC | never | auto-spends through the same command (#1651) |

## 4. User stories (each with acceptance criteria)

Written as *As a … I want … so that …*, criteria as *Given / When / Then*.
`?` marks an owner call.

**S1 — Notice.** As the player I want to know a ring point arrived so I never
sit on unspent points.
- Given a point mints on my level-up, when the LEVEL UP beat plays, then the
  hero portrait shows an unspent-points badge and the banner names it.
- Given unspent points, when my turn starts, then the badge is still there
  (no nag, no modal) — `?` or does mint raise the ring immediately, as the
  loot picker does for a kill?

**S2 — Open.** As the player I want to open the ring from my hero so the entry
point is where my identity already lives.
- Given the hero portrait top-left, when I click it, then the ring opens as a
  full-screen modal (rule `modal-system`: through `_enqueue_modal`, never
  paused), over the board, with the board still visible dimmed `?`.
- Given the ring is open, when I press Escape or the close control, then it
  closes and my points stay.

**S3 — Read.** As the player I want the ring to read at a glance so I know
what I am and what is near.
- Given the ring, then six sectors sit on a rim in the authored order, each
  labelled by its attribute, each aspect spoke tinted its own `Identity.tint`
  (aspect hue is its own, never the school's — `aspect_matrix.md` §Schools).
- Then bought cells glow (a named `Emissive` tier, never a hand-picked
  float), buyable cells are lit and reachable, locked cells are dim with their
  unmet requirement visible on hover.
- Then links and cross-links draw as edges; a keystone cell reads as a
  landmark (same emblem language as a keystone on the board).

**S4 — Understand a cell.** As the player I want a cell's grant and
requirement before I buy.
- Given any cell, when I hover or select it, then a tooltip shows: the
  aspect's name and glyph, the exact grant (+1 poison aspect / +1 poison
  stacks per hit / the keystone's modifiers), its cost, and the requirement
  (`requires_all` / `requires_any`) with met ones ticked.
- Then the status line names why a locked cell is locked in one sentence.

**S5 — Buy.** As the player I want buying to be deliberate but quick.
- Given a buyable cell selected and points ≥ cost, when I confirm, then one
  `SpendRingCellCommand` is submitted, the cell flips to bought with a short
  flourish, points decrement, and neighbours re-evaluate to buyable.
- Given points left, then the ring stays open; given none, `?` it closes or
  stays.
- Given a peer-hosted game, then the buy round-trips the host like a loot pick
  and the cell shows a pending state until confirmed.

**S6 — Wear it.** As the player I want my build visible on my hero.
- Given bought cells, then the hero portrait shows the dominant sector's hue
  and/or the deepest aspects' glyphs `?`; a spoke at T2 shows differently from
  T1.

**S7 — Inspect others.** As the player I want to read an enemy's identity
without seeing their whole ring.
- Given a hostile entity, when I inspect it, then I see at most the sector
  hues and tier counts `?` (per `info_gating.md`); never their unspent points.

**S8 — Input.** As a keyboard/gamepad player I want the ring navigable.
- Given focus in the ring, then arrows/D-pad move along links; confirm buys;
  cancel closes. `?` gamepad in scope now or later.

## 5. Flow

```
level-up  ─▶ badge on portrait ─▶ click portrait ─▶ ring modal
                                          │            ├─ hover cell → tooltip + status
                                          │            ├─ select buyable → confirm → bought (+ flourish)
                                          │            └─ close → board
mint (if S1 says so) ───────────────────▶ ring modal (same body)
```

## 6. States

| thing | states |
|---|---|
| portrait badge | hidden · n unspent · (pulse on mint) |
| cell | locked · buyable · unaffordable · bought · pending (MP) · selected · hovered |
| link | inactive · active (both ends bought) · path-to-selected |
| sector | none bought · partial · hub (keystone) bought |
| ring body | populated · empty (no points, read-only) · remote (peer's, gated) |

## 7. Constraints already in the code

- Modal: inherited `ui/modal/modal_base.tscn` + a `ModalBodyBase` body;
  queued through `HudRoot._enqueue_modal`; never `get_tree().paused`.
- Glow: named `Emissive` tiers only (`docs/domain/hdr-color.md`).
- Draw cost: 30 cells + links is trivial, but per-cell materials are not —
  tint by `modulate` (`docs/domain/rendering-performance.md`).
- Spending is a command (host-authoritative), so the UI never mutates state;
  it submits and reflects.
- Aspect hues and glyphs come from `identity/defs/*.tres`; sector order from
  the `RingDef` (#1651). Nothing in the UI hardcodes either.
- A live sandbox-host tab is the tuning surface before a run exists.

## 8. Counter-considerations

- **Interruption.** A modal on every mint breaks the turn's flow; a badge
  alone risks forgotten points. The loot picker already interrupts on kills,
  so a second interrupter compounds. Lean: badge + banner, modal on click.
- **Choice load.** 30 cells with 1–3 points is a lot of surface for a small
  choice; the ring must guide (buyable cells lit, the rest quiet) or it reads
  as a wall.
- **Colour collisions.** Aspect hues are settled as their own, so school and
  aspect may clash (Corruption and PER both purple); sector labels carry the
  school, hue never does.
- **Portrait overload.** The portrait already carries class sigil, colour,
  HP; adding a build read risks mush. Story S6 may want the ring's *silhouette*
  rather than glyphs.
- **Peer fidelity.** Showing a peer's ring means replicating spent sets
  under fog — bins not values (#519).
- **Scope.** This is many units, not one: renderer (sandbox tab first),
  portrait badge + hook, modal shell, cell tooltip/status, buy flow + MP
  pending, hero read (S6), inspect-others (S7), input (S8).

## 9. Open questions (owner)

1. Mint raises the ring, or badge-only until clicked? (S1)
2. Board visible dimmed behind the ring, or full cover? (S2)
3. What the hero portrait shows of the build — hue, glyphs, silhouette? (S6)
4. How much of an enemy's ring is readable? (S7)
5. Gamepad now or later? (S8)
6. Ring stays open after the last point or closes? (S5)

## 10. Reading list

`docs/design/inner_tree_and_stake_economy.md` §2 (the ring) ·
`docs/domain/modal-system.md` · `docs/design/info_gating.md` ·
`docs/design/aspect_matrix.md` §Schools · `docs/domain/hdr-color.md` ·
`ui/loot_picker/` (the one mid-run choice modal that exists) · #1651 (the data
and the command this surface drives).
