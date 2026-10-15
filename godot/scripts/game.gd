extends Node
## Entry point. Everything is built in code from here.
##
## Headless run (no window):
##   godot --headless --path godot -- --seed=7 --ticks=600 [--log=C:/path/run.log]
## Prints a run_end line and exits 0, or exits 1 if the run logged any ERROR.
## Phase 0: the sim is only the seeded RNG; phase 1 replaces the loop body with Sim.step().

const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const Rng = preload("res://scripts/sim/rng.gd")

const STEP := 1.0 / 60.0

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
	if headless and args.has("ticks"):
		var code := run_headless(seed_value, int(args["ticks"]))
		_file_sink.close()
		get_tree().quit(code)
		return
	_show_placeholder_screen()


## Returns the process exit code.
func run_headless(seed_value: int, ticks: int) -> int:
	var rng := Rng.new(seed_value)
	var checksum := 0
	for t in ticks:
		logger.tick = t
		checksum = hash([checksum, rng.range_int(0, 1 << 30)])
	logger.tick = ticks
	logger.info("run", "run_end", {
		"seed": seed_value, "ticks": ticks, "sim_seconds": ticks * STEP,
		"checksum": checksum, "errors": logger.counts[GLog.Level.ERROR],
	})
	return 1 if logger.counts[GLog.Level.ERROR] > 0 else 0


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
