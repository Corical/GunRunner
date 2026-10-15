extends "res://scripts/ports/model_catalog.gd"
## Stand-in models built from primitives, shaped like the Babylon build's (Enemy.ts build*, Boss.ts,
## WeaponModelBuilder.ts) and coloured from data/*.tsv so each enemy keeps its colour identity.
## Replaced by real CC0 models in phase 4 behind the same port.

const Rules = preload("res://scripts/sim/rules.gd")

var _rules: Rules
## One mesh per shape+size, shared by every model (Fable #5: ~1,570 identical meshes were built at start).
## Nothing edits a mesh after it is made, so sharing is safe.
static var _meshes := {}
var _materials := {}  ## one material per colour+style, shared by every model (no per-model leaks)


func _init(rules: Rules) -> void:
	_rules = rules


func is_stand_in() -> bool:
	return true


func make(kind: String, id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "%s_%s" % [kind, id]
	match kind:
		"player":
			_player(root)
		"enemy":
			_enemy(root, id)
		"boss":
			_boss(root)
		"weapon":
			_weapon(root, id)
		"tower":
			_tower(root, id)
		"reward":
			_reward(root, id)
		"ice":
			_part(root, _box(Vector3(2.0, 2.0, 2.0)), _mat("#67E8F9", 0.55, 0.3), Vector3(0, 1.0, 0))
		"trap":
			_trap(root, id)
		_:
			push_error("PrimitiveCatalog: unknown kind '%s'" % kind)
	return root


func muzzle(weapon_id: String) -> Vector3:
	return Vector3(0, 0, -_weapon_length(weapon_id) * 0.5)


# ---------- builders ----------

## Booby trap stand-in: dark spiked ball over a glowing ring on the road (Corne: "something reddish around
## it"). Jammer red, Jinx purple. Look is not decided yet - mechanics first.
func _trap(root: Node3D, id: String) -> void:
	var hue: String = _rules.trap_by_id[id]["color"] if _rules.trap_by_id.has(id) else "#DC2626"
	var spikes := _mat(hue, 1.0, 0.6)
	_part(root, _sphere(0.55), _mat("#1F1F1F", 1.0, 0.0), Vector3(0, 0.8, 0))
	var dirs := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for d in dirs:
		var spike := _part(root, _cylinder(0.0, 0.18, 0.5), spikes, Vector3(0, 0.8, 0) + d * 0.7)
		spike.look_at_from_position(spike.position, spike.position + d, Vector3.FORWARD if absf(d.y) > 0.5 else Vector3.UP)
		spike.rotate_object_local(Vector3.RIGHT, -PI / 2.0)
	_part(root, _torus(1.0, 1.35), _mat(hue, 0.7, 1.2), Vector3(0, 0.05, 0))


func _player(root: Node3D) -> void:
	var blue := _mat("#3B82F6")
	_part(root, _capsule(0.4, 1.3), blue, Vector3(0, 0.65, 0))
	_part(root, _sphere(0.28), _mat("#93C5FD"), Vector3(0, 1.5, 0))


func _enemy(root: Node3D, id: String) -> void:
	var m := _mat(_rules.enemies[id]["color"] if _rules.enemies.has(id) else "#FF00FF", 1.0, 0.25)
	match id:
		"basic":
			_part(root, _cylinder(0.35, 0.35, 1.0), m, Vector3(0, 0.7, 0))
			_part(root, _sphere(0.25), m, Vector3(0, 1.5, 0))
			_part(root, _box(Vector3(1.1, 0.15, 0.15)), m, Vector3(0, 0.9, 0))
			_part(root, _cylinder(0.1, 0.1, 0.5), m, Vector3(-0.2, 0.0, 0))
			_part(root, _cylinder(0.1, 0.1, 0.5), m, Vector3(0.2, 0.0, 0))
		"armored":
			_part(root, _box(Vector3(1.4, 1.5, 0.9)), m, Vector3(0, 0.75, 0))
			_part(root, _box(Vector3(0.5, 0.3, 0.5)), m, Vector3(-0.85, 1.3, 0))
			_part(root, _box(Vector3(0.5, 0.3, 0.5)), m, Vector3(0.85, 1.3, 0))
			_part(root, _sphere(0.23), m, Vector3(0, 1.75, 0))
			_part(root, _box(Vector3(1.0, 0.6, 0.15)), _mat("#A78BFA"), Vector3(0, 0.9, -0.5))
		"fast":
			_part(root, _cylinder(0.0, 0.35, 1.4), m, Vector3(0, 0.45, 0), Vector3(-PI / 2, 0, 0))
			_part(root, _box(Vector3(0.06, 0.5, 0.5)), m, Vector3(-0.35, 0.45, 0.3), Vector3(0, 0, -0.4))
			_part(root, _box(Vector3(0.06, 0.5, 0.5)), m, Vector3(0.35, 0.45, 0.3), Vector3(0, 0, 0.4))
		"shielded":
			_part(root, _cylinder(0.4, 0.4, 1.2), m, Vector3(0, 0.6, 0))
			_part(root, _sphere(0.23), m, Vector3(0, 1.4, 0))
			_part(root, _cylinder(0.8, 0.8, 0.05), _mat("#67E8F9", 0.45, 0.6), Vector3(0, 0.75, -0.75), Vector3(PI / 2, 0, 0))
		"healer":
			_part(root, _sphere(0.45), m, Vector3(0, 0.5, 0))
			_part(root, _box(Vector3(0.7, 0.15, 0.15)), _mat("#FFFFFF"), Vector3(0, 1.2, 0))
			_part(root, _box(Vector3(0.15, 0.7, 0.15)), _mat("#FFFFFF"), Vector3(0, 1.2, 0))
			_part(root, _torus(0.55, 0.65), m, Vector3(0, 0.5, 0))
		"splitter":
			_part(root, _sphere(0.5), m, Vector3(0, 0.5, 0))
			_part(root, _sphere(0.25), m, Vector3(0.5, 0.7, 0))
			_part(root, _sphere(0.25), m, Vector3(-0.4, 0.3, 0.3))
			_part(root, _sphere(0.2), m, Vector3(0.1, 0.95, -0.3))
		"bomber":
			_part(root, _sphere(0.45), m, Vector3(0, 0.45, 0))
			_part(root, _cylinder(0.04, 0.04, 0.5), _mat("#D6D3D1"), Vector3(0, 1.1, 0), Vector3(0, 0, 0.3))
			_part(root, _sphere(0.09), _mat("#FBBF24", 1.0, 1.5), Vector3(0.08, 1.35, 0))
			_part(root, _box(Vector3(0.5, 0.05, 0.3)), m, Vector3(-0.5, 0.5, 0), Vector3(0, 0, -0.3))
			_part(root, _box(Vector3(0.5, 0.05, 0.3)), m, Vector3(0.5, 0.5, 0), Vector3(0, 0, 0.3))
		_:
			_part(root, _box(Vector3.ONE), _mat("#FF00FF"), Vector3(0, 0.5, 0))


func _boss(root: Node3D) -> void:
	var red := _mat("#DC2626", 1.0, 0.3)
	_part(root, _box(Vector3(4.0, 3.5, 3.0)), red, Vector3(0, 1.75, 0))
	_part(root, _box(Vector3(2.4, 1.6, 2.0)), red, Vector3(0, 4.3, 0))
	_part(root, _cylinder(0.0, 0.3, 1.2), _mat("#FDE68A"), Vector3(-0.9, 5.5, 0))
	_part(root, _cylinder(0.0, 0.3, 1.2), _mat("#FDE68A"), Vector3(0.9, 5.5, 0))
	_part(root, _sphere(0.25), _mat("#FBBF24", 1.0, 2.0), Vector3(-0.5, 4.5, -1.0))
	_part(root, _sphere(0.25), _mat("#FBBF24", 1.0, 2.0), Vector3(0.5, 4.5, -1.0))


func _weapon_length(id: String) -> float:
	match id:
		"shotgun", "railgun":
			return 1.4
		"rocket", "grenade", "minigun", "flamethrower":
			return 1.2
		"smg", "laser":
			return 1.0
	return 0.7


func _weapon(root: Node3D, id: String) -> void:
	var colour: String = _rules.weapons[id]["bullet_color"] if _rules.weapons.has(id) else "#FBBF24"
	var body := _mat("#374151")
	var accent := _mat(colour, 1.0, 0.6)
	var length := _weapon_length(id)
	var radius := 0.18 if id in ["rocket", "grenade", "minigun"] else 0.09
	_part(root, _box(Vector3(0.25, 0.3, 0.6)), body, Vector3(0, 0, 0.1))
	_part(root, _cylinder(radius, radius, length), accent, Vector3(0, 0.05, -length * 0.5), Vector3(PI / 2, 0, 0))


func _tower(root: Node3D, id: String) -> void:
	var row: Dictionary = _rules.towers.get(id, {"color": "#FFFFFF", "radius": 5.0})
	_part(root, _cylinder(0.6, 0.8, 1.5), _mat("#4B5563"), Vector3(0, 0.75, 0))
	var top := _part(root, _sphere(0.5), _mat(row["color"], 1.0, 0.8), Vector3(0, 1.9, 0))
	top.name = "Top"
	var disc := _part(root, _cylinder(row["radius"], row["radius"], 0.02), _mat(row["color"], 0.15, 0.4), Vector3(0, 0.03, 0))
	disc.name = "Range"


func _reward(root: Node3D, id: String) -> void:
	if _rules.weapons.has(id):
		var w := Node3D.new()
		_weapon(w, id)
		w.scale = Vector3.ONE * 1.4
		w.position = Vector3(0, 1.0, 0)
		w.rotation = Vector3(0, PI / 2, 0)
		root.add_child(w)
		return
	if _rules.towers.has(id):
		_part(root, _cylinder(0.25, 0.35, 0.8), _mat("#4B5563"), Vector3(0, 0.6, 0))
		_part(root, _sphere(0.3), _mat(_rules.towers[id]["color"], 1.0, 0.8), Vector3(0, 1.2, 0))
		return
	match id:
		"heal":
			_part(root, _box(Vector3(0.9, 0.3, 0.3)), _mat("#22C55E", 1.0, 0.6), Vector3(0, 1.0, 0))
			_part(root, _box(Vector3(0.3, 0.9, 0.3)), _mat("#22C55E", 1.0, 0.6), Vector3(0, 1.0, 0))
		"armor":
			_part(root, _cylinder(0.5, 0.5, 0.15), _mat("#60A5FA", 1.0, 0.6), Vector3(0, 1.0, 0), Vector3(PI / 2, 0, 0))
		"maxhp":
			_part(root, _cylinder(0.0, 0.45, 0.6), _mat("#F472B6", 1.0, 0.6), Vector3(0, 1.3, 0))
			_part(root, _cylinder(0.45, 0.0, 0.6), _mat("#F472B6", 1.0, 0.6), Vector3(0, 0.7, 0))
		"frenzy":
			_part(root, _sphere(0.45), _mat("#EF4444", 1.0, 0.8), Vector3(0, 1.0, 0))
		"speed":
			_part(root, _cylinder(0.0, 0.4, 0.7), _mat("#FBBF24", 1.0, 0.8), Vector3(0, 1.0, -0.2), Vector3(-PI / 2, 0, 0))
			_part(root, _cylinder(0.12, 0.12, 0.6), _mat("#FBBF24", 1.0, 0.8), Vector3(0, 1.0, 0.35), Vector3(PI / 2, 0, 0))
		_:
			_part(root, _box(Vector3.ONE * 0.6), _mat("#FF00FF"), Vector3(0, 1.0, 0))


# ---------- helpers ----------

func _part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _mat(hex: String, alpha := 1.0, glow := 0.15) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [hex, alpha, glow]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	var c := Color(hex)
	c.a = alpha
	m.albedo_color = c
	m.emission_enabled = glow > 0.0
	m.emission = Color(hex)
	m.emission_energy_multiplier = glow
	m.roughness = 0.6
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = m
	return m


static func _box(size: Vector3) -> BoxMesh:
	var key := "box|%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var m := BoxMesh.new()
	m.size = size
	_meshes[key] = m
	return m


static func _sphere(r: float) -> SphereMesh:
	var key := "sphere|%s" % r
	if _meshes.has(key):
		return _meshes[key]
	var m := SphereMesh.new()
	_meshes[key] = m
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 8
	return m


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var key := "cyl|%s|%s|%s" % [top, bottom, height]
	if _meshes.has(key):
		return _meshes[key]
	var m := CylinderMesh.new()
	_meshes[key] = m
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 16
	return m


static func _capsule(r: float, height: float) -> CapsuleMesh:
	var key := "capsule|%s|%s" % [r, height]
	if _meshes.has(key):
		return _meshes[key]
	var m := CapsuleMesh.new()
	_meshes[key] = m
	m.radius = r
	m.height = height
	return m


static func _torus(inner: float, outer: float) -> TorusMesh:
	var key := "torus|%s|%s" % [inner, outer]
	if _meshes.has(key):
		return _meshes[key]
	var m := TorusMesh.new()
	_meshes[key] = m
	m.inner_radius = inner
	m.outer_radius = outer
	return m
