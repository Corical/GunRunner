extends SceneTree
## Sim cost benchmark (headless): the worst case the game can produce - Insane spawn rate, minigun with extra
## bullets, invulnerable player - stepped 3,600 times (1 minute of game). Prints microseconds per step.
## Run: godot --headless --path godot --script res://scripts/batch/bench_sim.gd
## One process only (never hog the machine). Compare before/after a change; absolute numbers are per machine.

const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Bot = preload("res://scripts/batch/simple_bot.gd")
const Sinks = preload("res://scripts/log/sinks.gd")

const STEPS := 3600


func _init() -> void:
	var rules := Loader.load_rules()
	if not rules.ok():
		print("rules failed: ", rules.errors)
		quit(1)
		return
	for mode in ["game", "file-only", "none"]:
		_bench(rules, mode)
	quit(0)


## mode "game" = what the game does today (INFO to a file AND print), "file-only" = file sink, "none" = WARN+.
func _logger(mode: String) -> GLog:
	var log := GLog.new()
	log.min_level = GLog.Level.INFO if mode != "none" else GLog.Level.WARN
	var path := OS.get_user_data_dir().path_join("bench.log")
	if mode != "none":
		log.add_sink(Sinks.File.new(path))
	if mode == "game":
		log.add_sink(Sinks.Stdout.new())
	if mode == "none":
		log.add_sink(Sinks.Memory.new())
	return log


func _bench(rules, mode: String) -> void:
	var results := []
	var lines := 0
	for seed_value in [1, 2, 3]:
		var log := _logger(mode)
		var s := Sim.new(rules, seed_value, log)
		s.enemies.set_manual_interval(0.3)
		s.player.set_weapon("minigun")
		s.player.mods["extra_bullets"] = 2.0
		s.player.hp = 1000000
		s.player.max_hp = 1000000
		var bot := Bot.new()
		var worst := 0
		var sim_usec := 0
		var started := Time.get_ticks_usec()
		var bullets_seen := 0
		var enemies_seen := 0
		for i in STEPS:
			var inp := {"move": bot.decide(s)}
			if not s.choices.is_empty():
				inp["pick"] = 0
			var t0 := Time.get_ticks_usec()
			s.step(inp)
			var dt := Time.get_ticks_usec() - t0
			sim_usec += dt
			worst = maxi(worst, dt)
			bullets_seen += s.bullets.active_count()
			enemies_seen += s.enemies.active_count()
		var total := sim_usec  # sim only; the bot is not the game
		results.append(float(total) / STEPS)
		lines += log.counts[GLog.Level.INFO] + log.counts[GLog.Level.DEBUG]
		printerr("  %s seed %d: %.1f us/step, worst %d us, %.0f bullets %.0f enemies" % [mode, seed_value,
			float(total) / STEPS, worst, float(bullets_seen) / STEPS, float(enemies_seen) / STEPS])
	results.sort()
	printerr("BENCH %-9s median %7.1f us/step | %.1f log calls/step (a 120 Hz frame is 8,333 us; 3x = 3 steps)" % [
		mode, results[1], float(lines) / (3 * STEPS)])
