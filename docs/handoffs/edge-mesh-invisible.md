# Edge MultiMesh invisible after #413

**State:** written against commit `ad346fb` (master). Owner confirmed live: the
zoom-jank FPS win from #413 is real, but edges no longer render at all.
Authoritative home is **issue #413's latest comment** — this file only points
at it so a fresh session doesn't have to re-derive the diagnosis.

**Diagnosis (already done, don't redo it):** headless-probed `Graph`/`Edge`
state in both sandboxes — instance count, transform, colors, and vis-state all
push correctly. The bug is confirmed isolated to `graph/edge_mesh.gdshader`'s
`vertex()`, specifically the `CANVAS_MATRIX`-based width extraction, which is
untested/likely wrong and unverifiable headlessly (Godot's dummy renderer
never executes shaders).

**Fix is spec'd, not yet applied** — see #413's comment for the exact 3-step
replacement (drop `CANVAS_MATRIX`, push `GraphCamera.current_zoom` as a
`global uniform` the same way `vision_falloff` etc. already work, one O(1)
write per zoom change). Apply it, then verify in a **windowed** run
(`dev_bloom_sandbox` or `first_level_sandbox`) — headless cannot render
shaders at all, so `mise run test`/`mise run check` passing proves nothing
about this bug.

**Delete this file once the fix lands and is confirmed live** — its only job
is pointing at #413 until then.
