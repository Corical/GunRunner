extends Node
## Port: phone vibration for game events. The game hands over each frame's sim events; the adapter decides what
## buzzes. Adapters declare `const HANDLED := [...]` like the sound adapter (test_events checks coverage).


func handle(_events: Array) -> void:
	push_error("Haptics.handle not implemented by %s" % get_script().resource_path)
	assert(false)


func set_enabled(_on: bool) -> void:
	push_error("Haptics.set_enabled not implemented by %s" % get_script().resource_path)
	assert(false)
