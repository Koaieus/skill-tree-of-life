## State

Written against `6090b6c` (master). Authoritative sources: issue **#871**
(currently **reopened**, moved back to `In review` by the owner) and the
frame captures at `/tmp/shatter_capture/` — **not committed, may be
ephemeral (tmpfs/cleanup) — copy anything worth keeping before it's gone.**

`#871`'s original fix landed as `f6d35d6` ("node-kill shatter — seams glow,
disc shatters, no rim rays"), which closed the issue. The owner reopened it
after reviewing a frame collage and flagging a specific gap (see below).
`docs/handoffs/swarm-brief-871.md` is the *original* dispatch brief for that
now-landed fix — spent, unrelated to this fork, leave it alone.

## What was built this session

`tools/shatter_capture.gd` + `.tscn` (committed, `6090b6c`): drives
`AllocationVFX`'s real shatter tuning by hand — spawns once via
`vfx._spawn_shatter(...)`, then steps `vfx._shard_field.elapsed` to fixed
instants and grabs `get_viewport().get_texture().get_image()` after two
forced-render awaits (the `scenes/overlay_shader_verify.gd` pattern). This
exists because polling the live "Allocation VFX" sandbox tab with external
`xdotool`/`import` screenshots was unusable — the editor viewport only
redraws on sparse real frames under external polling, so the whole 1.4s
window kept collapsing into 1-2 captured instants, always missing the
burst. Run it with `godot --path . tools/shatter_capture.tscn` — windowed,
real renderer, **not** `--headless`/xvfb (the compatibility renderer packs
shard custom data as half-floats and would render differently, per
`ui/vfx/shatter/shatter_field.gd`'s own doc comment).

Output: `/tmp/shatter_capture/frame_00_t0.00.png` … `frame_15_t1.45.png`
(16 fixed instants), `/tmp/shatter_capture/scrub/scrub_00_t0.750.png` …
`scrub_08_t0.990.png` (dense 0.03s scrub of the burst window), and a
labeled contact sheet at `/tmp/shatter_capture/collage.png`.

## The open fork — nova rays missing from the crack-glow crescendo

**Owner's observation** (verbatim from conversation): the collage is
accurate as far as it goes, but shows *no nova rays from the cracks at any
point*, whereas they expected rays to appear and ramp up between
**t≈0.50–0.60 and t=0.84** (`flight_start`) — i.e. during the crescendo,
anchored to the crack seams, building toward the burst.

**Diagnosis (already done, cheap to verify, no further digging needed
to confirm the fact — only to decide what to do about it):**

```
grep -n "ray_" skill_node/visuals/inner_disk_shatter.gdshader   # zero hits
git show f6d35d6 -- skill_node/visuals/inner_disk_shatter.gdshader
```

`f6d35d6`'s own commit message says it plainly: *"Drops #257's supernova
rays (drawn outside the disc, over the rim, one per shard at PEAK EV — the
'rim glows / ~10 bursts along the rim' read) and the three `ray_*`
uniforms."* The diff confirms deletion, not relocation: `ray_peak_ev`,
`ray_angle_width`, `ray_length` and the whole ray-drawing block (evaluated
"outside the disc" against `rim_seam`, fanning "onto the rim") are gone
from the shader entirely. There is no ray code left anywhere to have
missed driving from the capture tool — **this is not a capture-tool false
negative, it's what the landed fix actually did.**

The original `#871` issue body left this ambiguous on purpose: *"That ray
feature is the likeliest culprit for both the rim glow and the
rim-explosion read — it may simply want to go, or be pulled inward onto
the crack seams themselves."* The landed fix took the first branch
("let it go"). The owner, now looking at the actual result, is describing
the second branch ("pulled inward onto the crack seams") as what they
actually wanted — rays anchored to the crack lines themselves, ramping
during the crescendo, rather than no rays at all.

**This is a design decision, not a bug fix** — the code is doing exactly
what `f6d35d6` intended; the question is whether that intent itself now
needs revising given the owner's fresh look. Whoever picks this up should:

1. Confirm with the owner that "rays anchored to the cracks, ramping
   t≈0.5→0.84" is really what they want restored (vs. e.g. just wanting
   the crack lines themselves to glow brighter/wider — re-read their
   exact wording before assuming ray geometry specifically).
2. If confirmed, this is new shader work on
   `skill_node/visuals/inner_disk_shatter.gdshader` — the deleted block in
   `f6d35d6`'s diff is a real starting reference for the *shape* of a
   crack-anchored ray (same `smoothstep`/`dist_falloff` idiom), but it drew
   from the rim outward; a crack-anchored version would need to seed from
   each crack's own geometry instead of `rim_seam`, and should almost
   certainly gate itself off entirely by `flight_start` (never draw during
   shard flight) so it can't reintroduce the old "still glowing after the
   burst" complaint from a different angle.
3. File the outcome — whichever way it goes — as a new comment on `#871`
   (it's already reopened and in `In review`) or a fresh issue if it's
   deferred, so the fork doesn't just live in this file. Update
   `tools/shatter_capture.gd`'s fixed instant list if the new geometry
   needs different sample points to review.

## Live numbers

- `shatter_window = 1.4`, `shatter_flight_start = 0.6` → the burst instant
  in absolute seconds is `flight_start * window = 0.84`, matching the
  owner's own "between t≈0.50-0.60 and t=0.84" framing.
- Capture radius used: `24.0` (SkillNode's `base_inner_radius` default).
- Tint used: `Color(0.35, 0.85, 0.4)`.

## Delete this file when

The ray decision (build it / drop it / reword the ask) is recorded on
`#871` or in a new issue, and the shader change (if any) has landed.
