extends RefCounted
## Replays a recorded run (see run_recorder.gd) headless and reports what happened:
##   godot --headless --path godot -- --replay=C:/path/run-123.jsonl
## Verifies every checkpoint hash: a mismatch means the replay is NOT the game that was played (different
## data, different code, or a corrupt file) and is reported as an error, never glossed over.

const GLog = preload("res://scripts/log/logger.gd")
const RulesLoader = preload("res://scripts/data/rules_loader.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const RunStats = preload("res://scripts/stats/run_stats.gd")
const RunRecorder = preload("res://scripts/stats/run_recorder.gd")


class Result:
	extends RefCounted
	var ok := false
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	var checks := 0
	var sim: Object
	var stats: RunStats


static func replay(path: String, sim_logger: GLog) -> Result:
	var r := Result.new()
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		r.errors.append("cannot read %s" % path)
		return r
	# A JSON instance reports bad lines through its return code (JSON.parse_string would raise engine errors).
	var lines := Array(text.split("\n", false)).map(func(l: String):
		var json := JSON.new()
		return json.data if json.parse(l) == OK else null)
	if lines.is_empty() or typeof(lines[0]) != TYPE_DICTIONARY or lines[0].get("type") != "header":
		r.errors.append("%s: first line is not a header" % path)
		return r
	var header: Dictionary = lines[0]
	if int(header.get("schema", -1)) != RunRecorder.SCHEMA:
		r.errors.append("schema %s, expected %d" % [header.get("schema"), RunRecorder.SCHEMA])
		return r
	if int(header.get("data", 0)) != RunRecorder.data_fingerprint():
		r.warnings.append("game data differs from the run's (balance changed since): the replay will diverge")
	var rules := RulesLoader.load_rules()
	if not rules.ok():
		r.errors.append("data invalid: %s" % "; ".join(rules.errors))
		return r
	var sim := Sim.new(rules, int(header["seed"]), sim_logger)
	if float(header.get("spawn_interval", 0.0)) > 0.0:
		sim.enemies.set_manual_interval(float(header["spawn_interval"]))
	var stats := RunStats.new()
	r.sim = sim
	r.stats = stats

	var by_tick := {}  # tick -> entries applied before step tick+1
	var checks := {}
	var end := {}
	for i in range(1, lines.size()):
		var e = lines[i]
		if typeof(e) != TYPE_DICTIONARY:
			r.errors.append("line %d is not JSON" % (i + 1))
			return r
		match e.get("type"):
			"in", "set":
				var t := int(e["t"])
				if not by_tick.has(t):
					by_tick[t] = []
				by_tick[t].append(e)
			"chk":
				checks[int(e["t"])] = int(e["hash"])
			"start_weapon":
				sim.player.set_weapon(str(e["weapon"]))
			"start_tower":
				sim.towers.deploy(str(e["tower"]), 0.0, func(_k, _f): pass)
			"end":
				end = e
	var last_tick: int = int(end["t"]) if not end.is_empty() else (int(checks.keys().max()) if not checks.is_empty() else 0)
	if end.is_empty():
		r.warnings.append("no end line (app closed or killed mid-run): replaying to the last checkpoint, tick %d" % last_tick)

	var inp := {}
	var guard := 0
	while sim.tick < last_tick and not sim.over:
		var pick := -1  # a level-up pick is one-shot: it must not answer a later level-up too
		for e in by_tick.get(sim.tick, []):
			if e["type"] == "set":
				sim.enemies.set_manual_interval(float(e["spawn_interval"]))
			else:
				inp = {}
				for k in ["move", "target_x"]:
					if e.has(k):
						inp[k] = float(e[k])
				if e.has("pick"):
					pick = int(e["pick"])
		var step_inp := inp.duplicate()
		if pick >= 0:
			step_inp["pick"] = pick
		var before := sim.tick
		sim.step(step_inp)
		if sim.tick == before and not sim.over:
			guard += 1
			if guard > 2:
				r.errors.append("stuck at tick %d: the game waits for a level-up pick the recording does not have" % sim.tick)
				return r
			continue
		guard = 0
		stats.step(sim)
		if checks.has(sim.tick):
			r.checks += 1
			if checks[sim.tick] != sim.state_hash():
				r.errors.append("diverged at tick %d: recorded hash %d, replay %d" % [sim.tick, checks[sim.tick], sim.state_hash()])
				return r
	if not end.is_empty() and int(end["hash"]) != sim.state_hash():
		r.errors.append("end hash differs: recorded %d, replay %d (tick %d)" % [int(end["hash"]), sim.state_hash(), sim.tick])
		return r
	r.ok = true
	return r


## Prints the report through `logger` and returns the process exit code.
static func run(path: String, logger: GLog) -> int:
	var sim_log := GLog.new()
	sim_log.min_level = GLog.Level.ERROR
	var r := replay(path, sim_log)
	for w in r.warnings:
		logger.warn("replay", "warning", {"what": w})
	for e in r.errors:
		logger.error("replay", "failed", {"what": e})
	if r.sim == null:
		return 1
	var s: Object = r.sim
	logger.info("replay", "result", {"file": path, "verified": r.ok, "checkpoints": r.checks, "ticks": s.tick,
		"seconds": s.tick / 60.0, "distance": s.distance, "score": s.score, "kills": s.kills, "over": s.over})
	for row in r.stats.weapon_rows():
		logger.info("replay", "weapon", row)
	for by in r.stats.hurt_by:
		logger.info("replay", "hurt_by", {"by": by, "damage": r.stats.hurt_by[by], "hits": r.stats.hits_taken_by[by]})
	for enemy in r.stats.kills_by_enemy:
		logger.info("replay", "kills_of", {"enemy": enemy, "kills": r.stats.kills_by_enemy[enemy]})
	for line in r.stats.timeline:
		logger.info("timeline", line)
	return 0 if r.ok and r.errors.is_empty() else 1
