extends SceneTree
## Renders every weapon as it appears inside a frozen pickup, in a row, and saves a PNG - to check real models'
## size and facing without playing to them. Run windowed (needs a renderer):
##   godot --path godot --resolution 1800x600 --script res://tools/model_sheet.gd -- --out=C:/path/sheet.png [--stand-ins]

const Loader = preload("res://scripts/data/rules_loader.gd")
const PrimitiveCatalog = preload("res://scripts/adapters/primitive_catalog.gd")
const GltfCatalog = preload("res://scripts/adapters/gltf_catalog.gd")

var _out := ""
var _frames := 0


func _init() -> void:
	var stand_ins := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		stand_ins = stand_ins or a == "--stand-ins"
	var rules := Loader.load_rules()
	var cat = PrimitiveCatalog.new(rules) if stand_ins else GltfCatalog.new(rules, PrimitiveCatalog.new(rules))
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#2A2F3A")
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var ids: Array = rules.weapons.keys()
	for i in ids.size():
		var m: Node3D = cat.make("reward", ids[i])
		m.position = Vector3((i - (ids.size() - 1) / 2.0) * 2.6, 0, 0)
		world.add_child(m)
		var l := Label3D.new()
		l.text = ids[i]
		l.pixel_size = 0.006
		l.position = m.position + Vector3(0, -0.4, 0)
		world.add_child(l)
	var cam := Camera3D.new()
	cam.fov = 60
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 13), Vector3(0, 0.9, 0))
	cam.make_current()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 10:
		root.get_viewport().get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
