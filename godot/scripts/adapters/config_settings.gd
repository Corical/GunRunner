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
	out["haptics"] = bool(cfg.get_value("game", "haptics", out["haptics"]))
	out["volume"] = clampf(float(cfg.get_value("game", "volume", out["volume"])), 0.0, 1.0)
	out["music"] = str(cfg.get_value("game", "music", out["music"]))
	out["music_volume"] = clampf(float(cfg.get_value("game", "music_volume", out["music_volume"])), 0.0, 1.0)
	return out


func save_settings(settings: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "speed", settings.get("speed", 1.0))
	cfg.set_value("game", "spawn_interval", settings.get("spawn_interval", 0.0))
	cfg.set_value("game", "haptics", settings.get("haptics", true))
	cfg.set_value("game", "volume", settings.get("volume", 0.8))
	cfg.set_value("game", "music", settings.get("music", "Retro"))
	cfg.set_value("game", "music_volume", settings.get("music_volume", 0.6))
	var err := cfg.save(path)
	if err != OK:
		push_warning("settings: cannot save %s (error %d)" % [path, err])
