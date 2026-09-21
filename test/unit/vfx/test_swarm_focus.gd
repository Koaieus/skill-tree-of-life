extends GutTest
## SwarmFocus (#1042): the damage-weighted COM of live projectiles, projected
## onto the wave's launch → landing segment. Pending until the unit lands;
## the drone's first commit flips these to RED.


func test_com_projects_onto_the_segment_at_the_weight_mean() -> void:
	pending("#1042: three weighted points → the projected COM lies on from→to at the weight-mean's scalar projection")


func test_perpendicular_lift_does_not_move_the_marker() -> void:
	pending("#1042: a point lifted off the segment changes nothing — the arc's lift is discarded")


func test_no_live_points_holds_the_last_position() -> void:
	pending("#1042: an empty point set leaves the marker where it was")


func test_zero_weights_fall_back_to_the_status_floor() -> void:
	pending("#1042: all-zero weights weigh STATUS_FLOOR each")
