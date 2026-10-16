#!/usr/bin/env bash
# Board sweep 2026-10-16: writes the permission classifier refused the sweep agents.
# Review, then run from the repo:  bash <this file>
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
cd /home/bramh/skill-tree-of-life
close() { # n reason file
  gh issue comment "$1" --body-file "$3"
  gh issue edit "$1" --add-label 'stale?'
  gh issue close "$1" --reason "$2"
}
mark() { # n file
  gh issue comment "$1" --body-file "$2"
  gh issue edit "$1" --add-label 'stale?'
}
close 446  completed "$D/work-bl2/c446.md"
close 450  completed "$D/work-bl2/c450.md"
close 505  completed "$D/work-bl2/c505.md"
close 1052 completed "$D/work-bl3/p3/c1052.md"
close 1540 completed "$D/work-bl4/p2-close-1540-1589.md"
close 1589 completed "$D/work-bl4/p2-close-1540-1589.md"
mark 448  "$D/work-bl2/c448.md"
mark 451  "$D/work-bl2/c451.md"
mark 484  "$D/work-bl2/c484.md"
mark 595  "$D/work-bl2/c595.md"
mark 1565 "$D/work-bl4/p2-stale-1565-1603.md"
mark 1603 "$D/work-bl4/p2-stale-1565-1603.md"
echo done
