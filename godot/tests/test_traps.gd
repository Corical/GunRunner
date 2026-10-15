extends "res://tests/test_case.gd"
## Booby traps, written to break them: the debuff must really bite, really end, never stack, never fire
## after the trap was shot, never reach further because of Magnet, and the weave must stay on the road.

const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const Events = preload("res://scripts/sim/events.gd")
const K = Events.Kind


func _sim(tweak := {}, seed_value := 1) -> Sim:
	var rules := Loader.load_rules()
	assert(rules.ok(), "rules failed: %s" % [rules.errors])
	var t := {"upgrade_spawn_per_second": 0, "trap_spawn_per_second": 0, "boss_interval": 1e9}
	t.merge(tweak, true)
	for key in t:
		assert(rules.tuning.has(key), "unknown tweak " + key)
		rules.tuning[key] = float(t[key])
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	logger.add_sink(Sinks.Memory.new())
	var s := Sim.new(rules, seed_value, logger)
	s.enemies.pause_spawning()
	s.player.hp = 1000000
	s.player.max_hp = 1000000
	return s


## A trap of `id` placed at (x, z), not weaving (unless the test turns sway back on).
func _trap(s: Sim, id: String, x: float, z: float):
	ok(s.traps.spawn(id, s._emit), "trap pool full")
	var newest = null
	for t in s.traps.pool:
		if t.active and (newest == null or t.serial > newest.serial):
			newest = t
	newest.centre_x = x
	newest.x = x
	newest.prev_x = x
	newest.z = z
	newest.prev_z = z
	return newest


func _run(s: Sim, ticks: int, input := {}) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for i in ticks:
		s.step(input)
		all.append_array(s.events)
	return all


func _of(evs: Array[Dictionary], kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in evs:
		if e["kind"] == kind:
			out.append(e)
	return out


func _shots(s: Sim, ticks: int) -> int:
	return _of(_run(s, ticks), K.FIRED).size()


func test_jammer_halves_fire_rate_then_wears_off() -> void:
	var s := _sim({"trap_sway_amplitude": 0})
	var normal := _shots(s, 180)
	_trap(s, "jammer", s.player.x, s.player.z + 0.5)
	var evs := _run(s, 1)
	eq(_of(evs, K.TRAP_TRIGGERED).size(), 1, "touching a trap triggers it")
	var jammed := _shots(s, 180)
	ok(jammed <= normal / 2 + 1 and jammed >= normal / 2 - 2, "jammed %d shots vs normal %d in 3 s" % [jammed, normal])
	_run(s, 4 * 60)  # 6 s total jam has run out
	ok(not s.player.trap_left.has("jammer"), "jam ends")
	var after := _shots(s, 180)
	ok(absi(after - normal) <= 1, "fire rate back to normal: %d vs %d" % [after, normal])


func test_second_jammer_restarts_the_timer_instead_of_stacking() -> void:
	var s := _sim({"trap_sway_amplitude": 0})
	_trap(s, "jammer", s.player.x, s.player.z + 0.5)
	_run(s, 120)
	_trap(s, "jammer", s.player.x, s.player.z + 0.5)
	_run(s, 1)
	eq(s.player.trap_left.size(), 1, "a second Jammer must not stack")
	ok(absf(s.player.trap_left["jammer"] - (6.0 - 1.0 / 60.0)) < 0.02, "timer restarted to 6 s, got %f" % s.player.trap_left["jammer"])


func test_jinx_blocks_every_crit_then_crits_return() -> void:
	var s := _sim({"trap_sway_amplitude": 0})
	s.player.mods["crit_chance"] = 1.0
	_trap(s, "jinx", s.player.x, s.player.z + 0.5)
	_run(s, 1)
	ok(s.player.trap_left.has("jinx"), "jinxed")
	for i in 6:
		var e = s.enemies._inactive()
		s.enemies._activate(e, "shielded", s.player.x, 12.0 + i)
		e.hp = 100000
	var during := _of(_run(s, 5 * 60), K.CRIT)
	eq(during.size(), 0, "100% crit chance must give zero crits while jinxed")
	_run(s, 4 * 60)
	ok(not s.player.trap_left.has("jinx"), "jinx over")
	for i in 3:  # the first batch walked past the player by now
		var e2 = s.enemies._inactive()
		s.enemies._activate(e2, "shielded", s.player.x, 12.0 + i)
		e2.hp = 100000
	var after := _of(_run(s, 120), K.CRIT)
	ok(after.size() > 0, "crits come back after the jinx")


func test_shot_down_trap_never_applies_its_effect() -> void:
	var s := _sim({"trap_sway_amplitude": 0, "trap_hp": 1})
	var t = _trap(s, "jammer", s.player.x, 20.0)
	var evs := _run(s, 6 * 60)
	eq(_of(evs, K.TRAP_DESTROYED).size(), 1, "pistol destroys a 1-hp trap")
	eq(_of(evs, K.TRAP_TRIGGERED).size(), 0, "destroyed trap must not trigger")
	ok(s.player.trap_left.is_empty(), "no debuff")
	ok(not t.active, "gone")


func test_trap_stops_a_piercing_bullet() -> void:
	var s := _sim({"trap_sway_amplitude": 0, "trap_hp": 1000})
	s.player.fire_timer = -1e9  # only the bullet we place
	_trap(s, "jammer", 0.0, 10.0)
	var e = s.enemies._inactive()
	s.enemies._activate(e, "shielded", 0.0, 14.0)
	e.hp = 1000
	var w: Dictionary = s.rules.weapons["railgun"].duplicate()
	w["bullet_count"] = 1
	s.bullets.fire(0.0, 0.0, w, 30)
	var evs := _run(s, 30)
	eq(_of(evs, K.TRAP_HIT).size(), 1, "railgun hits the trap")
	eq(e.hp, 1000, "the trap took the bullet; the enemy behind is untouched")


func test_magnet_does_not_pull_traps_into_you() -> void:
	var s := _sim({"trap_sway_amplitude": 0, "upgrade_speed": 0})
	s.player.fire_timer = -1e9
	s.player.mods["pickup_mult"] = 1.5  # Magnet maxed
	_trap(s, "jammer", s.player.x + s.rules.t("pickup_dx") * 1.5, s.player.z)
	var evs := _run(s, 30)
	eq(_of(evs, K.TRAP_TRIGGERED).size(), 0, "outside base reach, Magnet must not widen it")


func test_weaving_traps_never_leave_the_road() -> void:
	var s := _sim({"trap_spawn_per_second": 3})
	var half := s.rules.t("road_width") / 2.0
	var seen := 0
	for i in 60 * 60:
		s.step({})
		for t in s.traps.pool:
			if t.active:
				seen += 1
				ok(absf(t.x) <= half, "trap at x=%f is off a road %f wide" % [t.x, half * 2])
	ok(seen > 1000, "test actually saw traps (%d samples)" % seen)


func test_traps_do_weave() -> void:
	var s := _sim()
	var t = _trap(s, "jinx", 0.0, 60.0)
	var xs := []
	for i in 300:
		s.step({})
		xs.append(t.x)
	ok(xs.max() - xs.min() > s.rules.t("trap_sway_amplitude"), "trap moved sideways %f" % (xs.max() - xs.min()))


func test_no_traps_during_a_boss() -> void:
	var s := _sim({"trap_spawn_per_second": 60, "boss_interval": 1})
	_run(s, 120)
	ok(s.boss.active, "boss started")
	for t in s.traps.pool:
		t.active = false
	_run(s, 120)
	var spawned := 0
	for t in s.traps.pool:
		if t.active:
			spawned += 1
	eq(spawned, 0, "no trap spawns while the boss is up")


func _rules_with(edit: Callable) -> Rules:
	var errors := PackedStringArray()
	var tables := Loader.load_tables(errors)
	edit.call(tables)
	return Rules.from_tables(tables)


## Fable review #18: a new trap cost 7 files. Now a new trap with an existing effect is one data row - prove it.
func test_a_new_trap_needs_only_a_data_row() -> void:
	var rules := _rules_with(func(t):
		t["traps"][0]["weight"] = 40
		t["traps"].append({"id": "sludge", "name": "Sludge", "effect": "fire_rate_mult", "amount": 0.3,
			"seconds": 3.0, "weight": 15, "label": "SLUDGED", "color": "#65A30D"}))
	ok(rules.ok(), "data-only trap accepted: %s" % [rules.errors])
	for key in ["upgrade_spawn_per_second", "trap_spawn_per_second"]:
		rules.tuning[key] = 0.0
	rules.tuning["boss_interval"] = 1e9
	rules.tuning["trap_sway_amplitude"] = 0.0
	var s := Sim.new(rules, 1, GLog.new())
	s.enemies.pause_spawning()
	s.player.hp = 1000000
	var normal := _shots(s, 120)
	_trap(s, "sludge", s.player.x, s.player.z + 0.5)
	_run(s, 1)
	ok(s.player.trap_left.has("sludge"), "sludge applied")
	var slowed := _shots(s, 120)
	ok(slowed <= int(normal * 0.3) + 1, "fire rate x0.3: %d vs %d" % [slowed, normal])
	_run(s, 120)
	ok(not s.player.trap_left.has("sludge"), "wears off after 3 s")


func test_bad_trap_rows_are_rejected() -> void:
	var r := _rules_with(func(t): t["traps"][0]["weight"] = 10)
	ok(not r.ok(), "weights not summing to 100")
	r = _rules_with(func(t): t["traps"][0]["effect"] = "explode")
	ok(not r.ok(), "unknown effect")
	r = _rules_with(func(t): t["traps"][0]["amount"] = 1.5)
	ok(not r.ok(), "a jammer that speeds you up")
	r = _rules_with(func(t): t["traps"][1]["seconds"] = 0.0)
	ok(not r.ok(), "zero-second trap")
