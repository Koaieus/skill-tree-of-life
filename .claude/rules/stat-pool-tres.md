---
description: Two silent traps when hand-editing a StatPool sub-resource in a pool .tres
paths:
  - "procgen/pools/**"
---

# Hand-editing a StatPool in a `.tres`

**`resource_name` is not an identity.** `StatPool`'s `stat_id` and `operation` setters
call `_update_resource_name()`, which overwrites any authored `resource_name` with
`"<stat_id> <op>"` on load. Two pools sharing (stat, op) — a small and a fat
`xp_per_turn +%` — are indistinguishable by name afterwards.

**Why:** the name is derived for the inspector, not stored.
**How to apply:** tell pools apart (in tests, sweeps, debugging) by the entry's
`pool_key`, never by `resource_name`.

**Keep `metadata/…` lines last in a sub-resource.** A property line (`pool_weight = …`)
placed *after* a `metadata/…` line in a StatPool sub-resource silently dropped the loaded
`subtypes` gate — a regular STR node rolled blight-gated `corruption_potency`. Found by
#1079; no parse error, no warning.

**Why:** the failure is invisible except as wrong content, and only a scoping sweep
(`test_pool_scoping.gd`, the subtype-gate tests) catches it.
**How to apply:** when adding a property by hand, insert it above any `metadata/` line;
after editing a pool `.tres`, run `test:dir res://test/unit/procgen/` plus
`test_pool_scoping.gd`.
