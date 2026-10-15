extends "res://tests/test_case.gd"

const Collision = preload("res://scripts/sim/collision.gd")


func test_point_jumping_clean_over_a_circle_still_hits() -> void:
	# Both endpoints are 5 units away; a point-in-circle test at either end would miss.
	ok(Collision.segment_hits_origin(0.5, -5.0, 0.5, 5.0, 1.0), "passes through at x=0.5")
	ok(Collision.segment_hits_origin(0.99, -5.0, 0.99, 5.0, 1.0), "grazes inside at x=0.99")


## swept_entry must agree with swept_hit on every case (a hit is a hit), and order entries along the path.
func test_swept_entry_agrees_with_swept_hit_and_orders_by_path() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 2000:
		var v := []
		for k in 8:
			v.append(rng.randf_range(-4.0, 4.0))
		var r := rng.randf_range(0.2, 2.5)
		var hit := Collision.swept_hit(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], r)
		var at := Collision.swept_entry(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], r)
		eq(at >= 0.0, hit, "case %d disagrees" % i)
		ok(at <= 1.0, "entry beyond the step")
	# point moving +z from 0 to 10: circle at z=4 entered before circle at z=7
	var near := Collision.swept_entry(0, 0, 0, 10, 0, 4, 0, 4, 1.0)
	var far := Collision.swept_entry(0, 0, 0, 10, 0, 7, 0, 7, 1.0)
	ok(near < far, "near %f before far %f" % [near, far])
	ok(absf(near - 0.3) < 1e-6, "enters radius-1 circle at z=3 -> t=0.3, got %f" % near)
	eq(Collision.swept_entry(0, 4, 0, 10, 0, 4, 0, 4, 1.0), 0.0, "starting inside = 0")


## The speed-up pre-check may only skip pairs that cannot hit; if it ever says "no" to a real hit, bullets pass
## through enemies. Also checks the inline copy in sim._bullets_vs_enemies uses the same rule.
func test_extents_precheck_never_rejects_a_real_hit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hits := 0
	for i in 5000:
		var v := []
		for k in 8:
			v.append(rng.randf_range(-6.0, 6.0))
		var r := rng.randf_range(0.2, 3.0)
		if Collision.swept_hit(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], r):
			hits += 1
			ok(Collision.extents_overlap(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], r), "case %d: pre-check rejected a hit" % i)
	ok(hits > 500, "enough real hits sampled (%d)" % hits)


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
