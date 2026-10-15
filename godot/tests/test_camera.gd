extends "res://tests/test_case.gd"
## The player must always be on screen, low and with a margin, wherever they are on the road, on the
## narrowest screen we support (16:9; phones in landscape are wider). Pure maths on the camera transform,
## the same projection the GPU does (vertical FOV, keep-height).

const WorldView = preload("res://scripts/view/world_view.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")

const ASPECT := 16.0 / 9.0


## Normalised screen position of a world point: x and y in -1..1 are on screen, y = -1 is the bottom edge.
func _ndc(cam: Transform3D, fov_deg: float, p: Vector3) -> Vector2:
	var local := cam.affine_inverse() * p
	var t := tan(deg_to_rad(fov_deg) / 2.0)
	return Vector2(local.x / (-local.z * t * ASPECT), local.y / (-local.z * t))


func _camera_for(player_sim_x: float) -> Transform3D:
	var w := WorldView.new()
	# Let the follow settle: as if the player has been at this x for a while.
	for i in 300:
		w.follow(-player_sim_x, 1.0 / 60.0)
	var t := w.camera_base
	w.free()
	return t


func test_player_is_on_screen_low_with_a_margin_everywhere_on_the_road() -> void:
	var rules := Loader.load_rules()
	var half: float = rules.t("road_width") / 2.0 - rules.t("player_road_margin")
	var z: float = rules.t("player_z")
	for x in [-half, -half / 2.0, 0.0, half / 2.0, half]:
		var cam := _camera_for(x)
		for y in [0.0, 1.7]:  # feet and head
			var ndc := _ndc(cam, WorldView.CAM_FOV, WorldView.view_pos(x, z, y))
			ok(ndc.y > -0.9, "player x=%.1f y=%.1f is below the screen margin (ndc y %.2f)" % [x, y, ndc.y])
			ok(ndc.y < -0.2, "player x=%.1f y=%.1f is not in the lower part of the screen (ndc y %.2f)" % [x, y, ndc.y])
			ok(absf(ndc.x) < 0.85, "player x=%.1f off the side of the screen (ndc x %.2f)" % [x, ndc.x])


func test_spawn_point_is_on_screen() -> void:
	var rules := Loader.load_rules()
	var cam := _camera_for(0.0)
	var ndc := _ndc(cam, WorldView.CAM_FOV, WorldView.view_pos(0.0, rules.t("enemy_spawn_distance"), 1.0))
	ok(ndc.y < 0.95 and ndc.y > -0.5, "enemies appear on screen, upper half (ndc y %.2f)" % ndc.y)
