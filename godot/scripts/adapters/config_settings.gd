extends "res://scripts/ports/settings_store.gd"
## Settings in a ConfigFile (user://settings.cfg on PC and Android). Unknown keys are ignored; out-of-range
## values are clamped, so a hand-edited file can't break the game.

var path := "user://settings.cfg"


func _init(file_path := "user://settings.cfg") -> void:
	path = file_path


func load_settings() -> Dictionary:
	var out := DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	out["speed"] = clampf(float(cfg.get_value("game", "speed", out["speed"])), 0.3, 3.0)
	var interval := float(cfg.get_value("game", "spawn_interval", out["spawn_interval"]))
	out["spawn_interval"] = 0.0 if interval <= 0.0 else clampf(interval, 0.3, 3.0)
	return out


func save_settings(settings: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "speed", settings.get("speed", 1.0))
	cfg.set_value("game", "spawn_interval", settings.get("spawn_interval", 0.0))
	var err := cfg.save(path)
	if err != OK:
		push_warning("settings: cannot save %s (error %d)" % [path, err])
