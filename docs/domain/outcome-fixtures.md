# Outcome fixtures: replaying an attack with no network

The two-process harness (`docs/domain/multiplayer-harness.md`) proves *host acts → client mirrors*, so every failure it reports has two candidate causes: the replay path or the messaging. The **Outcome playground** tab (`addons/outcome_playground/`) removes the second. It replays a recorded attack against a local `CommandApplier` with no `CommandChannel` attached — byte-for-byte the peer path, minus the wire. If a recorded outcome plays back correctly there, anything still broken over ENet is a messaging bug.

The unit of replay is one serialized `LaunchAttackCommand` — `plan` + `record` + `seed`, exactly what crosses. An `OutcomeFixture` (`attack/outcome/outcome_fixture.gd`) is that dictionary on disk, plus the `WorldFingerprint` before and after, plus a note. Fixtures are **captured, never authored**: a captured one proves the applier reproduces what the game did; an authored one only proves it applies what somebody typed. The shipped one is `test/fixtures/outcome/spark_cascade.tres`.

**The world is rebuilt from code, not stored.** A record names nodes by `stable_id` and its attacker by `entity_id`; both mint from per-`Graph` counters walking container child order, so a fixture only replays into an identically reproduced world. `scenes/dev/outcome_playground_world.gd` is the one builder, called by both the tab and the headless test (a `.tscn` plus a copy of "now arm it" on each side is where the two drift). `test_outcome_fixture_replay.gd` pins that two builds mint the same ids.

**A red fixture says which half broke.** A mismatched `world_fingerprint_at_capture` means the *builder* drifted — regenerate. A matching pre-state with a diverged `expected_fingerprint` means the *replay path* changed, which is the failure worth waking up for. Regenerate, never hand-edit:

```
REGEN_OUTCOME_FIXTURE=1 mise run test:one -- \
    res://test/unit/attack/test_outcome_fixture_replay.gd
```

That captures a live attack in the same headless context and rewrites the `.tres` the tab's Save button writes, so the two authoring paths cannot become two formats. Read the diff before committing. **A missing fixture is a failure, never a silent re-capture** — a test that captured its own golden when it found none would pass everywhere while asserting nothing.

**Untested:** every amount in `spark_cascade.tres` is integral, so whether a text resource round-trips `AttackRecord`'s `PackedFloat64Array` amounts exactly is unverified. They are float64 so a peer's HP lands on the host's number; if a fixture with a mitigated or crit-multiplied amount loses precision, the fix is a binary `.res`, not a change of format.
