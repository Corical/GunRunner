extends Node
## Entry point. Everything is built in code from here.
##
## Windowed:  godot --path godot [-- --seed=N --bot --autostart]
## Replay a recorded run (user://runs/*.jsonl, also pulled off the phone): -- --replay=C:/path/run-N.jsonl
## Headless batch, the bot plays every run (see batch/batch_runner.gd):
##   godot --headless --path godot -- --seed=7 [--runs=1] [--ticks=72000] [--log=C:/path/run.log]

const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const RulesLoader = preload("res://scripts/data/rules_loader.gd")
const BatchRunner = preload("res://scripts/batch/batch_runner.gd")
const PlayMode = preload("res://scripts/play/play_mode.gd")
const Replay = preload("res://scripts/stats/replay.gd")

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
	if headless and args.has("replay"):
		var replay_code := Replay.run(str(args["replay"]), logger)
		_file_sink.close()
		get_tree().quit(replay_code)
		return
	if headless and (args.has("ticks") or args.has("runs")):
		var code := BatchRunner.run(logger, _file_sink, seed_value, int(args.get("runs", 1)), int(args.get("ticks", BatchRunner.DEFAULT_TICK_CAP)))
		_file_sink.close()
		get_tree().quit(code)
		return
	var rules := RulesLoader.load_rules()
	if not rules.ok():
		logger.error("data", "invalid", {"errors": "; ".join(rules.errors)})
		_show_error("Game data is broken:\n" + "\n".join(rules.errors))
		return
	logger.min_level = GLog.Level.INFO
	args["seed"] = seed_value
	var play := PlayMode.new()
	add_child(play)
	play.start(rules, logger, args)


## "--seed=7 --runs=3 --bot" -> {"seed": 7, "runs": 3, "bot": true}. Integer values are converted.
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


func _show_error(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("#FCA5A5"))
	add_child(label)


func _exit_tree() -> void:
	if _file_sink != null:
		_file_sink.close()
