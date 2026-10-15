extends "res://tests/test_case.gd"
## The exact replacements for sin/pow must still behave like what they replaced, or the traps stop weaving
## smoothly and the level curve changes.

const ExactMath = preload("res://scripts/sim/exact_math.gd")


func test_wave_stays_in_range_and_reaches_both_edges() -> void:
	var lo := 9.0
	var hi := -9.0
	for i in 2000:
		var v := ExactMath.wave(i * 0.01 - 7.0)  # negative phases too
		ok(v >= -1.0 and v <= 1.0, "wave %f out of range" % v)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	ok(lo < -0.999 and hi > 0.999, "reaches the edges: %f..%f" % [lo, hi])


func test_wave_is_smooth_no_jumps_and_eases_at_the_edges() -> void:
	var step := 0.001
	var prev := ExactMath.wave(0.0)
	for i in range(1, int(TAU * 2.0 / step)):
		var v := ExactMath.wave(i * step)
		ok(absf(v - prev) < 0.005, "jump of %f at phase %f" % [absf(v - prev), i * step])
		prev = v
	# eases: near an edge it moves much slower than through the middle (like sin)
	var mid := absf(ExactMath.wave(TAU * 0.25 + 0.01) - ExactMath.wave(TAU * 0.25))
	var edge := absf(ExactMath.wave(TAU * 0.5 + 0.01) - ExactMath.wave(TAU * 0.5))
	ok(edge < mid * 0.1, "slows at the edge: edge %f vs middle %f" % [edge, mid])


func test_wave_has_period_tau() -> void:
	for x in [0.3, 1.7, 4.2]:
		ok(absf(ExactMath.wave(x) - ExactMath.wave(x + TAU)) < 1e-9, "period at %f" % x)


func test_int_power_matches_pow_closely() -> void:
	for base in [1.0, 1.35, 1.5, 2.0]:
		for n in 30:
			var want := pow(base, n)
			ok(absf(ExactMath.int_power(base, n) - want) <= want * 1e-12, "%f^%d" % [base, n])
	eq(ExactMath.int_power(1.5, 0), 1.0)
	eq(ExactMath.int_power(1.5, -3), 1.0, "negative n treated as 0")
