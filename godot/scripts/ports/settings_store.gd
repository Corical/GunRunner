extends RefCounted
## Port: where player settings are kept between sessions.
##   speed: game speed multiplier, 0.3..3.0 (default 1.0)
##   spawn_interval: seconds between enemy waves, 0 = automatic difficulty (default 0)

const DEFAULTS := {"speed": 1.0, "spawn_interval": 0.0}


func load_settings() -> Dictionary:
	push_error("SettingsStore.load_settings not implemented by %s" % get_script().resource_path)
	assert(false)
	return DEFAULTS.duplicate()


func save_settings(_settings: Dictionary) -> void:
	push_error("SettingsStore.save_settings not implemented by %s" % get_script().resource_path)
	assert(false)
