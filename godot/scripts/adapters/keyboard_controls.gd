extends "res://scripts/ports/controls.gd"
## Arrow keys or A/D. Reads which keys are held right now instead of tracking press/release events, so
## releasing one key never stops movement while the other is still held (plan D15).


func move_axis(_sim: Object) -> float:
	var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
	return (1.0 if right else 0.0) - (1.0 if left else 0.0)


func name() -> String:
	return "keyboard"
