# Relay — charter

The design behind `.claude/skills/relay/SKILL.md`. The skill is derived from
this; change the wish here, then re-derive the file. See [README](README.md)
for the protocol. Sibling charters: [swarm](swarm.md) (whose cycle relay
runs, unchanged, with one drone in flight), [drone](drone.md) (the leaf a
relay dispatches), [warp](warp.md) (the single-issue cycle each unit is).

This charter was **mined from the working skill, not designed fresh**, on the
warp protocol: every paragraph of the skill maps to a law below, and no
behaviour changed in the mining. The skill had already shrunk to a pointer
when swarm absorbed the merge token; what remained was its trigger text, the
three deltas from swarm at wave size 1, and two dated facts that belonged
here.

## What relay is for

Relay is **swarm at wave size 1**: the owner names several `Ready` issues to
land in sequence ("#A → #B → #C as Sonnet warps", "relay these") and one
session drives them through one `drone` at a time — brief, wait, review,
land, next. It exists as its own skill for its trigger: a serial chain is a
different ask from a wave, and a lead that reaches for `swarm` on a chain
will size a wave. Everything past the trigger is swarm's protocol — the
bare-number brief, the tier tag, `mise run land`, the once-per-train suite,
the push — read there and run here with one drone in flight.

## The cost model

One lead, one drone, two wakes per unit. With a single drone in flight the
lead's context grows only by its own reviews and landings, and there is no
sibling traffic to compound it — so the lead *is* the cheap reviewer, and a
Sage seat (≈ 20–25k Fable per unit, swarm's figure) has no wave of drone
questions to amortise against. Landing from the lead's own context costs a
`--stat`, a diff, and one `land` invocation; a Sage would cost the same diff
read plus its seat. The break-even is a chain long or design-heavy enough
that the drones' questions would otherwise land on the lead — that is the
only trigger for spawning one.

Ordering is the other cost: a chain's only planning question is which
issues touch the same files, and a Haiku `Explore` answers it in one leaf
call, cheaper than the lead reading any of them.

## Laws

1. **Restate nothing of swarm.** Relay runs swarm's cycle with one drone in
   flight; the skill body is a pointer to `swarm` plus the deltas below,
   and it does not re-grow. A lesson learned on a relay is filed where it
   binds — drone-side rules in the `drone` agent, the merge token in
   `mise run land`, review proportionality and the final-suite baseline in
   `swarm` — never in the relay skill.
2. **The Sage seat is optional; the lead reviews and lands.** Read
   `--stat`, then the diff, and run `mise run land -- <branch> --closes <n>`
   from the lead's own context. Spawn a Sage only when the chain is long or
   design-heavy enough that the drones' questions would otherwise land on
   the lead.
3. **Ordering is the DAG.** One Haiku `Explore` answers which issues touch
   the same files; that ordering is the whole plan.
4. **Every issue closes as it lands.** `land --closes` on every branch,
   since in a chain every branch is the last for its issue.

### Mined from

| Skill paragraph (pre-patch) | Law |
|---|---|
| frontmatter description — trigger text, "swarm at wave size 1 — the body is a pointer" | what for, 1 |
| "Folded into swarm … this file no longer restates any of it" | 1 |
| bullet "The Sage seat is optional" | 2 |
| bullet "Ordering is the DAG" | 3 |
| bullet "Each issue closes as it lands" | 4 |
| "What the … chain taught now lives where it binds … Do not re-grow this file" | 1 |

## Incident corpus

| Date | Where | What happened | Law |
|---|---|---|---|
| 2026-09-03 | chain #737 → #727 → #746 → #736 → #743 | five issues landed in ~5h as Sonnet warps; lead 218k, drones 111k–222k — the run that proved the serial shape and set the drone baseline (its drone-side row is in [drone](drone.md)'s corpus; cited, not duplicated) | 1, 2 |
| 2026-09-11 | #857 | the merge token mechanised as `mise run land` and relay folded into swarm as wave size 1; the skill became a pointer plus three deltas | 1, 2, 4 |
| 2026-09-21 | #1021 | owner: "relay needs a charter, relief too" — mined from the file per the warp protocol; the two dated facts above left the skill for this table | all |

## What the skill must not contain

- Any row above, any issue number, any date — including the fold-in date
  and the chain that proved the shape.
- Any restatement of swarm's cycle: the brief format, the tier tag, the
  merge token, the suite gate, the push. One pointer, three deltas.
- Any restatement of drone-side rules; they live in the `drone` agent.

## Open follow-ups

- Whether the three deltas belong as a "wave size 1" clause inside swarm's
  laws instead, retiring relay's skill body entirely — asked only if
  relay's trigger stops being used.
