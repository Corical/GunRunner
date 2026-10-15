extends "res://tests/test_case.gd"

const Collision = preload("res://scripts/sim/collision.gd")


func test_point_jumping_clean_over_a_circle_still_hits() -> void:
	# Both endpoints are 5 units away; a point-in-circle test at either end would miss.
	ok(Collision.segment_hits_origin(0.5, -5.0, 0.5, 5.0, 1.0), "passes through at x=0.5")
	ok(Collision.segment_hits_origin(0.99, -5.0, 0.99, 5.0, 1.0), "grazes inside at x=0.99")


func test_edge_and_outside_miss() -> void:
	ok(not Collision.segment_hits_origin(1.0, -5.0, 1.0, 5.0, 1.0), "exactly on the edge is a miss (strict, Babylon parity)")
	ok(not Collision.segment_hits_origin(1.5, -5.0, 1.5, 5.0, 1.0), "passes outside")
	ok(not Collision.segment_hits_origin(0.0, 2.0, 0.0, 5.0, 1.0), "moving away, never near")


func test_zero_length_segment_is_a_point_test() -> void:
	ok(Collision.segment_hits_origin(0.3, 0.3, 0.3, 0.3, 1.0), "stationary inside")
	ok(not Collision.segment_hits_origin(2.0, 0.0, 2.0, 0.0, 1.0), "stationary outside")


func test_moving_circle_uses_relative_motion() -> void:
	# Bullet stays at z=0; circle sweeps from z=+5 to z=-5 through it.
	ok(Collision.swept_hit(0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 0.0, -5.0, 1.0), "circle passes over a still point")
	# Both move the same way at the same speed, 3 apart: never meet.
	ok(not Collision.swept_hit(0.0, 0.0, 0.0, 10.0, 0.0, 3.0, 0.0, 13.0, 1.0), "chasing at equal speed never meets")


func test_head_on_closing_faster_than_radius_per_step() -> void:
	# Closing speed 20 units in one step against a radius of 1: the old point test misses this.
	ok(Collision.swept_hit(0.0, -10.0, 0.0, 10.0, 0.2, 10.0, 0.2, -10.0, 1.0), "head-on at high closing speed")
