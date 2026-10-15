extends "res://tests/test_case.gd"

const Rng = preload("res://scripts/sim/rng.gd")


func test_same_seed_same_sequence() -> void:
	var a := Rng.new(1234)
	var b := Rng.new(1234)
	for i in 1000:
		var x := a.next_float()
		var y := b.next_float()
		if x != y:
			fail("diverged at draw %d: %f vs %f" % [i, x, y])
			return
	eq(a.state(), b.state())


func test_different_seeds_differ() -> void:
	var a := Rng.new(1)
	var b := Rng.new(2)
	var same := 0
	for i in 100:
		if a.next_float() == b.next_float():
			same += 1
	ok(same < 5, "seeds 1 and 2 produced %d identical draws of 100" % same)


func test_range_int_hits_both_ends_and_never_leaves() -> void:
	var r := Rng.new(99)
	var seen := {}
	for i in 2000:
		var v := r.range_int(-2, 2)
		if v < -2 or v > 2:
			fail("out of range: %d" % v)
			return
		seen[v] = true
	eq(seen.size(), 5, "all of -2..2 drawn: %s" % [seen.keys()])


func test_next_float_in_unit_interval() -> void:
	var r := Rng.new(5)
	for i in 5000:
		var v := r.next_float()
		if v < 0.0 or v > 1.0:
			fail("out of [0,1]: %f" % v)
			return
