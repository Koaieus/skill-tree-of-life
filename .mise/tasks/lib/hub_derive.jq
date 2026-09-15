# Hub status derivation — the pure half of `gh-project hygiene --fix` and
# `gh-project sync-parent`. See docs/domain/issue-workflow.md §Hubs.
#
# A parent never carries work, so its status is a FUNCTION of its children:
#   1. no open child                              → Done, and close the issue
#   2. every open child is In review              → In review
#   3. any child Ready / In progress / In review  → In progress
#   4. children only Backlog / Needs design       → no action (hand-set filing state)
#   5. a hub is never Ready (Ready is the swarm queue) → In progress
# A parent with an OPEN child missing from the board is never derived (you'd
# close a hub over a child you can't see) — it lands in `unboarded` instead.
# Closed children are routinely archived off the project and don't matter here.
#
# Input:  array of {number, state ("OPEN"|"CLOSED"), status, parent, kids_total, kids_done}
# Output: {actions: [{number, from, to, close, reason}], unboarded: [{number, missing}]}
def derive:
  . as $items
  | [ $items[] | select(.state == "OPEN" and (.kids_total // 0) > 0) ] as $hubs
  | {
      actions: [
        $hubs[] as $hub
        | [ $items[] | select(.parent == $hub.number and .state == "OPEN") ] as $open
        | select(($open | length) >= ($hub.kids_total - ($hub.kids_done // 0)))
        | (
            if ($open | length) == 0 then
              { to: "Done", close: true, reason: "all \($hub.kids_total) child(ren) closed" }
            elif all($open[]; .status == "In review") then
              { to: "In review", close: false, reason: "every open child is In review" }
            elif any($open[]; .status == "Ready" or .status == "In progress" or .status == "In review") then
              { to: "In progress", close: false, reason: "a child is being ground" }
            elif $hub.status == "Ready" then
              { to: "In progress", close: false, reason: "a hub is never Ready — Ready is the swarm queue" }
            else
              null
            end
          ) as $d
        | select($d != null and $d.to != $hub.status)
        | { number: $hub.number, from: $hub.status, to: $d.to, close: $d.close, reason: $d.reason }
      ],
      unboarded: [
        $hubs[] as $hub
        | ([ $items[] | select(.parent == $hub.number and .state == "OPEN") ] | length) as $seen
        | ($hub.kids_total - ($hub.kids_done // 0)) as $expected
        | select($seen < $expected)
        | { number: $hub.number, missing: ($expected - $seen) }
      ]
    };
