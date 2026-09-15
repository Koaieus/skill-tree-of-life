# Handoff — swarmify charter (upstream discovery)

Written against `adc4ef4` + this commit, 2026-09-15. Authoritative homes: **#902**
(the full brief — read it first), `docs/charters/drone.md` (what the drone side
now is, and its open follow-ups), `docs/charters/README.md` (the convention).
This file only orders the work and names couplings.

## State

- Done this session: `/drone` skill → `.claude/agents/drone.md` derived from
  `docs/charters/drone.md`; `mise run agent-cost` (Σctx×turns, printed by
  `land`); `drone-budget-guard` allows the successor brief past 300k;
  warp-vs-drone audit verdict recorded on the charter (per-file parity; the
  cost is coordination + fragmentation, not method).
- The `drone` agent type is live but **has not run a unit yet.**

## Take first, in this order

1. **#902 — swarmify charter.** The brief is complete; it is a `swarmify`
   pass on itself. Deliverables listed on the issue (charter → re-derived
   skill → Ready-comment template → `issue-drift` task → swarm dispatch clip).
   Coupling: the *stubs-on-master* section changes what "Ready" means for
   class-adding issues — settle whether that is a hard requirement or a
   swarmify judgement call before writing the law.
2. **Drone smoke test** (charter follow-up): one haiku `drone` on a trivial
   fenced task. It doubles as the check of an unverified premise — that a
   typed subagent receives CLAUDE.md + always-on rules. If it does not, ~10
   lines (test ladder, red-green, long-running) go back into the agent body.
   Do this before the first real swarm on the new type.
3. **Sage vs `advisor`** (charter follow-up, owner call): trial `advisor` as
   the named advisor on the next relay; compare `agent-cost` per landed unit
   against a Sage run. The agent file already lets the brief decide.
4. `swarm` charter treatment — out of scope of #902, noted there.

## Live numbers

- Today's #896 drone: Σctx 10.2M / eff 1.44M / 91 turns; the Sonnet audit
  agent: 1.37M / 325k / 25 turns (`mise run agent-cost -- --latest 3`).
- Budget markers: 150k/200k/250k; guard hard stop 300k; drone retires at 250k.

Delete this file once #902 is `Ready` and the smoke test has run.
