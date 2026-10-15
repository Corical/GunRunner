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


func test_every_character_loads_animates_and_wears_its_colour_ring() -> void:
	var rules := Loader.load_rules()
	var cat := _catalog(rules)
	var cases := [["player", ""]]
	for id in rules.enemies:
		cases.append(["enemy", id])
	for b in rules.bosses:
		cases.append(["boss", b["id"]])
	for c in cases:
		var key: String = "player" if c[0] == "player" else c[1]
		ok(cat.has_character(key), "%s: %s does not load" % [key, rules.character_looks[key]["model"]])
		var n := cat.make(c[0], c[1])
		ok(_mesh_count(n) > 0, "%s %s has no mesh" % c)
		var p = cat._find_player(n)
		ok(p != null and p.current_animation == rules.character_looks[key]["anim"],
			"%s plays %s" % [key, rules.character_looks[key]["anim"]])
		var rings := 0
		for child in n.get_children():
			if child is MeshInstance3D and child.mesh is TorusMesh:
				rings += 1
		eq(rings, 0 if c[0] == "player" else 1, "%s colour ring" % key)
		n.free()


func test_unknown_animation_is_reported_not_silent() -> void:
	var rules := Loader.load_rules()
	rules.character_looks["fast"] = rules.character_looks["fast"].duplicate()
	rules.character_looks["fast"]["anim"] = "moonwalk"
	expected_errors = 1
	var n := _catalog(rules).make("enemy", "fast")
	ok(_mesh_count(n) > 0, "still drawn")
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


func test_pickups_towers_ice_traps_still_come_from_the_stand_in_catalog() -> void:
	var rules := Loader.load_rules()
	var cat := _catalog(rules)
	for pair in [["reward", "heal"], ["tower", "fire"], ["ice", ""], ["trap", "jammer"], ["boss_shot", ""]]:
		var n := cat.make(pair[0], pair[1])
		eq(String(n.name), "%s_%s" % pair, "%s %s from PrimitiveCatalog" % pair)
		n.free()
