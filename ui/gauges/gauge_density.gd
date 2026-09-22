class_name GaugeDensity
extends RefCounted
## The one home of "is this subdivision legible": a gauge that subdivides its
## track into `count` cells (arrows, skill points, magazine rounds) draws a
## tick per cell only when each cell gets at least [constant MIN_TICK_PX] of
## track. Below that the ticks are mud and the gauge drops them wholesale —
## owner (2026-09-21): a hard threshold, never fade-by-alpha or every-k-th.
## Coarser marks (wave boundaries, pool caps) are not subject to it.

## Narrowest cell that still reads as a tick, in track pixels. Inclusive.
const MIN_TICK_PX := 4.0


## True when `count` cells across `track_px` pixels each get `min_px` or more.
## Non-positive `count` or `track_px` never fits.
static func ticks_fit(count: int, track_px: float, min_px: float = MIN_TICK_PX,
		gap_px: float = 0.0) -> bool:
	if count <= 0 or track_px <= 0.0:
		return false
	return track_px / float(count) >= min_px
