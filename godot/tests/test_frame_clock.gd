extends "res://tests/test_case.gd"

const FrameClock = preload("res://scripts/sim/frame_clock.gd")


func _steps_for(frame_dt: float, seconds: float, speed := 1.0) -> int:
	var c := FrameClock.new()
	c.speed = speed
	var total := 0
	var frames := int(round(seconds / frame_dt))
	for i in frames:
		total += c.advance(frame_dt)
	return total


func test_frame_rate_does_not_change_sim_time() -> void:
	eq(_steps_for(1.0 / 60.0, 60.0), 3600, "60 fps")
	eq(_steps_for(1.0 / 30.0, 60.0), 3600, "30 fps")
	var at144 := _steps_for(1.0 / 144.0, 60.0)
	ok(absi(at144 - 3600) <= 1, "144 fps gave %d steps for 60 s" % at144)


func test_jittery_frames_sum_correctly() -> void:
	var c := FrameClock.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var elapsed := 0.0
	var total := 0
	while elapsed < 60.0:
		var dt := rng.randf_range(0.004, 0.05)
		dt = minf(dt, 60.0 - elapsed)
		elapsed += dt
		total += c.advance(dt)
	ok(absi(total - 3600) <= 1, "jitter gave %d steps for 60 s" % total)
	eq(c.dropped_steps, 0, "nothing dropped below the cap")


func test_speed_multiplier_adds_steps_not_size() -> void:
	eq(_steps_for(1.0 / 60.0, 10.0, 3.0), 1800, "3x speed = 3 steps per 60 fps frame")
	var slow := _steps_for(1.0 / 60.0, 10.0, 0.3)
	ok(absi(slow - 180) <= 1, "0.3x gave %d" % slow)


func test_stall_is_capped_and_dropped_not_carried() -> void:
	var c := FrameClock.new()
	eq(c.advance(5.0), 12, "5 s stall runs at most max_steps")
	eq(c.dropped_steps, 288, "300 owed - 12 run")
	eq(c.advance(1.0 / 60.0), 1, "next normal frame is normal, no catch-up")


func test_pause_accumulates_nothing() -> void:
	var c := FrameClock.new()
	c.paused = true
	for i in 600:
		eq(c.advance(1.0 / 60.0), 0)
	c.paused = false
	eq(c.advance(1.0 / 60.0), 1, "no burst after 10 s paused")


func test_bad_frame_times_run_nothing() -> void:
	var c := FrameClock.new()
	eq(c.advance(NAN), 0)
	eq(c.advance(INF), 0)
	eq(c.advance(-0.5), 0)
	eq(c.advance(0.0), 0)
	eq(c.advance(1.0 / 60.0), 1, "still healthy afterwards")


func test_speed_clamped_to_slider_range() -> void:
	var c := FrameClock.new()
	c.set_speed(10.0)
	eq(c.speed, 3.0)
	c.set_speed(0.0)
	eq(c.speed, 0.3)
