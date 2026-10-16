extends SceneTree
## Replays a recorded run with INFO logging, so the "player power" line at each boss prints (dps vs enemy and boss hp).
## godot --headless --path godot --script res://tools/replay_power.gd -- --replay=C:/path/run-N.jsonl
## Only meaningful on the build and data the run was recorded on (otherwise the replay diverges and warns).

func _init() -> void:
	var GLog = load("res://scripts/log/logger.gd")
	var Sinks = load("res://scripts/log/sinks.gd")
	var Replay = load("res://scripts/stats/replay.gd")
	var log = GLog.new()
	log.mirror_errors_to_engine = false
	log.add_sink(Sinks.Stdout.new())
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--replay="):
			path = a.trim_prefix("--replay=")
	var r = Replay.replay(path, log)
	print("warnings=", r.warnings, " errors=", r.errors)
	quit()
