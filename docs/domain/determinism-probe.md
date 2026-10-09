# The determinism probe

A permanent **desync canary**, not a feature: the cheapest signal that a peer and the
authority have stopped agreeing. The sync model it serves is settled in
[ADR 0002](../adr/0002-host-authoritative-sync-not-lockstep.md) (architecture:
`docs/domain/multiplayer-sync-model.md`); because the probe asks whether a peer
*could* have derived what it received, it also keeps the lockstep door open at
near-zero cost without the wire depending on it.

**Read the scope before quoting a clean run.** A clean run on one machine, one
binary, one libm measures *pipeline order*, not floating-point portability.

| Piece | Where |
|---|---|
| The probe | `network/determinism_probe.gd` |
| Its hooks | `network/command_channel.gd` (`_on_remote_command`, `_on_command_stamped`) and `network/world_sync_channel.gd` (the compare) |
| The `--probe` flag + readout | `scenes/dev/mp_dev_sandbox.gd` |
| The tab toggle | `addons/mp_sandbox/mp_sandbox_panel.tscn` |

## Running it

From a terminal — the host sweeps, the client measures:

```
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=host   --port=9109 --autopilot --turns=30
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9109 --autopilot --probe
```

**9099, the default, works too** — a host that cannot bind exits non-zero and says
which port is taken. Different ports are convenient for running two measurements at
once. **Launch both processes
from the same checkout at the same commit**: peers on different shas refuse to
link, but the stamp cannot see uncommitted edits — see
[multiplayer-harness.md](multiplayer-harness.md).

**`--autopilot` on the client line is not a typo.** Only the host sweeps, but
the flag also gates Red's budget boost, which must match on both peers or the
first budget-gated verb desyncs — see
[multiplayer-harness.md](multiplayer-harness.md). `--turns` stays host-only.

**`--turns` is not optional for a measurement.** One sweep is ~17 commands and
then the loop stalls on Red waiting for input that never comes in headless. Ask for a
few hundred turns.

Or tick both boxes on the sandbox host's **Multiplayer** tab and Launch both.
**The breakdown prints in the CLIENT window**, not the launcher's log —
`--probe` on a host is a no-op that says so, because a host receives no command
to re-derive.

The readout fires on a `PROBE_REPORT_PERIOD_SECONDS` heartbeat **and** after
`PROBE_REPORT_QUIET_SECONDS` of silence on the wire. The heartbeat is required: under
`--turns` the sweeps run back to back and the wire never goes quiet. It bounds the
table's staleness to one period; quiet prints *promptly* when a sweep — or a human
clicking — stops.

## Three questions, tallied apart

**WORLD — do the two worlds agree?** This is `WorldFingerprint.compute`, which
`WorldSyncChannel` already compared; the probe only attributes each verdict to the
command type that produced it. Columns: `ok / DIVERGED / skipped / exempt`.

The comparison is **pre-state against pre-state**, not post-apply:
the host stamps `Command.pre_fingerprint` when the command leaves its queue and
ships that, and the peer compares against its own world at `_on_remote_command`
entry, *before* it submits (the authority confirms before it applies, so there is no
post-mutation world to sample). The cost is that a divergence is attributed to
the command *after* the one that caused it, and a run's final command is never
compared at all; if you need the last one, compare once explicitly at
end of sweep.

**RESOLVE — could this peer have derived the RESOLVE-STAGE result?** Only
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

**LAND — could this peer have derived the host's LAND-TIME arithmetic?** RESOLVE
covers the half of a record a plan+seed determines; LAND covers the half lockstep
would have stood on. It covers
post-mitigation damage, the reclassified hit kind, the HP bars (`h_hp0`/`h_hp1`/
`h_hpm`), the blade-pop cue, every forced-dealloc field, and the `FLAG_GATED`
bit. Columns: `ok / DIVERGED / ok(uns) / div(uns) / unavailable / landings`.

`h_hpm` is the load-bearing one: a peer that recomputed a node's derived max
health differently after a cascade — or clamped `current` in a different order —
lands its damage against a different bar. Derived stats are recomputed per
peer, so that is a live failure mode, not a hypothetical.

**LAND buckets by settledness rather than annotating it.** Land-time arithmetic
reads the peer's LIVE world, so a re-derivation taken while an earlier command
is still draining is being asked about a world the host never resolved against —
not evidence in either direction. `ok(uns)` / `div(uns)` hold those, disjoint
from the real verdicts, so expected noise cannot masquerade as a finding.
RESOLVE keeps its softer `deferred` annotation instead, because a plan+seed
resolution does not read the live world at all.

**This column is answerable only while every peer holds the full world.** Under
the deferred fog-filtered model the inputs are withheld on purpose, so a clean
LAND column says lockstep COULD have carried these numbers — never that the
record is unnecessary.

Nothing real mutates: `AttackPlan.resolve` lands its outcome in its own shadow world,
and the plan built here is local, never assigned to `battle_system.attack_plan`. One re-derivation answers both RESOLVE and LAND,
so the two columns can never be reported against different worlds.

## The partition, and why it is the whole design

The two columns **partition** the record — every field `AttackRecord.capture`
writes belongs to exactly one, and `test_the_two_columns_partition_every_recorded_field`
fails if a new field lands in neither. A field in neither would be silently
unmeasured, which is how a real desync passes clean.

| RESOLVE — what the plan and seed determine | LAND — what the peer's OWN world determines |
|---|---|
| `seed`, `ap` | `h_amt` — post-`Mitigation` effective damage |
| `h_tgt`, `h_org`, `h_atk` | `h_kind` — reclassified to HEAL on a `min_damage_taken` underflow |
| `h_at` (arrival clock) | `h_hp0` / `h_hp1` / `h_hpm` — the HP bars |
| `h_crit` + the `FLAG_CRIT` bit | the `FLAG_GATED` bit (decided at land) |
| the whole timeline (`e_*`) | `h_pop`, and every `d_*` — the forced-dealloc sets |

`h_flags` is the one field **split between** the columns: the crit bit is a
**seeded roll** and belongs to RESOLVE, while `FLAG_GATED` shares the byte and
is decided at land time. `DeterminismProbe._crit_bits` and `_bits` mask
accordingly, and neither column may compare the byte whole.

**Why they are tallied apart rather than summed.** They answer different
questions about different inputs, and a column that changed meaning between runs
would not be a measurement. A clean RESOLVE says the hit **set**, **order** and **timeline**
are reproducible (which depends on the stable hitscan sort). A
clean LAND says the derived recompute and the intra-beat pipeline order agree.
Neither, on one machine, says anything about `libm`.

## `skipped` is the honest denominator, not a pass

`CommandChannel._on_remote_command` deliberately suppresses the fingerprint compare
when the applier's queue is non-empty at the moment the command arrives — a peer
that is somewhere *inside* an earlier command is not at any command's boundary,
so comparing would report a divergence that never happened. A spurious ✗ poisons
the only diagnostic this harness has. That guard is correct and stays.

But it means a share of commands is **never compared**, and "0 diverged of 412"
handed to the owner while only 280 were looked at is a false clean read. They are
counted as `skipped`.

The compare runs ahead of the mutation, so it does not have to survive its own
`await` and lose to a command that arrives meanwhile. Skips redistribute between verbs
(the compare sits on the *first* command of a burst, not the last); the readout's
`skipped` column is the honest denominator.

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
