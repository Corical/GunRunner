extends Node3D
## The road, ground, trees, lights and camera. Matches the Babylon scene (SceneManager.ts): dark blue sky,
## soft fill light plus a warm sun, 15-wide road, grey curbs, cone trees. Lane dashes and trees scroll with
## the sim's distance, so they stop on pause and follow the speed slider (plan D14).
##
## Sim x is drawn at -x: Godot's camera looks down +z here, which puts world -x on the right of the screen.

const ROAD_LENGTH := 300.0
const ROAD_CENTRE_Z := 110.0
const DASH_SPACING := 6.0
const DASH_LENGTH := 3.0
const TREE_SPAN := 280.0
const TREE_START_Z := -30.0

var camera: Camera3D

var _dashes: MultiMeshInstance3D
var _trees: Array[Node3D] = []
var _tree_base_z: Array[float] = []
var _road_width := 15.0


static func view_pos(sim_x: float, sim_z: float, y := 0.0) -> Vector3:
	return Vector3(-sim_x, y, sim_z)


## options: glow, fog, trees default on (--no-glow etc. to measure); shadows default OFF (--shadows):
## measured 15 Oct 2026 on Intel Iris Xe, 1280x720, real-time bot run: shadows on = 24 ms GPU, 30 fps;
## shadows off = 11.6 ms GPU, locked 60 fps, worst 1% 19.6 ms (Babylon: 148 ms).
func build(road_width: float, view_seed: int, options := {}) -> void:
	_road_width = road_width
	_environment(options.get("glow", true), options.get("fog", true))
	_lights(options.get("shadows", false))
	_camera()
	_ground_and_road()
	_lane_dashes()
	if options.get("trees", true):
		_trees_build(view_seed)


func scroll(distance: float) -> void:
	if _dashes == null:
		return
	var offset := fmod(distance, DASH_SPACING)
	var count := _dashes.multimesh.instance_count / 2
	for i in count:
		var z := -20.0 + i * DASH_SPACING - offset
		for side in 2:
			var x := (-2.5 if side == 0 else 2.5)
			_dashes.multimesh.set_instance_transform(i * 2 + side, Transform3D(Basis(), Vector3(x, 0.02, z)))
	var tree_offset := fmod(distance, TREE_SPAN)
	for i in _trees.size():
		var z := _tree_base_z[i] - tree_offset
		if z < TREE_START_Z:
			z += TREE_SPAN
		_trees[i].position.z = z


func _environment(glow: bool, fog: bool) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = glow
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.fog_enabled = fog
	env.fog_light_color = Color(0.05, 0.05, 0.12)
	env.fog_density = 0.006
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _lights(shadows: bool) -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = shadows
	# Cheap shadows for integrated GPUs (measured: full PSSM to 140 m cost ~19 ms/frame on Iris Xe).
	# One orthogonal split covering the play area near the player; far enemies need no shadow.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)
	# Babylon sun direction (-0.3, -1, 0.5), mirrored in x like everything else.
	sun.look_at_from_position(Vector3.ZERO, Vector3(0.3, -1.0, 0.5), Vector3.FORWARD)


func _camera() -> void:
	camera = Camera3D.new()
	camera.fov = rad_to_deg(0.8)  # Config.ts CAMERA_FOV, vertical
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 400.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 18, -22), Vector3(0, 0, 8), Vector3.UP)
	camera.current = true


func _ground_and_road() -> void:
	_plane(Vector2(120, ROAD_LENGTH), Color("#2D5A27"), Vector3(0, -0.02, ROAD_CENTRE_Z))
	_plane(Vector2(_road_width, ROAD_LENGTH), Color("#555555"), Vector3(0, 0.0, ROAD_CENTRE_Z))
	var curb_mat := _flat_mat(Color(0.4, 0.4, 0.4))
	for side in [-1.0, 1.0]:
		var curb := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.3, ROAD_LENGTH)
		curb.mesh = box
		curb.material_override = curb_mat
		curb.position = Vector3(side * (_road_width / 2.0 + 0.2), 0.15, ROAD_CENTRE_Z)
		add_child(curb)


func _lane_dashes() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := BoxMesh.new()
	quad.size = Vector3(0.18, 0.02, DASH_LENGTH)
	mm.mesh = quad
	mm.instance_count = int(ceil((ROAD_LENGTH - 60.0) / DASH_SPACING)) * 2
	_dashes = MultiMeshInstance3D.new()
	_dashes.multimesh = mm
	_dashes.material_override = _flat_mat(Color(0.85, 0.85, 0.8), true)
	add_child(_dashes)
	scroll(0.0)


func _trees_build(view_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = view_seed
	var trunk_mat := _flat_mat(Color(0.35, 0.22, 0.1))
	var leaf_mat := _flat_mat(Color(0.15, 0.45, 0.1))
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.3
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 2.0
	trunk_mesh.radial_segments = 6
	var leaf_mesh := CylinderMesh.new()
	leaf_mesh.top_radius = 0.0
	leaf_mesh.bottom_radius = 1.25
	leaf_mesh.height = 3.0
	leaf_mesh.radial_segments = 6
	for i in 60:
		var tree := Node3D.new()
		var side := -1.0 if i % 2 == 0 else 1.0
		tree.position = Vector3(side * rng.randf_range(_road_width / 2.0 + 3.0, 40.0), 0, 0)
		var s := rng.randf_range(0.8, 1.5)
		tree.scale = Vector3(s, s, s)
		var trunk := MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.material_override = trunk_mat
		trunk.position.y = 1.0
		tree.add_child(trunk)
		var leaves := MeshInstance3D.new()
		leaves.mesh = leaf_mesh
		leaves.material_override = leaf_mat
		leaves.position.y = 3.2
		tree.add_child(leaves)
		add_child(tree)
		_trees.append(tree)
		_tree_base_z.append(TREE_START_Z + rng.randf() * TREE_SPAN)


func _plane(size: Vector2, colour: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = size
	mi.mesh = plane
	mi.material_override = _flat_mat(colour)
	mi.position = pos
	add_child(mi)


static func _flat_mat(colour: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
