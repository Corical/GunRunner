extends "res://tests/test_case.gd"
## A recorded run must replay into exactly the same game, including drag steering at arbitrary float
## positions and a spawn-rate change mid-run; a tampered or truncated file must be caught, not glossed over.

const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const RunRecorder = preload("res://scripts/stats/run_recorder.gd")
const RunStats = preload("res://scripts/stats/run_stats.gd")
const Replay = preload("res://scripts/stats/replay.gd")
const Bot = preload("res://scripts/batch/simple_bot.gd")

const DIR := "user://test-runs"


func _quiet_log() -> GLog:
	var l := GLog.new()
	l.mirror_errors_to_engine = false
	l.add_sink(Sinks.Memory.new())
	return l


## Plays `ticks` steps like the game does: bot + keys + drag (odd floats) + a spawn-rate change, recording all.
func _record(path: String, seed_value: int, ticks: int, finish := true) -> Sim:
	# No state hacks here (e.g. huge hp): a replay only has seed + inputs + settings, so anything else diverges.
	var s := Sim.new(Loader.load_rules(), seed_value, _quiet_log())
	var rec := RunRecorder.new(path, seed_value, RunRecorder.data_fingerprint(), 0.0)
	var bot := Bot.new()
	for i in ticks:
		var inp := {}
		if i % 400 < 150:
			inp = bot.input(s)
		elif i % 400 < 300:
			inp = {"target_x": sin(i * 0.0371) * 6.123456789}
		if i == 900:
			s.enemies.set_manual_interval(0.6)
			rec.setting(s.tick, 0.6)
		inp = Sim.quantize_input(inp, not s.choices.is_empty())  # as play_mode does: record exactly what the sim gets
		rec.input(s.tick, inp)
		s.step(inp)
		rec.after_step(s)
	if finish:
		rec.finish(s)
	else:
		rec.flush()
	return s


func test_replay_reproduces_the_game_exactly() -> void:
	var path := DIR.path_join("roundtrip.jsonl")
	var played := _record(path, 4242, 3000)
	var r := Replay.replay(path, _quiet_log())
	eq(r.errors, PackedStringArray())
	ok(r.ok, "replay verified")
	eq(r.checks, played.tick / 600, "every checkpoint up to tick %d matched" % played.tick)
	ok(played.tick >= 1200, "run lasted long enough to have checkpoints: %d" % played.tick)
	eq(r.sim.tick, played.tick)
	eq(r.sim.state_hash(), played.state_hash(), "identical final state")
	eq(r.sim.kills, played.kills)
	# Fixture sanity, not balance: the run must be a real game. Was > 10; pick-one pairs put twice the ice on the
	# road, which soaks bullets, and this seed now dies at tick 2012 with 8 kills (15 Oct 2026).
	ok(played.kills >= 5, "the recorded run actually played (%d kills, tick %d, over=%s)" % [played.kills, played.tick, played.over])


func test_tampered_seed_is_caught() -> void:
	var path := DIR.path_join("tampered.jsonl")
	_record(path, 99, 1300)
	var text := FileAccess.get_file_as_string(path).replace("\"seed\":99", "\"seed\":98")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var r := Replay.replay(path, _quiet_log())
	ok(not r.ok, "a replay of a different game must not verify")
	ok(r.errors.size() == 1 and r.errors[0].begins_with("diverged at tick 600"), "caught at the first checkpoint: %s" % [r.errors])


## Fable review #17: a corrupt line must be an error in the report, never a script crash or a silent 0.
func test_corrupt_lines_are_reported_not_crashed_on() -> void:
	var path := DIR.path_join("corrupt.jsonl")
	_record(path, 5, 700)
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var cases := {
		"{\"type\":\"start_weapon\",\"weapon\":\"bazooka\"}": "unknown start weapon",
		"{\"type\":\"start_tower\",\"tower\":\"lava\"}": "unknown start tower",
		"{\"type\":\"start_boss\",\"boss\":\"dragon\"}": "cannot start boss dragon",
		"{\"type\":\"in\",\"t\":3,\"move\":\"left\"}": "move is not a number",
	}
	for bad in cases:
		var mixed := PackedStringArray([lines[0], bad])
		mixed.append_array(lines.slice(1))
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("\n".join(mixed))
		f.close()
		var r := Replay.replay(path, _quiet_log())
		ok(not r.ok, "corrupt line accepted: " + bad)
		ok(r.errors.size() == 1 and r.errors[0].contains(cases[bad]), "%s -> %s" % [bad, r.errors])


## --boss=gunner runs start mid-fight; the recording must carry that or every checkpoint after it diverges.
func test_run_started_on_a_boss_replays_exactly() -> void:
	var path := DIR.path_join("boss_start.jsonl")
	var s := Sim.new(Loader.load_rules(), 77, _quiet_log())
	var rec := RunRecorder.new(path, 77, RunRecorder.data_fingerprint(), 0.0)
	ok(s.start_boss_now("gunner"), "gunner fight started")
	rec.start_boss("gunner")
	var bot := Bot.new()
	for i in 1800:
		var inp := Sim.quantize_input(bot.input(s), not s.choices.is_empty())
		rec.input(s.tick, inp)
		s.step(inp)
		rec.after_step(s)
		if s.over:
			break
	rec.finish(s)
	var r := Replay.replay(path, _quiet_log())
	eq(r.errors, PackedStringArray())
	ok(r.ok, "replay verified")
	eq(r.sim.state_hash(), s.state_hash(), "identical final state")
	var t := Sim.new(Loader.load_rules(), 1, _quiet_log())
	ok(t.start_boss_now("brute"), "first boss starts")
	eq(t.start_boss_now("gunner"), false, "no second boss over a live one")
	eq(t.boss.row["id"], "brute")
	eq(t.start_boss_now("dragon"), false, "unknown id")


func test_truncated_run_replays_to_last_checkpoint_with_a_warning() -> void:
	var path := DIR.path_join("killed.jsonl")
	var played := _record(path, 7, 1500, false)  # app killed: no end line
	var r := Replay.replay(path, _quiet_log())
	ok(r.ok, "partial run still verifies: %s" % [r.errors])
	ok(played.tick >= 1200, "recorded run reached a second checkpoint: %d" % played.tick)
	eq(r.sim.tick, (played.tick / 600) * 600, "replayed up to the last checkpoint")
	ok(r.warnings.size() >= 1 and r.warnings[0].contains("no end line"), "warned: %s" % [r.warnings])


func test_bad_files_fail_loudly() -> void:
	var path := DIR.path_join("garbage.jsonl")
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not json\n")
	f.close()
	ok(not Replay.replay(path, _quiet_log()).ok, "garbage")
	ok(not Replay.replay(DIR.path_join("missing.jsonl"), _quiet_log()).ok, "missing file")


func test_stats_attribute_kills_hits_and_hurt() -> void:
	var s := Sim.new(Loader.load_rules(), 3, _quiet_log())
	s.enemies.pause_spawning()
	s.player.fire_timer = -1e9
	s.player.set_weapon("laser")
	var stats := RunStats.new()
	var e = s.enemies._inactive()
	s.enemies._activate(e, "basic", 0.0, 3.0)
	var w: Dictionary = s.rules.weapons["laser"].duplicate()
	w["bullet_count"] = 1
	s.bullets.fire(0.0, 0.0, w, 1)
	var hurt = s.enemies._inactive()
	s.enemies._activate(hurt, "armored", s.player.x, s.player.z + 1.4)
	for i in 10:
		s.step({})
		stats.step(s)
	eq(stats.kills_by_weapon.get("laser", 0), 1, "laser kill attributed")
	eq(stats.kills_by_enemy.get("basic", 0), 1)
	eq(stats.hurt_by.get("armored", 0), 1, "hurt by the armored enemy that reached the player")
	ok(stats.timeline.size() >= 1 and stats.timeline[0].contains("HURT -1 by armored"), "timeline: %s" % [stats.timeline])
	eq(stats.ticks_by_weapon.get("laser", 0), 10, "held laser for 10 steps")
	var rows := stats.weapon_rows()
	eq(rows[0]["weapon"], "laser")
	ok(absf(rows[0]["kills_per_min"] - 360.0) < 1e-6, "1 kill in 10 steps = 360/min: %f" % rows[0]["kills_per_min"])
