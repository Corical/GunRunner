extends "res://tests/test_case.gd"
## Sim tests written to break it: same-step ordering, every damage source, pools, the boss soft-lock,
## piercing re-hits, determinism. Scenarios are built by placing things directly in sim state.

const Sim = preload("res://scripts/sim/sim.gd")
const Loader = preload("res://scripts/data/rules_loader.gd")
const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")
const Events = preload("res://scripts/sim/events.gd")
const FrameClock = preload("res://scripts/sim/frame_clock.gd")
const K = Events.Kind


# ---------- helpers ----------

func _sim(seed_value := 1, tweak := {}) -> Sim:
	var rules := Loader.load_rules()
	assert(rules.ok(), "rules failed: %s" % [rules.errors])
	for key in tweak:
		assert(rules.tuning.has(key), "unknown tweak " + key)
		rules.tuning[key] = float(tweak[key])
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	logger.add_sink(Sinks.Memory.new())
	return Sim.new(rules, seed_value, logger)


## No spawning, no upgrades, no boss, no auto-fire, can't die: only what the test places exists.
func _quiet(tweak := {}, seed_value := 1) -> Sim:
	var t := {"upgrade_spawn_per_second": 0, "boss_interval": 1e9}
	t.merge(tweak, true)
	var s := _sim(seed_value, t)
	s.enemies.pause_spawning()
	s.player.fire_timer = -1e9
	s.player.hp = 1000000
	s.player.max_hp = 1000000
	return s


func _place(s: Sim, type_id: String, x: float, z: float):
	var e = s.enemies._inactive()
	assert(e != null, "enemy pool full in test")
	s.enemies._activate(e, type_id, x, z)
	return e


## One bullet of `weapon_id` (spread removed), at (x, z), already moving.
func _shoot(s: Sim, weapon_id: String, x: float, z: float, damage := -1):
	var w: Dictionary = s.rules.weapons[weapon_id].duplicate()
	w["bullet_count"] = 1
	var dmg: int = w["damage"] if damage < 0 else damage
	s.bullets.fire(x, z, w, dmg)
	var newest = null
	for b in s.bullets.pool:
		if b.active and (newest == null or b.serial > newest.serial):
			newest = b
	return newest


func _run(s: Sim, ticks: int, input := {}) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for i in ticks:
		s.step(input)
		all.append_array(s.events)
	return all


func _of(events: Array, kind: int) -> Array:
	return events.filter(func(e): return e["kind"] == kind)


# ---------- damage path (plan D2, D4) ----------

func test_bullet_kill_scores_once_and_builds_combo() -> void:
	var s := _quiet()
	var gains: Array = []
	for i in 3:
		_place(s, "basic", 3.0, 5.0)
		_shoot(s, "pistol", 3.0, 0.0)
		var ev := _run(s, 20)
		var killed := _of(ev, K.ENEMY_KILLED)
		eq(killed.size(), 1, "kill %d" % i)
		if killed.size() == 1:
			gains.append(killed[0]["score_gain"])
	eq(gains, [10, 10, 20], "combo 0 and 1 both multiply by 1, combo 2 by 2 (Babylon max(1, combo))")
	eq(s.score, 40)
	eq(s.kills, 3)
	eq(s.combo, 3)


func test_burn_kill_scores_like_any_kill() -> void:
	var s := _quiet()
	s.towers.deploy("freeze", 0.0, s._emit)
	s.towers.deploy("fire", 0.0, s._emit)
	_place(s, "basic", 0.0, 54.0)
	var ev := _run(s, 240)
	var killed := _of(ev, K.ENEMY_KILLED)
	eq(killed.size(), 1, "fire tower killed it")
	if killed.size() == 1:
		eq(killed[0]["source"], "burn")
		eq(killed[0]["score_gain"], 10)
	eq(s.kills, 1)
	eq(s.combo, 1, "tower kills build the combo too")


func test_poison_kill_after_the_tower_has_expired() -> void:
	var s := _quiet()
	s.towers.deploy("poison", 0.0, s._emit)
	s.towers.pool[0].time_left = 0.05
	_place(s, "basic", 0.0, 50.0)
	var ev := _run(s, 200)
	eq(_of(ev, K.TOWER_EXPIRED).size(), 1, "tower gone after 3 steps")
	var killed := _of(ev, K.ENEMY_KILLED)
	eq(killed.size(), 1, "lingering poison still kills")
	if killed.size() == 1:
		eq(killed[0]["source"], "poison")
	eq(s.score, 10)


func test_hit_number_is_damage_dealt_after_the_table() -> void:
	var s := _quiet()
	var e = _place(s, "armored", 0.0, 6.0)
	_shoot(s, "shotgun", 0.0, 0.0)
	var hits := _of(_run(s, 15), K.ENEMY_HIT)
	eq(hits.size(), 1)
	if hits.size() == 1:
		eq(hits[0]["amount"], 1, "shotgun 2 x 0.5 vs armored = 1, not the raw 2")
	eq(e.hp, 3)


func test_splash_uses_the_table_and_caps_victims() -> void:
	var s := _quiet()
	# The basic is nearest the rocket so it is hit first; 8 armored sit behind it, all within 3 of it.
	_place(s, "basic", 0.0, 27.0)
	for i in 8:
		_place(s, "armored", -1.0 + (i % 4) * 0.66, 28.0 + (i / 4) * 1.5)
	_shoot(s, "rocket", 0.0, 20.0)
	var killed := _of(_run(s, 20), K.ENEMY_KILLED)
	ok(not killed.is_empty() and killed[0]["enemy"] == "basic" and killed[0]["source"] == "bullet", "rocket hit the basic in front: %s" % [killed.slice(0, 1)])
	var by_source := {}
	for k in killed:
		by_source[k["source"]] = by_source.get(k["source"], 0) + 1
	eq(by_source.get("bullet", 0), 1, "the rocket hits one enemy")
	eq(by_source.get("splash", 0), 5, "splash capped at 5 victims of 8 in range")
	for k in killed:
		if k["source"] == "splash":
			eq(k["amount"], 8, "rocket splash 8/2 = 4, x2 vs armored = 8 (Babylon showed 1 and dealt 4)")
			break


# ---------- piercing (plan D12) ----------

func test_railgun_pierces_exactly_four() -> void:
	var s := _quiet()
	var line: Array = []
	for i in 5:
		line.append(_place(s, "armored", 0.0, 10.0 + i * 4.0))
	_shoot(s, "railgun", 0.0, 0.0)
	var killed := _of(_run(s, 60), K.ENEMY_KILLED)
	eq(killed.size(), 4, "penetration 4")
	ok(line[4].active, "fifth survives")


func test_piercing_bullet_never_hits_the_same_enemy_twice() -> void:
	var s := _quiet()
	var tank = _place(s, "shielded", 0.0, 10.0)
	tank.hp = 1000
	_shoot(s, "railgun", 0.0, 0.0)
	var hits := _of(_run(s, 40), K.ENEMY_HIT)
	eq(hits.size(), 1, "Babylon re-hit on every overlapping frame")
	eq(tank.hp, 1000 - 30)


func test_railgun_hits_boss_once_per_bullet() -> void:
	var s := _quiet({"boss_steer_speed": 0})
	s._start_boss()
	s.boss.z = 12.0
	var hp_before := s.boss.hp
	_shoot(s, "railgun", 0.0, 0.0)
	var hits := _of(_run(s, 30), K.BOSS_HIT)
	eq(hits.size(), 1, "one railgun bullet, one boss hit (Babylon: up to 4)")
	eq(s.boss.hp, hp_before - 15)


func test_second_bullet_same_step_ignores_dead_enemy() -> void:
	var s := _quiet()
	_place(s, "basic", 0.0, 1.5)
	var b1 = _shoot(s, "pistol", 0.0, 0.0)
	var b2 = _shoot(s, "pistol", 0.0, 0.0)
	var ev := _run(s, 1)
	eq(_of(ev, K.ENEMY_KILLED).size(), 1)
	eq(_of(ev, K.ENEMY_HIT).size(), 0, "dead enemy is not hit again")
	ok(not b1.active and b2.active, "only one bullet spent")


# ---------- swept collision in the sim (plan D9) ----------

func test_no_tunnelling_at_any_offset_inside_reach() -> void:
	var reach := 1.2 + 0.6  # bullet_hit_radius + basic radius
	var offset := -reach + 0.05
	while offset < reach:
		var s := _quiet()
		_place(s, "basic", offset, 20.0)
		_shoot(s, "pistol", 0.0, 0.0)
		var killed := _of(_run(s, 30), K.ENEMY_KILLED).size()
		ok(killed == 1, "offset %.2f: %d kills" % [offset, killed])
		offset += 0.1
	for far in [reach + 0.05, -reach - 0.05]:
		var s := _quiet()
		_place(s, "basic", far, 20.0)
		_shoot(s, "pistol", 0.0, 0.0)
		eq(_of(_run(s, 30), K.ENEMY_KILLED).size(), 0, "offset %.2f must miss" % far)


# ---------- boss (plan D13) ----------

func test_boss_cannot_be_dodged_forever_from_the_road_edge() -> void:
	var s := _sim(1, {"upgrade_spawn_per_second": 0})
	s.player.hp = 1000000
	s.player.max_hp = 1000000
	s.enemies.pause_spawning()
	s._start_boss()
	var ev := _run(s, 60 * 120, {"move": 1.0})
	ok(s.player.x > 6.9, "player held at the right edge")
	var defeated := _of(ev, K.BOSS_DEFEATED)
	ok(defeated.size() >= 1 and defeated[0]["wave"] == 1, "pistol from the edge kills wave 1 within 2 minutes: %s" % [defeated])
	var after_defeat := false
	var spawned_after := 0
	for e in ev:
		if e["kind"] == K.BOSS_DEFEATED:
			after_defeat = true
		elif after_defeat and e["kind"] == K.ENEMY_SPAWNED:
			spawned_after += 1
	ok(spawned_after > 0, "enemy spawning resumes after the boss")


func test_dodged_boss_wraps_round_without_damage() -> void:
	var s := _quiet({"boss_steer_speed": 0})
	s._start_boss()
	s.player.x = 7.0
	var hp := s.player.hp
	var ev := _run(s, 60 * 40)
	var wraps := _of(ev, K.BOSS_WRAPPED).size()
	ok(wraps >= 1 and wraps <= 3, "a lap is ~25 s, so 1-3 wraps in 40 s, got %d" % wraps)
	ok(s.boss.z > s.player.z, "boss is in front of the player again (z %.1f)" % s.boss.z)
	eq(_of(ev, K.PLAYER_HURT).size(), 0, "dodging is not punished")
	eq(s.player.hp, hp)
	ok(s.boss.active, "fight still on")


func test_boss_contact_hurts_once_and_pushes_back() -> void:
	var s := _quiet({"boss_steer_speed": 0})
	s._start_boss()
	s.boss.x = s.player.x
	s.boss.z = s.player.z + 3.9
	var ev := _run(s, 30)
	var hurt := _of(ev, K.PLAYER_HURT)
	eq(hurt.size(), 1, "one contact in half a second")
	if hurt.size() == 1:
		eq(hurt[0]["amount"], 3)
		eq(hurt[0]["source"], "boss")


func test_boss_killed_by_first_of_several_bullets_in_one_step() -> void:
	var s := _quiet({"boss_steer_speed": 0})
	s._start_boss()
	s.boss.hp = 1
	s.boss.z = 1.0
	var score_before := s.score
	for i in 3:
		_shoot(s, "pistol", 0.0, 0.0)
	var ev := _run(s, 1)
	eq(_of(ev, K.BOSS_DEFEATED).size(), 1)
	eq(_of(ev, K.BOSS_HIT).size(), 1, "no hits on a dead boss")
	eq(_of(ev, K.UPGRADE_SPAWNED).size(), 1, "guaranteed drop, once")
	eq(s.score - score_before, 500)
	eq(s.kills, 0, "boss is not counted as a kill (Babylon parity)")


func test_boss_starts_once_and_not_again_while_active() -> void:
	var s := _quiet({"boss_interval": 500})
	s.distance = 499.9
	eq(_of(_run(s, 1), K.BOSS_STARTED).size(), 0, "trigger is checked before distance grows (step 13 before 14)")
	var ev := _run(s, 1)
	eq(_of(ev, K.BOSS_STARTED).size(), 1, "starts on the next step at 500.1")
	s.distance = 1200.0
	eq(_of(_run(s, 10), K.BOSS_STARTED).size(), 0, "no second boss while one is active")
	eq(s.boss.hp, 70, "wave 1 hp = 50 + 20")


func test_boss_hp_grows_per_wave() -> void:
	var s := _quiet()
	s.boss.activate(2)
	eq(s.boss.max_hp, 90)


# ---------- same-step order (sim.gd header) ----------

func test_enemy_killed_in_the_step_it_reaches_the_player_does_no_harm() -> void:
	var s := _quiet()
	s.player.hp = 5
	_place(s, "basic", s.player.x, s.player.z + 1.4)
	_shoot(s, "pistol", s.player.x, s.player.z + 0.5)
	var ev := _run(s, 1)
	eq(_of(ev, K.ENEMY_KILLED).size(), 1)
	eq(_of(ev, K.PLAYER_HURT).size(), 0)


func test_heal_in_the_same_step_as_a_hit_is_applied_first() -> void:
	var s := _quiet()
	s.player.hp = 1
	s.player.max_hp = 5
	s.upgrades.spawn("heal", s._emit)
	var u = s.upgrades.pool[0]
	u.thawed = true
	u.x = s.player.x
	u.z = s.player.z + 0.1
	_place(s, "basic", s.player.x, s.player.z + 1.4)
	var ev := _run(s, 1)
	eq(_of(ev, K.PICKUP).size(), 1)
	eq(_of(ev, K.PLAYER_HURT).size(), 1)
	eq(s.player.hp, 2, "1 + 2 heal - 1 hit")
	ok(not s.over, "survives")


func test_nothing_happens_after_game_over() -> void:
	var s := _quiet()
	s.player.hp = 1
	_place(s, "basic", s.player.x, s.player.z + 1.4)
	var ev := _run(s, 1)
	eq(_of(ev, K.GAME_OVER).size(), 1)
	var tick := s.tick
	_run(s, 10)
	eq(s.events.size(), 0)
	eq(s.tick, tick, "tick frozen")


func test_enemy_contact_breaks_combo() -> void:
	var s := _quiet()
	s.combo = 4
	_place(s, "basic", s.player.x, s.player.z + 1.4)
	var ev := _run(s, 1)
	eq(_of(ev, K.COMBO_BROKEN).size(), 1)
	eq(s.combo, 0)


# ---------- player ----------

func test_armor_absorbs_first() -> void:
	var s := _quiet()
	s.player.hp = 5
	s.player.armor = 3
	s.player.take_damage(3)
	eq([s.player.hp, s.player.armor], [5, 0])
	s.player.armor = 1
	s.player.take_damage(3)
	eq([s.player.hp, s.player.armor], [3, 0])


func test_buffs_reset_not_stack_and_caps_hold() -> void:
	var s := _quiet()
	s.player.start_frenzy(8.0)
	_run(s, 180)
	s.player.start_frenzy(8.0)
	ok(absf(s.player.frenzy_timer - 8.0) < 1e-9, "re-pick resets to 8 s, not 13 s")
	s.player.max_hp = 12
	s.player.hp = 12
	s.player.add_max_hp(1)
	eq([s.player.hp, s.player.max_hp], [12, 12], "max HP capped at 12")
	s.player.hp = 11
	s.player.heal(2)
	eq(s.player.hp, 12, "heal capped at max")


func test_weapon_swap_resets_fire_timer() -> void:
	var s := _quiet()
	s.player.fire_timer = 0.3
	s.player.set_weapon("laser")
	eq(s.player.fire_timer, 0.0)


func test_fire_rate_matches_the_computed_step_table() -> void:
	var expected := {
		"pistol": 20, "smg": 8, "shotgun": 31, "laser": 5, "rocket": 40,
		"minigun": 3, "railgun": 75, "flamethrower": 4, "grenade": 50,
	}
	var buffed := {"laser": 4, "flamethrower": 3, "pistol": 14}
	for w in expected:
		eq(_steps_per_shot(w, false), expected[w], w)
	for w in buffed:
		eq(_steps_per_shot(w, true), buffed[w], w + " with speed buff")


func _steps_per_shot(weapon_id: String, buffed: bool) -> int:
	var s := _quiet()
	s.player.set_weapon(weapon_id)
	if buffed:
		s.player.start_speed_buff(100.0)
	for n in range(1, 200):
		s.player.update_timers(Sim.STEP)
		if s.player.try_fire():
			return n
	return -1


func test_frenzy_doubles_shot_damage_rounding_up() -> void:
	var s := _quiet()
	s.player.set_weapon("railgun")
	s.player.start_frenzy(5.0)
	eq(s.player.shot_damage(), 30)


func test_bad_input_is_ignored() -> void:
	eq(Sim._axis(NAN), 0.0)
	eq(Sim._axis(INF), 0.0)
	eq(Sim._axis("left"), 0.0)
	eq(Sim._axis(5.0), 1.0)
	eq(Sim._axis(-2), -1.0)
	eq(Sim._axis(0.5), 0.5)


func test_keys_accelerate_and_ease_to_a_stop() -> void:
	var s := _quiet()
	s.player.x = -7.0  # room to run: from the centre it would hit the edge (which zeroes speed) before the check
	_run(s, 1, {"move": 1.0})
	ok(s.player.vx > 0.0 and s.player.vx < 15.0, "first step is not full speed: %f" % s.player.vx)
	_run(s, 30, {"move": 1.0})
	ok(absf(s.player.vx - 15.0) < 1e-6, "reaches key speed 15: %f" % s.player.vx)
	_run(s, 1, {})
	ok(s.player.vx > 0.0, "does not stop dead on release")
	_run(s, 30, {})
	eq(s.player.vx, 0.0, "stopped after release")


func test_drag_reaches_target_without_overshoot() -> void:
	for target in [5.0, -6.5, 0.3, -0.3]:
		var s := _quiet()
		var start: float = s.player.x
		var worst_past := 0.0
		for i in 120:
			s.step({"target_x": target})
			var past: float = (s.player.x - target) * signf(target - start)
			worst_past = maxf(worst_past, past)
		ok(absf(s.player.x - target) < 1e-3, "drag to %.1f ended at %f" % [target, s.player.x])
		ok(worst_past <= 1e-6, "drag to %.1f overshot by %f" % [target, worst_past])


func test_drag_target_off_the_road_stops_at_the_edge() -> void:
	var s := _quiet()
	_run(s, 120, {"target_x": 50.0})
	eq(s.player.x, 7.0)
	eq(s.player.vx, 0.0, "no leftover speed pushing into the edge")


func test_drag_wins_over_keys_and_bad_targets_are_ignored() -> void:
	var s := _quiet()
	_run(s, 120, {"move": 1.0, "target_x": -3.0})
	ok(absf(s.player.x + 3.0) < 1e-3, "drag target beats the key axis: %f" % s.player.x)
	for bad in [NAN, INF, -INF, "left", null]:
		var b := _quiet()
		_run(b, 30, {"target_x": bad, "move": 1.0})
		ok(b.player.x > 1.0, "target %s ignored, keys still steer: x=%f" % [bad, b.player.x])


func test_player_stays_on_the_road() -> void:
	var s := _quiet()
	_run(s, 120, {"move": 1.0})
	eq(s.player.x, 7.0)
	_run(s, 240, {"move": -1.0})
	eq(s.player.x, -7.0)


# ---------- towers ----------

func test_two_freeze_towers_do_not_multiply_slow() -> void:
	var s := _quiet()
	s.towers.deploy("freeze", 0.0, s._emit)
	s.towers.deploy("freeze", 0.0, s._emit)
	var e = _place(s, "basic", 0.0, 50.0)
	_run(s, 3)
	var z0: float = e.z
	_run(s, 1)
	ok(absf((z0 - e.z) - 10.0 * 0.4 / 60.0) < 1e-6, "moved %f per step, want %f" % [z0 - e.z, 10.0 * 0.4 / 60.0])


func test_slow_applies_one_step_late() -> void:
	var s := _quiet()
	s.towers.deploy("freeze", 0.0, s._emit)
	var e = _place(s, "basic", 0.0, 50.0)
	var z0: float = e.z
	_run(s, 1)
	ok(absf((z0 - e.z) - 10.0 / 60.0) < 1e-6, "first step at full speed (Babylon order)")
	z0 = e.z
	_run(s, 1)
	ok(absf((z0 - e.z) - 4.0 / 60.0) < 1e-6, "second step slowed")


func test_poison_reapply_keeps_the_tick_timer_running() -> void:
	var s := _quiet()
	var e = _place(s, "armored", 0.0, 50.0)
	e.poison_timer = 3.0
	e.poison_tick_timer = 1.5
	s.towers.deploy("poison", 0.0, s._emit)
	var ev := _run(s, 32)
	ok(e.poison_timer > 7.0, "duration topped up to 8")
	eq(_of(ev, K.ENEMY_HIT).size(), 1, "ticked after the remaining 0.5 s, not a fresh 2 s")


func test_full_tower_slots_still_use_up_the_pickup() -> void:
	var s := _quiet()
	for i in 6:
		s.towers.deploy("fire", 0.0, s._emit)
	s.upgrades.spawn("freeze", s._emit)
	var u = s.upgrades.pool[0]
	u.thawed = true
	u.x = s.player.x
	u.z = s.player.z
	var ev := _run(s, 1)
	eq(_of(ev, K.PICKUP).size(), 1)
	eq(_of(ev, K.POOL_EXHAUSTED).size(), 1)
	eq(_of(ev, K.TOWER_DEPLOYED).size(), 0)
	ok(not u.active, "pickup consumed")


# ---------- spawning ----------

func test_band_boundaries() -> void:
	var s := _quiet()
	var cases := {0.0: "early", 149.9: "early", 150.0: "mid", 399.99: "mid", 400.0: "late", 800.0: "endgame", 5000.0: "endgame"}
	for d in cases:
		eq(s.enemies._band_for(d)["id"], cases[d], "distance %s" % d)


func test_wave_size_grows_with_distance() -> void:
	var cases := {0.0: 1, 299.0: 1, 300.0: 2, 600.0: 3, 10000.0: 3}
	for d in cases:
		var s := _quiet()
		var spawned := [0]  # lambdas capture ints by value; an Array is shared
		s.enemies._spawn_wave(d, func(kind, _f): if kind == K.ENEMY_SPAWNED: spawned[0] += 1)
		eq(spawned[0], cases[d], "distance %s" % d)


func test_spawn_gap_mostly_respected() -> void:
	var s := _quiet()
	var close := 0
	var pairs := 0
	for w in 300:
		for e in s.enemies.pool:
			e.active = false
		s.enemies._spawn_wave(1000.0, func(_k, _f): pass)
		var xs: Array = []
		for e in s.enemies.pool:
			if e.active:
				xs.append(e.x)
		for i in xs.size():
			for j in range(i + 1, xs.size()):
				pairs += 1
				if absf(xs[i] - xs[j]) < 2.5:
					close += 1
	ok(pairs == 900, "300 waves of 3")
	ok(close <= pairs / 50, "%d of %d pairs closer than 2.5" % [close, pairs])


func test_full_enemy_pool_skips_and_logs() -> void:
	var s := _quiet()
	for i in 30:
		_place(s, "basic", 0.0, 100.0)
	var spawned := [0]
	s.enemies._spawn_wave(1000.0, func(_k, _f): spawned[0] += 1)
	eq(spawned[0], 0)
	eq(s.enemies.exhausted_count, 1)
	eq(s.enemies.active_count(), 30)
	# The counter itself works: free one slot and the next wave places exactly one.
	s.enemies.pool[0].active = false
	s.enemies._spawn_wave(1000.0, func(_k, _f): spawned[0] += 1)
	eq(spawned[0], 1, "counter proven live")


func test_spawn_interval_formula_and_manual_override_survives_boss() -> void:
	var s := _quiet()
	eq(s.enemies._auto_interval(500.0), 1.3)
	eq(s.enemies._auto_interval(2000.0), 0.8)
	s.enemies.set_manual_interval(3.0)
	s.enemies.pause_spawning()
	s.enemies.resume_spawning(600.0)
	eq(s.enemies.spawn_interval, 3.0, "Babylon reset this to the auto value after a boss")
	s.enemies.set_manual_interval(0.0)
	s.enemies.resume_spawning(500.0)
	eq(s.enemies.spawn_interval, 1.3, "back to auto")


func test_spawn_roll_matches_weights() -> void:
	var s := _quiet()
	for band in s.rules.spawn_bands:
		var counts := {}
		var n := 50000
		for i in n:
			var t: String = s.enemies._roll_type(band)
			counts[t] = counts.get(t, 0) + 1
		for pair in band["weights"]:
			var share: float = counts.get(pair[0], 0) * 100.0 / n
			ok(absf(share - pair[1]) < 0.8, "%s %s: %.2f%% vs %d%%" % [band["id"], pair[0], share, pair[1]])


# ---------- upgrades ----------

func test_reward_roll_matches_weights() -> void:
	var s := _quiet()
	var counts := {}
	var n := 100000
	for i in n:
		var r: String = s.upgrades._roll()["id"]
		counts[r] = counts.get(r, 0) + 1
	for row in s.rules.rewards:
		var share: float = counts.get(row["id"], 0) * 100.0 / n
		ok(absf(share - row["weight"]) < 0.5, "%s: %.2f%% vs %d%%" % [row["id"], share, row["weight"]])


func test_upgrade_rate_per_second_and_none_during_boss() -> void:
	var s := _quiet({"upgrade_spawn_per_second": 0.48, "upgrade_pool": 400})
	var spawned := _of(_run(s, 36000), K.UPGRADE_SPAWNED).size()
	ok(spawned >= 230 and spawned <= 346, "10 sim-minutes: %d spawns, expect 288 +- 58" % spawned)

	var b := _quiet({"upgrade_spawn_per_second": 0.48, "boss_steer_speed": 0})
	b._start_boss()
	b.boss.hp = 1000000
	b.boss.max_hp = 1000000
	b.player.x = 7.0
	eq(_of(_run(b, 3600), K.UPGRADE_SPAWNED).size(), 0, "no upgrades during a boss")


func test_ice_stops_even_a_railgun_bullet() -> void:
	var s := _quiet()
	s.upgrades.spawn("heal", s._emit)
	var u = s.upgrades.pool[0]
	u.x = 0.0
	u.z = 5.0
	var b = _shoot(s, "railgun", 0.0, 0.0)
	var ev := _run(s, 10)
	eq(_of(ev, K.ICE_SHATTERED).size(), 1, "15 damage shatters 8 ice hp")
	ok(not b.active, "bullet stopped by ice despite penetration 4")


# ---------- determinism and structure ----------

func _input_for(tick: int) -> Dictionary:
	return {"move": sin(tick * 0.013) * 1.3}


func test_same_seed_same_state_every_step() -> void:
	var a := _sim(42)
	var b := _sim(42)
	a.player.hp = 1000000
	b.player.hp = 1000000
	for t in 3600:
		a.step(_input_for(a.tick))
		b.step(_input_for(b.tick))
		if a.state_hash() != b.state_hash():
			fail("diverged at tick %d" % a.tick)
			return
	ok(a.kills > 0 and a.distance > 700.0, "the run actually played: kills=%d distance=%.0f" % [a.kills, a.distance])
	var c := _sim(43)
	c.player.hp = 1000000
	for t in 3600:
		c.step(_input_for(c.tick))
	ok(c.state_hash() != a.state_hash(), "different seed, different game")


func test_frame_rate_does_not_change_the_game() -> void:
	var hashes := {}
	for fps in [30.0, 60.0, 144.0]:
		var s := _sim(9)
		s.player.hp = 1000000
		var clock := FrameClock.new()
		while s.tick < 1800:
			var n := clock.advance(1.0 / fps)
			for i in n:
				if s.tick < 1800:
					s.step(_input_for(s.tick))
		hashes[fps] = s.state_hash()
	eq(hashes[30.0], hashes[60.0], "30 vs 60 fps")
	eq(hashes[144.0], hashes[60.0], "144 vs 60 fps")


func test_every_sim_part_logs_to_the_same_logger() -> void:
	var s := _sim()
	for part in [s.player, s.bullets, s.enemies, s.towers, s.upgrades, s.boss]:
		ok(part._log == s._log, "%s has the run logger" % part.get_script().resource_path)
