extends Node
## Port: game sounds. The game hands over the sim events of each frame; the adapter decides what plays.
## Default adapter synthesises the Babylon build's sounds; recorded sound files can replace it later.

## Adapters declare `const HANDLED := [...]` with every event kind they react to (test_events checks coverage).


func handle(_events: Array) -> void:
	push_error("Sfx.handle not implemented by %s" % get_script().resource_path)
	assert(false)


func set_muted(_muted: bool) -> void:
	push_error("Sfx.set_muted not implemented by %s" % get_script().resource_path)
	assert(false)
