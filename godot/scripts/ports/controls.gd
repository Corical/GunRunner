extends RefCounted
## Port: where the player's steering comes from (keyboard, drag, bot, a recorded script).
## Menu keys (start, pause, speed) are handled by the game itself; this is only steering.


## The sim input for this step: {"move": -1..1} or {"target_x": world x}. `sim` lets a bot read the game.
func read(_sim: Object) -> Dictionary:
	push_error("Controls.read not implemented by %s" % get_script().resource_path)
	assert(false)
	return {}


## Pointer and touch events the game did not use for its UI. Adapters that don't steer by pointer ignore them.
func on_pointer(_event: InputEvent, _sim: Object, _viewport_width: float) -> void:
	pass


func name() -> String:
	return "unnamed"
