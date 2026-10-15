extends "res://tests/test_case.gd"
## Real models: every file weapon_looks.tsv names must load, and a missing one must fall back, not leave a hole.

const Loader = preload("res://scripts/data/rules_loader.gd")
const PrimitiveCatalog = preload("res://scripts/adapters/primitive_catalog.gd")
const GltfCatalog = preload("res://scripts/adapters/gltf_catalog.gd")


func _catalog(rules) -> GltfCatalog:
	return GltfCatalog.new(rules, PrimitiveCatalog.new(rules))


func _mesh_count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for child in n.get_children():
		c += _mesh_count(child)
	return c


func test_every_named_weapon_model_loads_and_has_meshes() -> void:
	var rules := Loader.load_rules()
	var cat := _catalog(rules)
	for id in rules.weapons:
		if rules.weapon_looks[id]["model"] == "-":
			continue
		ok(cat.has_model(id), "weapon %s: %s does not load" % [id, rules.weapon_looks[id]["model"]])
		for kind in ["weapon", "reward"]:
			var n := cat.make(kind, id)
			ok(_mesh_count(n) > 0, "%s %s has no mesh" % [kind, id])
			n.free()


func test_missing_model_falls_back_to_the_stand_in() -> void:
	var rules := Loader.load_rules()
	rules.weapon_looks["laser"] = rules.weapon_looks["laser"].duplicate()
	rules.weapon_looks["laser"]["model"] = "kenney_blaster/does-not-exist.glb"
	var cat := _catalog(rules)
	expected_errors = 1  # the "did not load" report, once, however often it is asked for
	ok(not cat.has_model("laser"), "missing file is not a model")
	var n := cat.make("weapon", "laser")
	ok(_mesh_count(n) > 0, "stand-in drawn instead of nothing")
	ok(n.get_child(0) is MeshInstance3D, "primitive parts straight under the root (a glTF gun nests a scene)")
	n.free()
	var real := cat.make("weapon", "pistol")
	ok(not (real.get_child(0) is MeshInstance3D), "the pistol, which has a model, is the glTF scene")
	real.free()


func test_non_weapons_still_come_from_the_stand_in_catalog() -> void:
	var rules := Loader.load_rules()
	var cat := _catalog(rules)
	for pair in [["enemy", "basic"], ["boss", "gunner"], ["reward", "heal"], ["tower", "fire"], ["ice", ""]]:
		var n := cat.make(pair[0], pair[1])
		eq(String(n.name), "%s_%s" % pair, "%s %s from PrimitiveCatalog" % pair)
		n.free()
