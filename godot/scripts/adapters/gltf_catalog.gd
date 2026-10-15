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
	if kind == "weapon" and _scene(id) != null:
		return _gun(id)
	if kind == "reward" and _rules.weapons.has(id) and _scene(id) != null:
		var root := Node3D.new()
		root.name = "reward_%s" % id
		PrimitiveCatalog.pose_frozen_weapon(root, _gun(id))
		return root
	return _fallback.make(kind, id)


func is_stand_in() -> bool:
	return _fallback.is_stand_in()


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
