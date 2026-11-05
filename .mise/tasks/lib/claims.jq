# Claim staleness — the pure half of `gh-project hygiene`'s `in_progress_stale`.
# See docs/domain/issue-workflow.md §Roadmap + hygiene.
#
# An open LEAF sitting `In progress` whose newest activity is older than
# $threshold is a dead claim: it hides the issue (and everything blocked by it)
# from every swarm, since a drone only pulls `Ready`. Hubs are skipped — a
# hub's `In progress` is derived from its children (hub_derive.jq), not a
# claim; `hub_drift` / `stalled_hub` own them.
#
# Activity = the newest of `.updated` (ISO 8601, the issue's updatedAt — covers
# comments) and `$activity["<n>"]` (epoch seconds, gathered by the caller from
# commits and worktrees). A missing signal is ignored; none at all counts as 0.
#
# Input:  array of {number, state, status, kids_total, updated}
# Args:   $now (epoch s), $activity ({"<n>": epoch s}), $threshold (seconds)
# Output: [{number, age_hours}] — age floored to whole hours.
def in_progress_stale($now; $activity; $threshold):
  [ .[]
    | select(.state == "OPEN" and .status == "In progress" and (.kids_total // 0) == 0)
    | ([ (.updated // empty | fromdateiso8601), ($activity[.number | tostring] // empty) ] | max // 0) as $last
    | ($now - $last) as $age
    | select($age > $threshold)
    | { number, age_hours: ($age / 3600 | floor) } ];
