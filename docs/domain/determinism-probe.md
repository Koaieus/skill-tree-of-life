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
godot --headless --path . scenes/dev/mp_dev_sandbox.tscn -- --role=client --address=127.0.0.1 --port=9099 --probe
```

**`--turns` is not optional for a measurement.** One sweep is ~17 commands and
then the loop stalls on Red waiting for input that never comes in headless. The
issue asks for a few hundred, so ask for the turns.

Or tick both boxes on the sandbox host's **Multiplayer** tab and Launch both.
**The breakdown prints in the CLIENT window**, not the launcher's log —
`--probe` on a host is a no-op that says so, because a host receives no command
to re-derive.

The readout fires after `PROBE_REPORT_QUIET_SECONDS` of silence on the wire
rather than at a command count or an end-of-sweep hook: a count would need the
harness to know how long a sweep is, and a sweep hook would leave a human
clicking in the window with no way to see the number at all. Quiet covers both,
and reprints after each later burst.

## Two questions, tallied apart

**WORLD — do the two worlds agree after applying?** This is
`WorldFingerprint.compute`, which `CommandLink` already compared; the probe only
attributes each verdict to the command type that produced it. Columns:
`ok / DIVERGED / skipped / exempt`.

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

`CommandLink._on_remote_command` deliberately suppresses the fingerprint
compare while the applier's queue is non-empty or a newer command has
superseded this one — two async commands in flight resume from the same
`applying_changed` and the earlier would otherwise compare a post-both world
against its own older fingerprint, reporting a divergence that never happened.
That guard is correct and stays.

But it means a real share of commands is **never compared**, and "0 diverged of
412" handed to the owner while only 280 were looked at is a false clean read.
They are counted as `skipped`. In practice the attack-heavy autopilot sweep
skips roughly a third — if you want a tighter read, that ratio is the thing to
attack, not the guard.

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
