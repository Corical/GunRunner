extends "res://tests/test_case.gd"
## Level-ups: the game pauses for a pick, offers distinct perks, respects max stacks, each perk does what its
## card says, and several levels gained at once are all offered, one after another.

const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const Events = preload("res://scripts/sim/events.gd")


func _sim() -> Sim:
	var l := GLog.new()
	l.mirror_errors_to_engine = false
	l.add_sink(Sinks.Memory.new())
	var s := Sim.new(Loader.load_rules(), 21, l)
	s.enemies.pause_spawning()
	s.rules.tuning["upgrade_spawn_per_second"] = 0.0
	return s


func _level_up(s: Sim) -> void:
	s.xp = s.xp_needed(s.level)
	s.step({})


func test_xp_curve() -> void:
	var s := _sim()
	var base := s.rules.t("xp_base")
	var growth := s.rules.t("xp_growth")
	eq(s.xp_needed(1), int(round(base)))
	eq(s.xp_needed(2), int(round(base * growth)))
	eq(s.xp_needed(5), int(round(base * pow(growth, 4))))
	ok(s.xp_needed(10) > s.xp_needed(9), "each level needs more than the last")


func test_level_up_pauses_until_a_pick() -> void:
	var s := _sim()
	_level_up(s)
	eq(s.level, 2)
	eq(s.choices.size(), 3, "three cards")
	var tick := s.tick
	for i in 30:
		s.step({"move": 1.0})
	eq(s.tick, tick, "no time passes while choosing")
	s.step({"pick": 7})
	eq(s.tick, tick, "out-of-range pick refused")
	ok(not s.choices.is_empty(), "still choosing")
	var chosen: String = s.choices[1]
	s.step({"pick": 1})
	eq(s.tick, tick + 1, "pick taken and the game moves on in the same step")
	eq(s.player.perk_stacks.get(chosen, 0), 1)
	ok(s.choices.is_empty(), "choice closed")


func test_choices_are_distinct_and_respect_max_stacks() -> void:
	var s := _sim()
	for row in s.rules.perks:
		if row["id"] != "damage" and row["id"] != "fire_rate" and row["id"] != "range":
			s.player.perk_stacks[row["id"]] = int(row["max_stacks"])
	for i in 20:
		_level_up(s)
		var unique := {}
		for c in s.choices:
			unique[c] = true
			ok(c in ["damage", "fire_rate", "range"], "maxed perk %s offered" % c)
		eq(unique.size(), s.choices.size(), "no duplicate cards: %s" % [s.choices])
		s.step({"pick": 0})
	for id in ["damage", "fire_rate", "range"]:
		var max_stacks := 0
		for row in s.rules.perks:
			if row["id"] == id:
				max_stacks = int(row["max_stacks"])
		ok(s.player.perk_stacks.get(id, 0) <= max_stacks, "%s within max stacks" % id)


func test_all_perks_maxed_means_no_pause() -> void:
	var s := _sim()
	for row in s.rules.perks:
		s.player.perk_stacks[row["id"]] = int(row["max_stacks"])
	_level_up(s)
	eq(s.level, 2)
	ok(s.choices.is_empty(), "nothing to offer, no pause")
	var t := s.tick
	s.step({})
	eq(s.tick, t + 1)


func test_several_levels_at_once_are_queued() -> void:
	var s := _sim()
	s.xp = s.xp_needed(1) + s.xp_needed(2) + s.xp_needed(3)
	s.step({})
	eq(s.level, 4, "three levels gained")
	eq(s.choices.size(), 3)
	eq(s.pending_levels, 2)
	s.step({"pick": 0})
	eq(s.choices.size(), 3, "second choice offered straight away")
	s.step({"pick": 0})
	s.step({"pick": 0})
	ok(s.choices.is_empty() and s.pending_levels == 0, "all three taken")
	var total := 0
	for k in s.player.perk_stacks:
		total += s.player.perk_stacks[k]
	eq(total, 3)


## 16 Oct: ceil made one Heavy Rounds pick double every 1-damage gun and stacks 2-5 add nothing to them. Over many
## shots the average must be base x (1 + bonus) for every stack count and every gun, and each stack must add.
func test_damage_perk_averages_its_percentage_on_every_gun() -> void:
	var row: Dictionary = {}
	for r in _sim().rules.perks:
		if r["id"] == "damage":
			row = r
	for gun in ["pistol", "smg", "shotgun", "railgun", "rocket"]:
		var last_total := -1
		for stacks in range(0, int(row["max_stacks"]) + 1):
			var s := _sim()
			s.player.set_weapon(gun)
			for i in stacks:
				s.player.apply_perk(row)
			var shots := 1200
			var total := 0
			for i in shots:
				total += s.player.shot_damage()
			var want: float = float(s.rules.weapons[gun]["damage"]) * (1.0 + row["amount"] * stacks) * shots
			ok(absf(total - want) <= 1.0, "%s with %d stacks: %d damage over %d shots, want %.1f" % [gun, stacks, total, shots, want])
			ok(total > last_total, "%s: stack %d adds damage (%d -> %d)" % [gun, stacks, last_total, total])
			last_total = total


func test_each_perk_changes_what_it_says() -> void:
	var rows := {}
	var s0 := _sim()
	for row in s0.rules.perks:
		rows[row["id"]] = row
	var s := _sim()
	s.player.set_weapon("railgun")
	var base_dmg := s.player.shot_damage()
	s.player.apply_perk(rows["damage"])
	eq(s.player.shot_damage(), int(floor(base_dmg * (1.0 + rows["damage"]["amount"]))), "damage perk, fraction carried")
	var hp := s.player.hp
	var max_hp := s.player.max_hp
	s.player.apply_perk(rows["vitality"])
	eq([s.player.max_hp, s.player.hp], [max_hp + 2, mini(max_hp + 2, hp + 2)], "vitality")
	eq(s.player.max_hp_cap(), int(s.rules.t("max_hp")) + 2, "cap raised")
	var armour := s.player.armor
	s.player.apply_perk(rows["plating"])
	eq(s.player.armor, armour + 3, "plating")
	s.player.apply_perk(rows["multishot"])
	s.player.apply_perk(rows["pierce"])
	s.player.apply_perk(rows["range"])
	var w: Dictionary = s.rules.weapons["pistol"]
	var fired := s.bullets.fire(0.0, 0.0, w, 1, s.player.mods)
	eq(fired, 2, "split shot: pistol fires 2")
	for b in s.bullets.pool:
		if b.active:
			eq(b.penetration, 2, "pierce +1")
			ok(absf(b.max_range - float(w["max_range"]) * (1.0 + rows["range"]["amount"])) < 1e-6, "range perk")
			ok(absf(b.vx) > 0.0, "split shot bullets fan out")


func test_perk_taken_event_and_xp_from_kills() -> void:
	var s := _sim()
	s.player.fire_timer = -1e9
	var e = s.enemies._inactive()
	s.enemies._activate(e, "armored", 0.0, 3.0)
	e.hp = 1
	var w: Dictionary = s.rules.weapons["pistol"].duplicate()
	s.bullets.fire(0.0, 0.0, w, 1)
	for i in 10:
		s.step({})
	eq(s.xp, int(s.rules.enemies["armored"]["score"]), "xp = enemy base score, not combo score")
	_level_up(s)
	s.step({"pick": 0})
	var taken := s.events.filter(func(ev): return ev["kind"] == Events.Kind.PERK_TAKEN)
	eq(taken.size(), 1)
