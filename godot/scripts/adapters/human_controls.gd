extends "res://scripts/ports/controls.gd"
## A person: keyboard (arrows / A D) and drag steering (mouse or finger), drag wins while held.
##
## Drag is relative, like touch runners: press anywhere, slide, and the player follows the slide.
## Half the screen width sweeps the whole road. Keys read which keys are held right now (not press/release
## events), so releasing one key never stops movement while the other is held (plan D15).

## ours: half the screen width = the full road (tune by feel).
const SCREEN_FRACTION_FOR_ROAD := 0.5

var _dragging := false
var _press_px := 0.0
var _anchor_x := 0.0
var _target_x := 0.0
var _road := 14.0


func read(sim: Object) -> Dictionary:
	if sim != null:
		_road = sim.rules.t("road_width") - 2.0 * sim.rules.t("player_road_margin")
	if _dragging:
		return {"target_x": _target_x}
	var left := Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A)
	var right := Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D)
	return {"move": (1.0 if right else 0.0) - (1.0 if left else 0.0)}


func on_pointer(event: InputEvent, sim: Object, viewport_width: float) -> void:
	var units_per_px := _road / maxf(1.0, viewport_width * SCREEN_FRACTION_FOR_ROAD)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_set_pressed(event.pressed, event.position.x, sim)
	elif event is InputEventScreenTouch and event.index == 0:
		_set_pressed(event.pressed, event.position.x, sim)
	elif event is InputEventMouseMotion and _dragging:
		_target_x = _anchor_x + (event.position.x - _press_px) * units_per_px
	elif event is InputEventScreenDrag and event.index == 0 and _dragging:
		_target_x = _anchor_x + (event.position.x - _press_px) * units_per_px


func _set_pressed(pressed: bool, px: float, sim: Object) -> void:
	_dragging = pressed
	if pressed:
		_press_px = px
		_anchor_x = sim.player.x if sim != null else 0.0
		_target_x = _anchor_x


func name() -> String:
	return "keys+drag"
