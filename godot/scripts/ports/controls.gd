extends RefCounted
## Port: where the player's steering comes from (keyboard, touch, bot, a recorded script).
## Menu keys (start, pause, speed) are handled by the game itself; this is only steering.


## -1 = full left, 1 = full right, 0 = still. `sim` is passed so a bot can read the game; humans ignore it.
func move_axis(_sim: Object) -> float:
	push_error("Controls.move_axis not implemented by %s" % get_script().resource_path)
	assert(false)
	return 0.0


func name() -> String:
	return "unnamed"
