---
paths:
  - "test/unit/spell/**"
---

A `SpellTestHelper` graph's `Navigator` mirrors no node until `graph.navigator.reconcile()`, so a `SplashEffect` / `EuclideanRangeFinder` gather finds nothing: call it after the fixture's last node change. **Why:** the euclidean gather filters the board index by the navigator's membership, so an unmirrored node is never gathered.
