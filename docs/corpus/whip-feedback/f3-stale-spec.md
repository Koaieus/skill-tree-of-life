**Observed (3 runs).** Sizing and splitting decisions are made from an issue's own estimate, and the estimate was stale:
- 2026-10-17 (4112f339, #1650): the lead planned "#1650 is too big for one drone (about 50 composition->scene sites plus about 101 get_node files ...): split it". The first drone reported "stale spec: access-style is 1 site (scenes/game_root.gd:703), not ~101 (that count included doc comments and "%s" format strings". Real work was 25 + 1 sites, one drone.
- 2026-10-16 (153e4757): "#431 ... The spec's grep proof for `clear_scaled_effect_sets` was stale, because the teardown half had already landed."
- 2026-10-16 (bd465c0c): "I closed five of the seven `Ready` issues. They had already landed on master."

**Proposed.** Before a lead splits a unit (or counts it large) it re-runs the issue's own count/grep command once; the drone brief's first step is the same check, and "stale spec" in NOTES is a signal the lead re-sizes the rest of the same hub from. One command, not a judgement.
