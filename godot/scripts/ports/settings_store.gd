extends RefCounted
## Port: where player settings are kept between sessions.
##   speed: game speed multiplier, 0.3..3.0 (default 1.0)
##   spawn_interval: seconds between enemy waves, 0 = automatic difficulty (default 0)
##   haptics: vibration on/off (default on); volume: 0..1 effects (0.8); music: mood name or "Off"; music_volume 0..1

const DEFAULTS := {"speed": 1.0, "spawn_interval": 0.0, "haptics": true, "volume": 0.8, "music": "Retro", "music_volume": 0.6, "hurt_flash": true}


func load_settings() -> Dictionary:
	push_error("SettingsStore.load_settings not implemented by %s" % get_script().resource_path)
	assert(false)
	return DEFAULTS.duplicate()


func save_settings(_settings: Dictionary) -> void:
	push_error("SettingsStore.save_settings not implemented by %s" % get_script().resource_path)
	assert(false)
