# The determinism probe (#529)

**This produces a number, not a feature.** It exists to settle #463's open
question — confirm-down versus lockstep + snapshot recovery — by measurement
instead of another round of argument. `docs/handoffs/lan-versus-transport.md`
is why the question was open; `docs/domain/multiplayer-sync-model.md` is the
architecture it serves.

| Piece | Where |
|---|---|
| The probe | `network/determinism_probe.gd` |
| Its three hooks | `network/command_link.gd` (`_on_remote_command`) |
| The `--probe` flag + readout | `scenes/dev/mp_dev_sandbox.gd` |
| The tab toggle | `addons/mp_sandbox/mp_sandbox_panel.tscn` |

## Running it

From a terminal — the host sweeps, the client measures:

```
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host   --port=9099 --autopilot --turns=30
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099 --autopilot --probe
```

**`--autopilot` on the client line is not a typo.** Only the host sweeps, but
the flag also gates Red's budget boost, which must match on both peers or the
first budget-gated verb desyncs — see
[multiplayer-harness.md](multiplayer-harness.md). `--turns` stays host-only.

**`--turns` is not optional for a measurement.** One sweep is ~17 commands and
then the loop stalls on Red waiting for input that never comes in headless. The
issue asks for a few hundred, so ask for the turns.

Or tick both boxes on the sandbox host's **Multiplayer** tab and Launch both.
**The breakdown prints in the CLIENT window**, not the launcher's log —
`--probe` on a host is a no-op that says so, because a host receives no command
to re-derive.

The readout fires on a `PROBE_REPORT_PERIOD_SECONDS` heartbeat **and** after
`PROBE_REPORT_QUIET_SECONDS` of silence on the wire. Quiet alone was the
original design and it silently failed: under `--turns` the sweeps run back to
back, the wire never goes quiet, and a ten-minute measured run printed its last
table two minutes in. The heartbeat means the table is never more than a period
stale and killing the process costs at most one period. Quiet stays because it
prints *promptly* when a sweep — or a human clicking — stops.

## Two questions, tallied apart

**WORLD — do the two worlds agree?** This is `WorldFingerprint.compute`, which
`CommandLink` already compared; the probe only attributes each verdict to the
command type that produced it. Columns: `ok / DIVERGED / skipped / exempt`.

Since #540 the comparison is **pre-state against pre-state**, not post-apply:
the host stamps `Command.pre_fingerprint` when the command leaves its queue and
ships that, and the peer compares against its own world at
`_on_remote_command` entry, *before* it submits. It had to move — once the
authority confirms *before* it applies, there is no post-mutation world to
sample at confirm time. The honest cost is that a divergence is attributed to
the command *after* the one that caused it, and a run's final command is never
compared at all; if you need the last one, compare once explicitly at
end of sweep.

**RESOLVE — could this peer have DERIVED the host's result?** Only
`LaunchAttackCommand` can be asked: it is the one verb carrying both the inputs
(the plan, and `resolve_seed`) and the host's result (an `AttackRecord`). Every
other verb carries intent only, so "re-resolving" one is just applying it and
the WORLD column is the whole answer. The peer rebuilds the plan through
`AttackPlanCodec`, stamps the same seed, calls `resolve()`, re-encodes through
the same `AttackRecord.capture` the host used, and diffs. Columns:
`ok / DIVERGED / unavailable / landings re-derived`.

**`landings re-derived` is what makes that row a measurement.** "5 attacks, 0
diverged" is vacuous if all five resolved to zero hits — two empty arrays match
trivially. An attack that produced no landings agrees for free and proves
nothing, so the hit count is reported beside the verdict rather than left for
the reader to assume.

Nothing mutates. `BattleSystem._resolve_for_launch` documents that "nothing
below `resolve()` mutates"; the plan built here is local and is never assigned
to `battle_system.attack_plan`.

## The partition, and why it is the whole design

`AttackRecord`'s class note is explicit that **a client cannot re-derive a
combat number** — mitigation is read node-locally at land time, an earlier
beat's cascade changes what a later beat lands on, and a fogged target may not
be held at all. So diffing the whole record reports 100% divergence for
structural reasons and the number means nothing.

| Compared (resolve-stage) | Not compared (land-time) |
|---|---|
| `seed`, `ap`, `mana` | `h_amt` — post-`Mitigation` effective damage |
| `h_tgt`, `h_org`, `h_atk` | `h_kind` — reclassified to HEAL on a `min_damage_taken` underflow |
| `h_at` (arrival clock) | `h_hp0` / `h_hp1` / `h_hpm` |
| `h_crit` + the `FLAG_CRIT` bit | the `FLAG_GATED` bit (#503, decided at land) |
| the whole timeline (`e_*`) | every `d_*` — the forced-dealloc sets |

`h_flags` is split, not skipped: the crit bit is a **seeded roll** and a peer
disagreeing about it is a real determinism failure, while `FLAG_GATED` shares
the byte and is land-time. `DeterminismProbe._crit_bits` masks accordingly.

So **a clean RESOLVE column does not say "lockstep needs no record".** It says
the hit **set**, **order** and **timeline** are reproducible — precisely the
half #530's stable hitscan sort was a prerequisite for. The report prints this
scope in its own footer, because the owner is making a model decision off it.

## `skipped` is the honest denominator, not a pass

`CommandLink._on_remote_command` deliberately suppresses the fingerprint compare
when the applier's queue is non-empty at the moment the command arrives — a peer
that is somewhere *inside* an earlier command is not at any command's boundary,
so comparing would report a divergence that never happened. A spurious ✗ poisons
the only diagnostic this harness has. That guard is correct and stays.

But it means a share of commands is **never compared**, and "0 diverged of 412"
handed to the owner while only 280 were looked at is a false clean read. They are
counted as `skipped`.

**#540 cut this substantially by moving the compare ahead of the mutation.** The
old post-apply compare had to survive its own `await`, so it also lost to any
command that arrived meanwhile (a `_recv_seq` supersede check, now deleted) —
which hit the long-running verbs hardest. Measured over the same autopilot sweep,
`launch_attack` went from 17 skipped of 31 to **3 of 31**. Note the totals move
less than that suggests: the compare shifted from the *last* command of a burst
to the *first*, which redistributes skips between verbs rather than only removing
them (`allocate` went 4 → 9 over the same run).

## `exempt` is the model working

`.claude/rules/multiplayer-sync.md` carves host-only rolls out: "never roll
unseeded for a result a peer must *reproduce* rather than receive; host-only
rolls (loot) are exempt." `LootRoundCommand` carries what was granted **by
value** for exactly that reason. It gets its own column so a real mismatch is
never buried under an expected one.

## Adding a verb to the RESOLVE column

Only if the verb's wire form carries **both** its inputs and the host's derived
result. If it carries intent only, there is nothing to compare and adding it
would just re-count the WORLD column. If it carries a result with no inputs,
the honest answer is `unavailable`, not agreement.
