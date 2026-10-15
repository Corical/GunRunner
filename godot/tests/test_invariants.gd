extends "res://tests/test_case.gd"
## The batch gate trusts these checks, so each one is proven to fire on a deliberately broken state.

const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const Invariants = preload("res://scripts/batch/invariants.gd")
const Bot = preload("res://scripts/batch/simple_bot.gd")


func _sim() -> Sim:
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	logger.add_sink(Sinks.Memory.new())
	return Sim.new(Loader.load_rules(), 5, logger)


## Runs 30 clean steps, one more step, then applies `breakage` just before the check (applying it before the
## step let the sim heal some breakages, e.g. it clamps the player back onto the road), returns the failures.
func _failures_after(breakage: Callable) -> PackedStringArray:
	var s := _sim()
	var inv := Invariants.new()
	for i in 30:
		s.step({})
		inv.check_step(s)
	ok(inv.failures.is_empty(), "clean steps produced failures: %s" % [inv.failures])
	s.step({})
	breakage.call(s)
	inv.check_step(s)
	return inv.failures


func _expect(breakage: Callable, fragment: String) -> void:
	var f := _failures_after(breakage)
	for line in f:
		if line.contains(fragment):
			return
	fail("expected a failure containing '%s', got %s" % [fragment, f])


func test_score_going_down_is_caught() -> void:
	_expect(func(s): s.score -= 1000, "score fell")


func test_skipped_tick_is_caught() -> void:
	_expect(func(s): s.tick += 5, "tick jumped")


func test_player_off_the_road_is_caught() -> void:
	_expect(func(s): s.player.x = 40.0, "player off road")


func test_player_hp_over_max_is_caught() -> void:
	_expect(func(s): s.player.hp = s.player.max_hp + 3, "player hp")


func test_dead_enemy_left_active_is_caught() -> void:
	_expect(func(s):
		var e = s.enemies._inactive()
		s.enemies._activate(e, "basic", 0.0, 100.0)
		e.hp = 0, "enemy")


func test_run_without_kills_or_proper_end_is_caught() -> void:
	var s := _sim()
	var inv := Invariants.new()
	for i in 10:
		s.step({})
		inv.check_step(s)
	inv.check_end(s, 72000)
	ok(inv.failures.size() == 2, "no kills + stopped early: %s" % [inv.failures])


func test_bot_run_is_clean_and_plays() -> void:
	var s := _sim()
	var inv := Invariants.new()
	var bot := Bot.new()
	while not s.over and s.tick < 36000:
		s.step({"move": bot.decide(s)})
		inv.check_step(s)
	inv.check_end(s, 36000)
	eq(inv.failures, PackedStringArray())
	ok(s.kills > 20 and s.distance > 300.0, "bot actually plays: kills=%d distance=%.0f" % [s.kills, s.distance])
