# Balance Harness Snapshot

> Informative only — an order-of-magnitude smell test for runaway or non-fun values. Not a source of truth and never a build gate.
> See `tools/balance/README.md` — including why this snapshot goes stale
> once #274 lands.

Generated: 2026-08-03T15:41:09

## mirror_L5

| Readout | Value |
|---|---|
| attacker_level | 5 |
| attacker_owned_nodes | 12 |
| damage_per_ap_melee | 3.000 |
| damage_per_ap_ranged | 3.000 |
| defender_health_pool | 24.000 |
| defender_level | 5 |
| defender_node_max_hp | 24.000 |
| defender_owned_nodes | 12 |
| hits_to_drop_node | 8 |
| melee_damage_raw | 3.000 |
| melee_dpa_over_ranged_dpa | 1.000 |
| mitigated_melee_damage | 3.000 |
| mitigated_ranged_damage | 3.000 |
| ranged_damage_raw | 3.000 |
| sp_income_at_level_marginal | 2.000 |
| sp_income_at_level_max | 24.000 |
| territory_growth_per_turn | 2.000 |
| territory_growth_sp_per_level | 2.000 |
| territory_growth_turns_per_level | 1 |
| turns_to_drop_core_naive | 8 |

## mirror_L20

| Readout | Value |
|---|---|
| attacker_level | 20 |
| attacker_owned_nodes | 45 |
| damage_per_ap_melee | 4.000 |
| damage_per_ap_ranged | 4.000 |
| defender_health_pool | 39.000 |
| defender_level | 20 |
| defender_node_max_hp | 39.000 |
| defender_owned_nodes | 45 |
| hits_to_drop_node | 10 |
| melee_damage_raw | 4.000 |
| melee_dpa_over_ranged_dpa | 1.000 |
| mitigated_melee_damage | 4.000 |
| mitigated_ranged_damage | 4.000 |
| ranged_damage_raw | 4.000 |
| sp_income_at_level_marginal | 2.000 |
| sp_income_at_level_max | 90.000 |
| territory_growth_per_turn | 2.000 |
| territory_growth_sp_per_level | 2.000 |
| territory_growth_turns_per_level | 1 |
| turns_to_drop_core_naive | 10 |

## mirror_L50

| Readout | Value |
|---|---|
| attacker_level | 50 |
| attacker_owned_nodes | 111 |
| damage_per_ap_melee | 7.000 |
| damage_per_ap_ranged | 7.000 |
| defender_health_pool | 69.000 |
| defender_level | 50 |
| defender_node_max_hp | 69.000 |
| defender_owned_nodes | 111 |
| hits_to_drop_node | 10 |
| melee_damage_raw | 7.000 |
| melee_dpa_over_ranged_dpa | 1.000 |
| mitigated_melee_damage | 7.000 |
| mitigated_ranged_damage | 7.000 |
| ranged_damage_raw | 7.000 |
| sp_income_at_level_marginal | 2.000 |
| sp_income_at_level_max | 222.000 |
| territory_growth_per_turn | 2.000 |
| territory_growth_sp_per_level | 2.000 |
| territory_growth_turns_per_level | 1 |
| turns_to_drop_core_naive | 10 |

## matched_L100_zero_invest

| Readout | Value |
|---|---|
| attacker_level | 100 |
| attacker_owned_nodes | 221 |
| baseline_raw_damage_vs_mitigation_at_matched_level | 1.500 |
| damage_per_ap_melee | 3.000 |
| damage_per_ap_ranged | 3.000 |
| defender_armor | 0.000 |
| defender_health_pool | 119.000 |
| defender_level | 100 |
| defender_min_damage_taken | 3.000 |
| defender_node_max_hp | 119.000 |
| defender_owned_nodes | 221 |
| hits_to_drop_node | 40 |
| melee_damage_raw | 2.000 |
| melee_dpa_over_ranged_dpa | 1.000 |
| mitigated_melee_damage | 3.000 |
| mitigated_ranged_damage | 3.000 |
| ranged_damage_raw | 2.000 |
| sp_income_at_level_marginal | 2.000 |
| sp_income_at_level_max | 442.000 |
| turns_to_drop_core_naive | 40 |

## asymmetric_snipe_L20_vs_L80

| Readout | Value |
|---|---|
| attacker_level | 20 |
| attacker_owned_nodes | 45 |
| damage_per_ap_melee | 4.000 |
| damage_per_ap_ranged | 4.000 |
| defender_health_pool | 99.000 |
| defender_level | 80 |
| defender_node_max_hp | 99.000 |
| defender_owned_nodes | 177 |
| hits_to_drop_node | 25 |
| melee_damage_raw | 4.000 |
| melee_dpa_over_ranged_dpa | 1.000 |
| mitigated_melee_damage | 4.000 |
| mitigated_ranged_damage | 4.000 |
| ranged_damage_raw | 4.000 |
| sp_income_at_level_marginal | 2.000 |
| sp_income_at_level_max | 354.000 |
| turns_to_drop_core_naive | 25 |

## core_adjacent_aura_L50

| Readout | Value |
|---|---|
| aura_coverage_fraction | 0.027 |
| aura_covered_nodes | 3 |
| core_node_ttk_pressure_per_turn | 7.000 |
| core_node_ttk_under_sustained_pressure | -1 |
| defender_level | 50 |
| defender_owned_nodes | 111 |

## Invariants

_Every range ships `TBD` (D-13 — an implementing agent must never invent
balance ranges). `OUT` is a printed observation, exactly like `TBD` — it never_
_fails this run._

| Invariant | Status | Detail | Why |
|---|---|---|---|
| melee_dpa_over_ranged_dpa | TBD | 1.000 (range not yet pinned) | channel parity |
| hits_to_drop_node | TBD | 10 (range not yet pinned) | baseline TTK |
| sp_income_at_level | TBD | 2.000 (range not yet pinned) | progression tempo |
| aura_coverage_fraction | TBD | 0.027 (range not yet pinned) | D-10 sanctuary bubble — what fraction of territory the heal aura covers must stay bounded, or it out-heals the forced-dealloc chip damage and the core's death clock stops ticking |
| core_node_ttk_under_sustained_pressure | TBD | -1 (range not yet pinned) | D-10 magnitude — the core-node heal is deliberately not a full reset, so sustained pressure must still grind it down; a reading of -1 (never depleted within the simulated cap) means the aura re-exempted the core from D-9 attrition |
| baseline_raw_damage_vs_mitigation_at_matched_level | TBD | 1.500 (range not yet pinned) | D-11/D-14 — confirms no dead zone re-forms via bulk alone: a leveled defender should be slower to kill but never effectively immune to an uninvested attacker |
