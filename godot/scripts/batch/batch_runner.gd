extends RefCounted
## Headless batch: the bot plays seeds first_seed..first_seed+runs-1, each until game over or tick_cap,
## with invariants checked after every step. One run_end line per run and a summary line.
## Returns the process exit code: 1 if any run broke an invariant or anything logged an ERROR.

const GLog = preload("res://scripts/log/logger.gd")
const RulesLoader = preload("res://scripts/data/rules_loader.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Bot = preload("res://scripts/batch/simple_bot.gd")
const Invariants = preload("res://scripts/batch/invariants.gd")
const RunStats = preload("res://scripts/stats/run_stats.gd")

const DEFAULT_TICK_CAP := 72000


static func run(logger: GLog, sim_sink: Object, first_seed: int, runs: int, tick_cap: int) -> int:
	var rules := RulesLoader.load_rules()
	if not rules.ok():
		logger.error("data", "invalid", {"errors": "; ".join(rules.errors)})
		return 1
	var started := Time.get_ticks_msec()
	var failed_runs := 0
	var total_distance := 0.0
	var max_distance := 0.0
	var total_kills := 0
	var total_ticks := 0
	var bosses_beaten := 0
	var deaths := 0
	var totals := RunStats.new()
	for i in runs:
		var run_seed := first_seed + i
		var sim_log := GLog.new()
		sim_log.min_level = GLog.Level.WARN
		sim_log.add_sink(sim_sink)
		var s := Sim.new(rules, run_seed, sim_log)
		var bot := Bot.new()
		var inv := Invariants.new()
		var stats := RunStats.new()
		while not s.over and s.tick < tick_cap:
			s.step(bot.input(s))
			inv.check_step(s)
			stats.step(s)
		totals.merge(stats)
		inv.check_end(s, tick_cap)
		var beaten := s.boss.wave - (1 if s.boss.active else 0)
		logger.tick = s.tick
		logger.info("run", "run_end", {
			"seed": run_seed, "ticks": s.tick, "end": "died" if s.over else "cap", "distance": s.distance,
			"score": s.score, "kills": s.kills, "bosses_beaten": beaten, "weapon": "+".join(s.player.guns.map(func(g): return "%s:%d" % [g.id, g.level])),
			"hash": s.state_hash(), "warnings": sim_log.counts[GLog.Level.WARN],
			"invariant_failures": inv.failures.size(),
		})
		for f in inv.failures:
			logger.error("invariant", "failed", {"seed": run_seed, "what": f})
		if not inv.failures.is_empty() or sim_log.counts[GLog.Level.ERROR] > 0:
			failed_runs += 1
		total_distance += s.distance
		max_distance = maxf(max_distance, s.distance)
		total_kills += s.kills
		total_ticks += s.tick
		bosses_beaten += beaten
		deaths += 1 if s.over else 0
	logger.tick = -1
	# Which weapons carry the bot: kills per minute while held, across every run.
	for row in totals.weapon_rows():
		logger.info("batch", "weapon", row)
	for by in totals.hurt_by:
		logger.info("batch", "hurt_by", {"by": by, "damage": totals.hurt_by[by], "hits": totals.hits_taken_by[by]})
	logger.info("batch", "summary", {
		"first_seed": first_seed, "runs": runs, "failed_runs": failed_runs, "deaths": deaths,
		"avg_distance": total_distance / maxi(1, runs), "max_distance": max_distance,
		"avg_kills": float(total_kills) / maxi(1, runs), "bosses_beaten": bosses_beaten,
		"sim_minutes": total_ticks / 3600.0, "wall_seconds": (Time.get_ticks_msec() - started) / 1000.0,
	})
	return 1 if failed_runs > 0 or logger.counts[GLog.Level.ERROR] > 0 else 0
