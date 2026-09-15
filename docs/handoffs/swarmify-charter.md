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

1. **#902 — DONE as a swarmify pass (2026-09-15).** Charter at
   `docs/charters/swarmify.md` (a1ebc3d); hub comment on #902 carries the
   owner calls + DAG. Three `Ready` children: #905 (re-derive skill +
   template), #903 (`issue-drift` + selftest), #904 (swarm clip, blocked by
   #903). #905 ∥ #903, then #904 — a relay or a two-wave swarm. They are the
   first issues written *under* the charter (stamped reading lists, seam
   maps) — note whether the drones use them.
2. **Drone smoke test — DONE 2026-09-15** (7f548a8): premise true, starts on
   its prompt, sees CLAUDE.md; nothing goes back into the agent body.
3. **Sage vs `advisor`** (charter follow-up, owner call): trial `advisor` as
   the named advisor on the next relay; compare `agent-cost` per landed unit
   against a Sage run. The agent file already lets the brief decide.
4. **#906 — DONE 2026-09-15.** `docs/charters/swarm.md` + skill re-derived
   (414b93e); Sage never lands; drones get `advisor` once-early. The next
   swarm/relay is the first run of all three charters together — ledger
   the idle count, advisor calls and `priced` per unit; the open
   experiments (deliberate `/compact` with a drone in flight, advisor
   caching) are on the charter.

## Live numbers

- Today's #896 drone: Σctx 10.2M / eff 1.44M / 91 turns; the Sonnet audit
  agent: 1.37M / 325k / 25 turns (`mise run agent-cost -- --latest 3`).
- Budget markers: 150k/200k/250k; guard hard stop 300k; drone retires at 250k.

Delete this file once #903–#905 have landed.
