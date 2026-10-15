extends Node
## Entry point. Everything is built in code from here.
##
## Headless batch (no window), the bot plays every run:
##   godot --headless --path godot -- --seed=7 [--runs=1] [--ticks=72000] [--log=C:/path/run.log]
## Runs seeds seed..seed+runs-1, each until game over or the tick cap (default 20 sim-minutes).
## One run_end line per run, a batch summary line, exit 1 if any run broke an invariant or logged an ERROR.

const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const RulesLoader = preload("res://scripts/data/rules_loader.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Bot = preload("res://scripts/batch/simple_bot.gd")
const Invariants = preload("res://scripts/batch/invariants.gd")

const DEFAULT_TICK_CAP := 72000

var logger: GLog
var _file_sink: Sinks.File


func _ready() -> void:
	var args := parse_args(OS.get_cmdline_user_args())
	var seed_value: int = args.get("seed", int(Time.get_unix_time_from_system()))
	logger = GLog.new()
	var log_path: String = args.get("log", "user://logs/run-%d.log" % seed_value)
	_file_sink = Sinks.File.new(log_path)
	logger.add_sink(_file_sink)
	logger.add_sink(Sinks.Stdout.new())
	var headless := DisplayServer.get_name() == "headless"
	logger.info("boot", "start", {
		"seed": seed_value, "headless": headless, "godot": Engine.get_version_info()["string"],
		"log": ProjectSettings.globalize_path(log_path),
	})
	if headless and (args.has("ticks") or args.has("runs")):
		var code := run_batch(seed_value, int(args.get("runs", 1)), int(args.get("ticks", DEFAULT_TICK_CAP)))
		_file_sink.close()
		get_tree().quit(code)
		return
	_show_placeholder_screen()


## Returns the process exit code.
func run_batch(first_seed: int, runs: int, tick_cap: int) -> int:
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
	for i in runs:
		var run_seed := first_seed + i
		var sim_log := GLog.new()
		sim_log.min_level = GLog.Level.WARN
		sim_log.add_sink(_file_sink)
		var s := Sim.new(rules, run_seed, sim_log)
		var bot := Bot.new()
		var inv := Invariants.new()
		while not s.over and s.tick < tick_cap:
			s.step({"move": bot.decide(s)})
			inv.check_step(s)
		inv.check_end(s, tick_cap)
		var beaten := s.boss.wave - (1 if s.boss.active else 0)
		logger.tick = s.tick
		logger.info("run", "run_end", {
			"seed": run_seed, "ticks": s.tick, "end": "died" if s.over else "cap", "distance": s.distance,
			"score": s.score, "kills": s.kills, "bosses_beaten": beaten, "weapon": s.player.weapon_id,
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
	logger.info("batch", "summary", {
		"first_seed": first_seed, "runs": runs, "failed_runs": failed_runs, "deaths": deaths,
		"avg_distance": total_distance / maxi(1, runs), "max_distance": max_distance,
		"avg_kills": float(total_kills) / maxi(1, runs), "bosses_beaten": bosses_beaten,
		"sim_minutes": total_ticks / 3600.0, "wall_seconds": (Time.get_ticks_msec() - started) / 1000.0,
	})
	return 1 if failed_runs > 0 or logger.counts[GLog.Level.ERROR] > 0 else 0


## "--seed=7 --ticks=600 --flag" -> {"seed": "7", "ticks": "600", "flag": true}. Numbers are converted.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq_at := body.find("=")
		if eq_at < 0:
			out[body] = true
			continue
		var value := body.substr(eq_at + 1)
		out[body.substr(0, eq_at)] = value.to_int() if value.is_valid_int() else value
	return out


func _show_placeholder_screen() -> void:
	var label := Label.new()
	label.text = "GunRunner — Godot port\nPhase 0 scaffold. Gameplay arrives in phase 2."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 32)
	add_child(label)
	logger.info("boot", "placeholder_screen")


func _exit_tree() -> void:
	if _file_sink != null:
		_file_sink.close()
