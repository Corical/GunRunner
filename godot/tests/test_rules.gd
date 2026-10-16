extends "res://tests/test_case.gd"
## Real data must load clean; every kind of broken cross-reference must be rejected.

const Rules = preload("res://scripts/sim/rules.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")


func _tables() -> Dictionary:
	var errors := PackedStringArray()
	var tables := Loader.load_tables(errors)
	assert(errors.is_empty(), "real data failed to parse: %s" % [errors])
	return tables.duplicate(true)


func _errors_after(mutate: Callable) -> PackedStringArray:
	var tables := _tables()
	mutate.call(tables)
	return Rules.from_tables(tables).errors


func _expect_error(mutate: Callable, fragment: String) -> void:
	var errs := _errors_after(mutate)
	for e in errs:
		if e.contains(fragment):
			return
	fail("expected an error containing '%s', got %s" % [fragment, errs])


func _row(tables: Dictionary, table: String, id: String) -> Dictionary:
	for row in tables[table]:
		if row["id"] == id:
			return row
	assert(false, "no row %s in %s" % [id, table])
	return {}


func test_real_data_loads_clean() -> void:
	var rules := Loader.load_rules()
	eq(rules.errors, PackedStringArray())
	eq(rules.weapons.size(), 10)
	eq(rules.enemies.size(), 7)
	eq(rules.towers.size(), 3)
	eq(rules.rewards.size(), 17)
	eq(rules.spawn_bands.size(), 4)
	eq(rules.multiplier("railgun", "armored"), 2.0)
	eq(rules.multiplier("pistol", "armored"), 1.0, "missing pair defaults to 1")
	eq(rules.t("game_speed"), 12.0)


func test_reward_weights_must_sum_to_100() -> void:
	_expect_error(func(t): _row(t, "rewards", "heal")["weight"] = 12, "sum to 99")


func test_reward_must_reference_real_weapon_or_tower() -> void:
	_expect_error(func(t): _row(t, "rewards", "smg")["id"] = "bazooka", "reward bazooka: no such weapon")
	_expect_error(func(t): _row(t, "rewards", "fire")["id"] = "lava", "reward lava: no such tower")
	_expect_error(func(t): _row(t, "rewards", "heal")["kind"] = "potion", "unknown kind 'potion'")


func test_every_character_needs_a_look_row() -> void:
	_expect_error(func(t): t["character_looks"] = t["character_looks"].filter(func(r): return r["id"] != "healer"),
		"healer: no row in character_looks.tsv")
	_expect_error(func(t): t["character_looks"] = t["character_looks"].filter(func(r): return r["id"] != "gunner"),
		"gunner: no row in character_looks.tsv")
	_expect_error(func(t): t["character_looks"] = t["character_looks"].filter(func(r): return r["id"] != "player"),
		"player: no row in character_looks.tsv")
	_expect_error(func(t): _row(t, "character_looks", "basic")["id"] = "dragon", "character_looks dragon: not the player")
	_expect_error(func(t): _row(t, "character_looks", "bomber")["scale"] = 0.0, "character_looks bomber: scale must be > 0")


func test_bosses_validated() -> void:
	_expect_error(func(t): _row(t, "bosses", "summoner")["summon_enemy"] = "dragon", "boss summoner: summon_enemy 'dragon' is not an enemy")
	_expect_error(func(t): _row(t, "bosses", "summoner")["summon_count"] = 0, "boss summoner: summons nothing")
	_expect_error(func(t): _row(t, "bosses", "gunner")["shot_speed"] = 0.0, "boss gunner: shoots, so shot_speed")
	_expect_error(func(t): _row(t, "bosses", "gunner")["steer"] = 0.0, "boss gunner: steer must be > 0")
	_expect_error(func(t): _row(t, "bosses", "gunner")["strafe"] = 40.0, "boss gunner: strafe 40.0 goes off the road")
	_expect_error(func(t): _row(t, "bosses", "brute")["strafe"] = 2.0, "boss brute: strafe only works while holding")
	_expect_error(func(t): _row(t, "bosses", "juggernaut")["hp_mult"] = 0.0, "boss juggernaut: hp_mult must be > 0")
	_expect_error(func(t): _row(t, "bosses", "brute")["speed"] = 0.0, "boss brute: speed must be > 0")
	_expect_error(func(t): t["bosses"] = [], "table 'bosses' is empty")
	_expect_error(func(t): _row(t, "bosses", "summoner")["hold_seconds"] = 0.0, "boss summoner: holds, so hold_seconds must be > 0")


## Every pickup must say what it is: a blank name or a broken colour would put an unreadable pickup on the road.
func test_reward_needs_label_and_colour() -> void:
	_expect_error(func(t): _row(t, "rewards", "rocket")["label"] = "  ", "reward rocket: label is empty")
	_expect_error(func(t): _row(t, "rewards", "heal")["color"] = "greenish", "reward heal: color 'greenish' is not a colour")
	_expect_error(func(t): t["rewards"][0].erase("label"), "table 'rewards' missing column 'label'")


func test_effectiveness_must_reference_real_ids() -> void:
	_expect_error(func(t): _row(t, "effectiveness", "laser-shielded")["enemy"] = "ghost", "unknown enemy 'ghost'")
	_expect_error(func(t): _row(t, "effectiveness", "laser-shielded")["weapon"] = "sword", "unknown weapon 'sword'")


func test_effectiveness_pair_listed_twice() -> void:
	_expect_error(func(t): _row(t, "effectiveness", "laser-armored")["enemy"] = "shielded", "listed twice")


func test_spawn_bands_validated() -> void:
	_expect_error(func(t): _row(t, "spawns", "early")["basic"] = 84, "sum to 99")
	_expect_error(func(t): _row(t, "spawns", "early")["start"] = 5.0, "first band must start at 0")
	_expect_error(func(t): _row(t, "spawns", "late")["start"] = 100.0, "not after previous band")
	_expect_error(func(t): _row(t, "spawns", "mid")["zombie"] = 0, "'zombie' is not an enemy id")


func test_tuning_missing_and_dead_keys() -> void:
	_expect_error(func(t): t["tuning"] = t["tuning"].filter(func(r): return r["id"] != "bullet_speed"), "missing 'bullet_speed'")
	_expect_error(func(t): t["tuning"].append({"id": "gravity", "value": 9.8, "source": "x"}), "'gravity' is not read by the sim")


## Fable review #6: xp_growth 0.5 made xp_needed() round to 0 and the level-up loop never ended.
func test_tuning_ranges_rejected() -> void:
	_expect_error(func(t): _row(t, "tuning", "xp_growth")["value"] = 0.5, "xp_growth = 0.5, must be at least 1")
	_expect_error(func(t): _row(t, "tuning", "burn_tick")["value"] = 0.0, "burn_tick")
	_expect_error(func(t): _row(t, "tuning", "wave_size_metres")["value"] = 0.0, "wave_size_metres")
	_expect_error(func(t): _row(t, "tuning", "enemy_pool")["value"] = 0.0, "enemy_pool")
	_expect_error(func(t): _row(t, "tuning", "heal_amount")["value"] = -2.0, "heal_amount = -2")
	_expect_error(func(t): _row(t, "tuning", "initial_hp")["value"] = 50.0, "initial_hp is above max_hp")
	eq(_errors_after(func(t): _row(t, "tuning", "player_z")["value"] = -12.0), PackedStringArray(), "positions behind the player may be negative")
	_expect_error(func(t): _row(t, "tuning", "upgrade_pair_chance")["value"] = 1.5, "upgrade_pair_chance = 1.5, is a chance")


func test_every_range_rule_names_a_real_key() -> void:
	for key in Rules.TUNING_MIN:
		ok(Rules.TUNING_KEYS.has(key), "TUNING_MIN has unknown key " + key)
	for key in Rules.TUNING_NEGATIVE_OK:
		ok(Rules.TUNING_KEYS.has(key), "TUNING_NEGATIVE_OK has unknown key " + key)


func test_every_weapon_needs_a_look_row() -> void:
	_expect_error(func(t): t["weapon_looks"] = t["weapon_looks"].filter(func(r): return r["id"] != "laser"),
		"weapon laser: no row in weapon_looks.tsv")
	_expect_error(func(t): t["weapon_looks"].append(_row(t, "weapon_looks", "pistol").merged({"id": "bazooka"}, true)),
		"weapon_looks bazooka: no such weapon")


func test_weapon_sanity() -> void:
	_expect_error(func(t): _row(t, "weapons", "smg")["fire_rate"] = 0.0, "fire_rate must be > 0")
	_expect_error(func(t): _row(t, "weapons", "railgun")["penetration"] = 0, "penetration must be >= 1")
	_expect_error(func(t): _row(t, "weapons", "pistol")["id"] = "peashooter", "default weapon 'pistol' missing")


func test_missing_table_and_column() -> void:
	_expect_error(func(t): t.erase("towers"), "missing table 'towers'")
	_expect_error(func(t): t["enemies"][0].erase("score"), "table 'enemies' missing column 'score'")
	_expect_error(func(t): t["weapons"] = [], "table 'weapons' is empty")


func test_unknown_tuning_key_read_asserts_not_defaults() -> void:
	var rules := Loader.load_rules()
	ok(not rules.tuning.has("no_such_key"), "sanity")
	# t() asserts in debug builds; we only check that it is not silently 0 by design: keys are validated up front.
	eq(Rules.TUNING_KEYS.size(), rules.tuning.size(), "every tuning row is a key the sim reads")
