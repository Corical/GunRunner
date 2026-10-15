extends "res://scripts/ports/model_catalog.gd"
## Real models where data/weapon_looks.tsv names one (model column), stand-ins for everything else. Wraps a
## PrimitiveCatalog and only takes over weapons - in the player's hands and inside frozen pickups.
## A model that fails to load is reported once and falls back to the stand-in, never a crash or a hole.

const Rules = preload("res://scripts/sim/rules.gd")
const PrimitiveCatalog = preload("res://scripts/adapters/primitive_catalog.gd")

const ROOT := "res://assets/models/"

var _rules: Rules
var _fallback: PrimitiveCatalog
var _scenes := {}  ## weapon id -> PackedScene, or null when it failed (so it is reported once)


func _init(rules: Rules, fallback: PrimitiveCatalog) -> void:
	_rules = rules
	_fallback = fallback


func make(kind: String, id: String) -> Node3D:
	if kind in ["player", "enemy", "boss"]:
		var key := "player" if kind == "player" else id
		if _character_scene(key) != null:
			return _character(kind, id, key)
	if kind == "weapon" and _scene(id) != null:
		return _gun(id)
	if kind == "reward" and _rules.weapons.has(id) and _scene(id) != null:
		var root := Node3D.new()
		root.name = "reward_%s" % id
		PrimitiveCatalog.pose_frozen_weapon(root, _gun(id))
		return root
	return _fallback.make(kind, id)


## Characters and weapons are real models now; only pickups, towers, ice and traps are still stand-ins.
func is_stand_in() -> bool:
	return false


## True when this weapon has a real model that loads (tests use it to prove every named file works).
func has_model(id: String) -> bool:
	return _scene(id) != null


func _gun(id: String) -> Node3D:
	var look: Dictionary = _rules.weapon_looks[id]
	var root := Node3D.new()
	root.name = "weapon_%s" % id
	var model: Node3D = (_scene(id) as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(look["model_scale"])
	model.rotation.y = deg_to_rad(float(look["model_yaw"]))
	root.add_child(model)
	return root


## True when this character ("player", enemy id or boss id) has a real model that loads.
func has_character(key: String) -> bool:
	return _character_scene(key) != null


## A character model: scaled (enemies also by their size), turned to face the player, its clip looping only
## while visible (pooled slots keep every enemy type built and hidden), with a ring at its feet in its data
## colour so the colour coding of the stand-ins (and the Enemy Guide) still holds.
func _character(kind: String, id: String, key: String) -> Node3D:
	var look: Dictionary = _rules.character_looks[key]
	var root := Node3D.new()
	root.name = "%s_%s" % [kind, id]
	var model: Node3D = (_character_scene(key) as PackedScene).instantiate()
	var size := 1.0
	var colour := "#3B82F6"
	if kind == "enemy":
		size = float(_rules.enemies[id]["size"])
		colour = _rules.enemies[id]["color"]
	elif kind == "boss":
		for b in _rules.bosses:
			if b["id"] == id:
				colour = b["color"]
	model.scale = Vector3.ONE * float(look["scale"]) * size
	model.rotation.y = deg_to_rad(float(look["yaw"]))
	root.add_child(model)
	if kind != "player":
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55 * size * (3.0 if kind == "boss" else 1.0)
		torus.outer_radius = 0.7 * size * (3.0 if kind == "boss" else 1.0)
		ring.mesh = torus
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(colour)
		m.emission_enabled = true
		m.emission = Color(colour)
		m.emission_energy_multiplier = 0.8
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = m
		ring.position.y = 0.05
		ring.scale.y = 0.2
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
	var player := _find_player(model)
	var clip: String = look["anim"]
	if player != null and player.has_animation(clip):
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
		root.visibility_changed.connect(func(): player.active = root.is_visible_in_tree())
	elif player != null:
		push_error("GltfCatalog: %s has no animation '%s'" % [key, clip])
	return root


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var p := _find_player(c)
		if p != null:
			return p
	return null


func _character_scene(key: String) -> PackedScene:
	var cache_key := "character:" + key
	if _scenes.has(cache_key):
		return _scenes[cache_key]
	var file: String = _rules.character_looks.get(key, {}).get("model", "-")
	var scene: PackedScene = null
	if file != "-":
		var path := ROOT + file
		scene = load(path) as PackedScene if ResourceLoader.exists(path) else null
		if scene == null:
			push_error("GltfCatalog: %s model %s did not load; drawing the stand-in" % [key, path])
	_scenes[cache_key] = scene
	return scene


func _scene(id: String) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var look: Dictionary = _rules.weapon_looks.get(id, {})
	var file: String = look.get("model", "-")
	var scene: PackedScene = null
	if file != "-":
		var path := ROOT + file
		scene = load(path) as PackedScene if ResourceLoader.exists(path) else null
		if scene == null:
			push_error("GltfCatalog: weapon %s model %s did not load; drawing the stand-in" % [id, path])
	_scenes[id] = scene
	return scene
