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


func _surface_albedos(n: Node, out: Array) -> void:
	if n is MeshInstance3D and not ((n as MeshInstance3D).mesh is TorusMesh):  # the ring is a marker
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i)
			out.append(m.albedo_color if m is BaseMaterial3D else null)
	for c in n.get_children():
		_surface_albedos(c, out)


func _first_override(n: Node) -> Material:
	if n is MeshInstance3D and (n as MeshInstance3D).get_surface_override_material(0) != null:
		return (n as MeshInstance3D).get_surface_override_material(0)
	for c in n.get_children():
		var m := _first_override(c)
		if m != null:
			return m
	return null


## 16 Oct: "different body colours per enemy type". Every enemy and boss body carries its data colour, the player
## keeps its own, pooled slots of one type share one material, and no two enemy types look the same.
func test_enemy_and_boss_bodies_wear_their_data_colour() -> void:
	var rules := Loader.load_rules()
	var cat := _catalog(rules)
	var p := cat.make("player", "")
	var player_albedos: Array = []
	_surface_albedos(p, player_albedos)
	p.free()
	ok(player_albedos.size() > 0 and player_albedos.all(func(a): return a == null), "player is not tinted")
	var seen := {}
	var cases: Array = []
	for id in rules.enemies:
		cases.append(["enemy", id, rules.enemies[id]["color"]])
	for b in rules.bosses:
		cases.append(["boss", b["id"], b["color"]])
	for c in cases:
		var n := cat.make(c[0], c[1])
		var albedos: Array = []
		_surface_albedos(n, albedos)
		var want := Color.WHITE.lerp(Color(c[2]), cat.TINT_STRENGTH)
		ok(albedos.size() > 0, "%s %s has surfaces" % [c[0], c[1]])
		for a in albedos:
			ok(a != null and a.is_equal_approx(want), "%s %s tinted %s, got %s" % [c[0], c[1], want, a])
		var again := cat.make(c[0], c[1])
		ok(_first_override(n) == _first_override(again), "%s %s: slots share one material" % [c[0], c[1]])
		again.free()
		n.free()
		if c[0] == "enemy":
			ok(not seen.has(c[2]), "enemy %s shares colour %s with %s" % [c[1], c[2], seen.get(c[2], "")])
			seen[c[2]] = c[1]


## Sideways half-width of what is drawn (the colour ring at the feet is a marker, not body).
func _half_width(n: Node, parent := Transform3D.IDENTITY) -> float:
	var xf := parent
	if n is Node3D:
		xf = parent * (n as Node3D).transform
	var half := 0.0
	if n is MeshInstance3D and not ((n as MeshInstance3D).mesh is TorusMesh):
		var box: AABB = xf * (n as MeshInstance3D).get_aabb()
		half = maxf(absf(box.position.x), absf(box.end.x))
	for c in n.get_children():
		half = maxf(half, _half_width(c, xf))
	return half


## 16 Oct: a 6 m boss hit width hit Corne from 3.5 m past the juggernaut's body, so it could not be dodged; 15 Oct
## the same for enemies at 2 m. Sideways, a hit must land where the bodies touch, give or take 0.35 m.
func test_sideways_hit_reach_matches_the_drawn_bodies() -> void:
	var rules := Loader.load_rules()
	var cat := _catalog(rules)
	var p := cat.make("player", "")
	var player_half := _half_width(p)
	p.free()
	ok(player_half > 0.3, "player is drawn (%.2f m)" % player_half)
	var cases: Array = []
	for id in rules.enemies:
		var reach: float = rules.t("enemy_hit_player_radius") + float(rules.enemies[id]["size"]) * rules.t("enemy_radius_per_size")
		cases.append(["enemy", id, reach])
	for b in rules.bosses:
		cases.append(["boss", b["id"], float(b["contact_dx"])])
	for c in cases:
		var n := cat.make(c[0], c[1])
		var touch := _half_width(n) + player_half
		n.free()
		ok(absf(c[2] - touch) <= 0.35, "%s %s hits %.2f m to the side, bodies touch at %.2f m" % [c[0], c[1], c[2], touch])


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
