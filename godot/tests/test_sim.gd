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
		if key.begins_with("boss."):  # a bosses.tsv column, set on every boss
			var col: String = key.trim_prefix("boss.")
			for row in rules.bosses:
				assert(row.has(col), "unknown boss column " + col)
				row[col] = tweak[key]
			continue
		assert(rules.tuning.has(key), "unknown tweak " + key)
		rules.tuning[key] = float(tweak[key])
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	logger.add_sink(Sinks.Memory.new())
	return Sim.new(rules, seed_value, logger)


## No spawning, no upgrades, no boss, no auto-fire, can't die: only what the test places exists.
func _quiet(tweak := {}, seed_value := 1) -> Sim:
	var t := {"upgrade_spawn_per_second": 0, "trap_spawn_per_second": 0, "boss_interval": 1e9}
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


## Fable review #16: towers.tsv's damage column was read only as on/off; burn and poison always dealt 1, while the
## Enemy Guide showed the column. The number in the data must be the number in the game.
func test_tower_damage_comes_from_the_data() -> void:
	var s := _quiet()
	s.rules.towers["fire"]["burn_damage"] = 3
	s.rules.towers["poison"]["poison_damage"] = 4
	s.towers.deploy("fire", 0.0, s._emit)
	var burnt = _place(s, "shielded", 0.0, 54.0)
	burnt.hp = 1000
	s.enemies.pool[0].slow_mult = 1.0
	var hits := _of(_run(s, 120), K.ENEMY_HIT)
	var burns := hits.filter(func(h): return h["source"] == "burn")
	ok(burns.size() > 0, "fire tower burned")
	for h in burns:
		eq(h["amount"], 3, "burn deals the data's burn_damage")
	var s2 := _quiet()
	s2.rules.towers["poison"]["poison_damage"] = 4
	s2.towers.deploy("poison", 0.0, s2._emit)
	var p = _place(s2, "shielded", 0.0, 54.0)
	p.hp = 1000
	var poisons := _of(_run(s2, 300), K.ENEMY_HIT).filter(func(h): return h["source"] == "poison")
	ok(poisons.size() > 0, "poison ticked")
	for h in poisons:
		eq(h["amount"], 4, "poison deals the data's poison_damage")


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
	var tank = _place(s, "armored", 0.0, 10.0)
	tank.hp = 1000
	_shoot(s, "railgun", 0.0, 0.0)
	var hits := _of(_run(s, 40), K.ENEMY_HIT)
	eq(hits.size(), 1, "Babylon re-hit on every overlapping frame")
	eq(tank.hp, 1000 - 30)


## Fable review #3: hits went in pool-slot order. The enemy BEHIND sits in the lower slot here, so the old code
## gave it the bullet; the one in front must take it.
func test_bullet_hits_the_enemy_in_front_not_the_lower_pool_slot() -> void:
	# A fast bullet (6.7 m per step) whose single step passes through both circles - at normal speed it would
	# reach the front one a step earlier and the order would never matter.
	var s := _quiet({"bullet_speed": 400})
	var behind = _place(s, "armored", 0.0, 13.0)   # slot 0
	var front = _place(s, "armored", 0.0, 10.0)    # slot 1
	behind.hp = 1000
	front.hp = 1000
	_shoot(s, "pistol", 0.0, 6.0, 5)
	_run(s, 1)
	eq(front.hp, 995, "front enemy takes the hit")
	eq(behind.hp, 1000, "enemy behind is untouched")


func test_splash_hits_nearest_victims_not_lowest_slots() -> void:
	var s := _quiet({"splash_max_victims": 1})
	var far = _place(s, "armored", 2.4, 20.0)   # lower slot, further from the blast
	var near = _place(s, "armored", 0.8, 20.0)
	var target = _place(s, "armored", 0.0, 20.0)
	for e in [far, near, target]:
		e.hp = 1000
	_shoot(s, "rocket", 0.0, 12.0, 40)
	_run(s, 30)
	ok(target.hp < 1000, "rocket hit the target")
	ok(near.hp < 1000, "nearest neighbour splashed")
	eq(far.hp, 1000, "only 1 victim allowed, and it must be the nearest")


## The crit number on screen must be the damage actually dealt, and a non-crit must never show one.
func test_crit_event_matches_damage_dealt_and_only_on_crits() -> void:
	var s := _quiet()
	s.player.mods["crit_chance"] = 1.0
	var tank = _place(s, "armored", 0.0, 10.0)
	tank.hp = 1000
	_shoot(s, "pistol", 0.0, 0.0, 7)
	var evs := _run(s, 40)
	var crits := _of(evs, K.CRIT)
	eq(crits.size(), 1, "one crit per crit hit")
	eq(int(crits[0]["amount"]), 1000 - tank.hp, "number shown = damage dealt")
	eq(int(crits[0]["amount"]), 14, "doubled")

	var s2 := _quiet()
	s2.player.mods["crit_chance"] = 0.0
	var t2 = _place(s2, "armored", 0.0, 10.0)
	t2.hp = 1000
	_shoot(s2, "pistol", 0.0, 0.0, 7)
	eq(_of(_run(s2, 40), K.CRIT).size(), 0, "no crit chance, no crit pop")


func test_railgun_hits_boss_once_per_bullet() -> void:
	var s := _quiet({"boss.steer": 0.0})
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
	var ev := _run(s, 60 * 120, {"move": 1.0, "pick": 0})  # pick: take the first boss-loot card
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
	var s := _quiet({"boss.steer": 0.0})
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


## A juggernaut coming straight at you, dodged late: it is 6 m away when you start moving to the edge.
## Returns how often the boss hurt you before it went past (or 40 s ran out).
func _late_dodge_hits(contact_dx: float, dodge: bool) -> int:
	var s := _quiet({"boss.contact_dx": contact_dx})
	ok(s.start_boss_now("juggernaut"), "juggernaut row exists")
	s.boss.hp = 1000000
	s.boss.max_hp = 1000000
	s.player.x = 0.0
	s.boss.x = 0.0
	var hits := 0
	for i in 60 * 40:  # it spawns ~83 m out at 3.5 m/s: ~24 s to arrive
		var move := 1.0 if dodge and s.boss.z - s.player.z < 6.0 else 0.0
		s.step({"move": move})
		for e in s.events:
			if e["kind"] == K.PLAYER_HURT and e["source"] == "boss":
				hits += 1
			if e["kind"] == K.BOSS_WRAPPED:
				return hits
	return hits


## 16 Oct: the juggernaut hit Corne 4 times in 4.4 s standing in line, and at 6 m wide moving could not save him.
func test_juggernaut_hits_you_in_line_and_a_late_sidestep_dodges_it() -> void:
	ok(_late_dodge_hits(2.5, false) >= 1, "standing in its path gets you hit")
	eq(_late_dodge_hits(2.5, true), 0, "moving away when it is 6 m out clears it")
	ok(_late_dodge_hits(6.0, true) >= 1, "the old 6 m width caught the same dodge (this test can tell)")


func test_boss_contact_hurts_once_and_pushes_back() -> void:
	var s := _quiet({"boss.steer": 0.0})
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
	var s := _quiet({"boss.steer": 0.0})
	s._start_boss()
	s.boss.hp = 1
	s.boss.z = 1.0
	var score_before := s.score
	for i in 3:
		_shoot(s, "pistol", 0.0, 0.0)
	var ev := _run(s, 1)
	eq(_of(ev, K.BOSS_DEFEATED).size(), 1)
	eq(_of(ev, K.BOSS_HIT).size(), 1, "no hits on a dead boss")
	eq(_of(ev, K.LOOT_OFFERED).size(), 1, "boss loot, once")
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
	eq(s.boss.hp, 240, "wave 1 hp = 200 + 40")


func test_boss_hp_grows_per_wave() -> void:
	var s := _quiet()
	s.boss.activate(2)
	eq(s.boss.row["id"], "summoner", "wave 2 is the second boss in bosses.tsv")
	eq(s.boss.max_hp, 224, "(200 + 40 x 2) x 0.8")
	s.boss.activate(5)
	eq(s.boss.row["id"], "brute", "after the last boss the order starts again")
	eq(s.boss.max_hp, 400, "...with more hp: (200 + 40 x 5) x 1.0")
	s.boss.activate(5, 2.5)
	eq(s.boss.max_hp, 1000, "the distance growth multiplies the whole thing: 400 x 2.5")


# ---------- boss types ----------

## Puts the boss of `id` on the road at its hold distance, with huge hp so the test decides when it dies.
func _boss_fight(id: String, tweak := {}) -> Sim:
	var s := _quiet(tweak)
	var wave := 1
	for i in s.rules.bosses.size():
		if s.rules.bosses[i]["id"] == id:
			wave = i + 1
	s.boss.activate(wave)
	s.boss.hp = 1000000
	s.boss.max_hp = 1000000
	return s


func test_holding_boss_stops_at_its_distance_and_never_touches_you() -> void:
	for id in ["summoner", "gunner"]:
		var s := _boss_fight(id, {"boss.shoot_every": 0.0, "boss.summon_every": 0.0, "boss.hold_seconds": 1000.0})
		var ev := _run(s, 60 * 30)
		var hold: float = s.boss.row["hold_z"]
		ok(is_equal_approx(s.boss.z, s.player.z + hold), "%s holds at %.1f, is at %.2f" % [id, hold, s.boss.z - s.player.z])
		eq(_of(ev, K.BOSS_CONTACT).size(), 0, id + " never reaches you")
		eq(_of(ev, K.BOSS_WRAPPED).size(), 0, id + " never passes you")


## A holder you cannot kill must not be an endless fight (a bot farmed a Summoner's minions for 20 minutes):
## once hold_seconds run out it stops calling and shooting and walks into you.
func test_holder_runs_out_of_patience_and_charges() -> void:
	for id in ["summoner", "gunner"]:
		var s := _boss_fight(id, {"boss.hold_seconds": 5.0})
		s.player.x = 0.0
		var contacts := 0
		var charging := false
		var calls_while_charging := 0
		for i in 60 * 40:
			s.step({})
			for e in s.events:
				if e["kind"] == K.BOSS_CONTACT:
					contacts += 1
				if charging and e["kind"] in [K.BOSS_SUMMONED, K.BOSS_SHOT]:
					calls_while_charging += 1
			charging = charging or not s.boss.holds()
		ok(charging, id + " started charging")
		ok(contacts >= 1, id + " reached you after its patience ran out")
		eq(calls_while_charging, 0, id + " stops summoning and shooting once it charges")


func test_charging_boss_still_reaches_you() -> void:
	var s := _boss_fight("juggernaut")
	s.player.x = 0.0
	var ev := _run(s, 60 * 30)
	ok(_of(ev, K.BOSS_CONTACT).size() >= 1, "the juggernaut walks into you")
	for e in _of(ev, K.PLAYER_HURT):
		eq(e["amount"], 4, "juggernaut hits for its own contact_damage")
		eq(e["by"], "juggernaut")


func test_summoner_calls_minions_on_its_timer_only_once_in_position() -> void:
	var s := _boss_fight("summoner")
	var every: float = s.boss.row["summon_every"]
	var travel: float = (s.boss.z - s.player.z - s.boss.row["hold_z"]) / s.boss.row["speed"]
	var ev := _run(s, int(60 * (travel + every * 3.5)))
	var calls := _of(ev, K.BOSS_SUMMONED)
	eq(calls.size(), 3, "three calls in 3.5 periods after arriving")
	var spawned := _of(ev, K.ENEMY_SPAWNED)
	eq(spawned.size(), 3 * int(s.boss.row["summon_count"]))
	for e in spawned:
		eq(e["enemy"], s.boss.row["summon_enemy"])
		ok(absf(e["x"]) <= s.rules.t("road_width") / 2.0, "minion on the road")


func test_summons_with_a_full_enemy_pool_place_none_and_say_so() -> void:
	var s := _boss_fight("summoner")
	for e in s.enemies.pool:
		s.enemies._activate(e, "basic", 0.0, 500.0)  # far away, never reaches the player in this test
		e.slow_mult = 0.0
	var ev := _run(s, 60 * 20)
	var calls := _of(ev, K.BOSS_SUMMONED)
	ok(calls.size() >= 1, "it tried")
	for c in calls:
		eq(c["count"], 0, "nothing placed")


func test_gunner_shot_hits_a_player_who_stands_still() -> void:
	var s := _boss_fight("gunner", {"boss.strafe": 0.0})
	s.player.hp = 10
	s.player.max_hp = 10
	var ev := _run(s, 60 * 20)
	var shots := _of(ev, K.BOSS_SHOT).size()
	var hits := 0
	for e in _of(ev, K.PLAYER_HURT):
		eq(e["by"], "gunner_shot")
		hits += 1
	ok(shots >= 2, "it fired (%d)" % shots)
	ok(hits >= 1, "standing still gets you shot (%d hits from %d shots)" % [hits, shots])


func test_gunner_shot_misses_a_player_who_steps_aside() -> void:
	var s := _boss_fight("gunner", {"boss.strafe": 0.0, "boss.shoot_every": 100.0})
	s.boss.shoot_timer = 0.0  # fire on the first step it is in position, then not again in this test
	var fired := false
	var hurt := 0
	for i in 60 * 20:
		s.step({})
		for e in s.events:
			if e["kind"] == K.BOSS_SHOT:
				fired = true
				s.player.x = 3.0  # step 3 m aside right after the shot leaves
			if e["kind"] == K.PLAYER_HURT:
				hurt += 1
	ok(fired, "it fired")
	eq(hurt, 0, "a 3 m step clears the shot")


func test_shots_vanish_when_the_boss_dies() -> void:
	var s := _boss_fight("gunner", {"boss.strafe": 0.0})
	for i in 60 * 20:
		s.step({})
		var flying := false
		for sh in s.boss.shots:
			flying = flying or sh.active
		if flying:
			break
	var any := false
	for sh in s.boss.shots:
		any = any or sh.active
	ok(any, "a shot is in the air")
	s.boss.hp = 1
	_shoot(s, "railgun", s.boss.x, s.boss.z - 6.0)
	_run(s, 30)
	ok(not s.boss.active, "boss down")
	for sh in s.boss.shots:
		ok(not sh.active, "no shot outlives its boss")


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
	# Steps between shots at 60 Hz, computed independently in Python for the rates in weapons.tsv.
	var expected := {
		"pistol": 20, "smg": 10, "shotgun": 31, "laser": 9, "rocket": 40,
		"minigun": 5, "railgun": 75, "flamethrower": 8, "grenade": 50,
	}
	var buffed := {"laser": 6, "flamethrower": 5, "pistol": 14, "minigun": 3}
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


func test_frenzy_doubles_shot_damage() -> void:
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
	for raw_target in [5.0, -6.5, 0.3, -0.3]:
		var target: float = snappedf(raw_target, Sim.INPUT_GRID)  # the sim rounds inputs to the grid
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

func test_enemy_hp_grows_with_distance() -> void:
	var s := _quiet({"enemy_hp_per_100m": 0.12, "enemy_hp_growth_per_100m": 1.0})
	var cases := [[1, 0.0, 1], [1, 500.0, 2], [4, 0.0, 4], [4, 500.0, 7], [4, 2000.0, 14], [1, 400.0, 2], [3, -50.0, 3]]
	for c in cases:
		eq(s.enemies.hp_at(c[0], c[1]), c[2], "base %d at %.0f m" % [c[0], c[1]])
	s.distance = 500.0
	s.enemies.resume_spawning(500.0)
	var spawned := [0]
	s.enemies._spawn_wave(500.0, func(_k, _f): spawned[0] += 1)
	for e in s.enemies.pool:
		if e.active:
			eq(e.hp, s.enemies.hp_at(int(e.row["hp"]), 500.0), "spawned %s uses the ramp" % e.type_id)
			eq(e.max_hp, e.hp, "hp bar full at spawn")
	ok(spawned[0] > 0, "a wave spawned")


func _near(actual: float, expected: float, tolerance: float, note := "") -> void:
	ok(absf(actual - expected) <= tolerance, "%s: expected %s +- %s, got %s" % [note, expected, tolerance, actual])


## 16 Oct: Corne quit an 18 km run "because it might go on forever". The replay held dps/hp at ~10 from 0.5 to 17 km.
## Past escalation_start hp compounds per WHOLE 100 m; the edges are where an off-by-one would hide.
func test_enemy_hp_compounds_past_escalation_start_and_only_there() -> void:
	var s := _quiet()
	var g: float = s.rules.t("enemy_hp_growth_per_100m")
	ok(g > 1.0, "growth must be above 1 or it does nothing")
	for d in [-50.0, 0.0, 999.0, 1000.0, 1099.9]:
		eq(s.enemies.growth(d), 1.0, "%.1f m: no growth before the first whole 100 m past the start" % d)
	eq(s.enemies.growth(1100.0), g, "1,100 m: one step")
	eq(s.enemies.growth(1250.0), g * g, "1,250 m: two whole steps, the half step does not count")
	var prev := 0.0
	for i in 3000:  # every 10 m out to 30 km: never shrinks
		var gr: float = s.enemies.growth(i * 10.0)
		ok(gr >= prev, "growth fell at %d m" % (i * 10))
		prev = gr
	_near(s.enemies.growth(17000.0), pow(g, 160), 1e-6 * pow(g, 160), "17 km = 160 steps (exact maths, same as pow)")
	var linear := _quiet({"enemy_hp_growth_per_100m": 1.0})
	ok(s.enemies.hp_at(1, 17000.0) >= 8 * linear.enemies.hp_at(1, 17000.0), "17 km: at least 8x the old straight line, got %d vs %d"
		% [s.enemies.hp_at(1, 17000.0), linear.enemies.hp_at(1, 17000.0)])
	var late := _quiet({"escalation_start": 5000.0})
	eq(late.enemies.growth(4900.0), 1.0, "growth follows escalation_start, not a hard-coded 1,000 m")
	eq(late.enemies.growth(5100.0), g)


func test_boss_hp_takes_the_growth_where_it_starts() -> void:
	var s := _quiet()
	s.distance = 6000.0
	s._start_boss()
	var flat := int((s.rules.t("boss_base_hp") + s.rules.t("boss_hp_per_wave")) * float(s.boss.row["hp_mult"]))
	ok(s.boss.max_hp > flat, "a boss at 6 km is tougher than the same boss at 0 m")
	eq(s.boss.max_hp, int(flat * s.enemies.growth(6000.0)), "x growth(6 km)")
	var early := _quiet()
	early._start_boss()
	eq(early.boss.max_hp, flat, "a boss before escalation_start is unscaled")


## Touches did 1 and bomber blasts 2 at every distance, so 61 banked armour meant 61 free touches.
func test_enemy_hits_grow_every_few_tiers() -> void:
	var s := _quiet()
	var every := int(s.rules.t("enemy_damage_every_tiers"))
	var edge: float = s.rules.t("escalation_start") + s.rules.t("escalation_every") * (every - 1)  # first metre of tier `every`
	eq(s.enemies.tier(edge - 0.1), every - 1)
	eq(s.enemies.tier(edge), every)
	eq(s.enemies.hit_damage(1, 0.0), 1)
	eq(s.enemies.hit_damage(1, edge - 0.1), 1, "one tier short: still 1")
	eq(s.enemies.hit_damage(1, edge), 2, "tier %d: +1" % every)
	eq(s.enemies.hit_damage(2, edge), 3, "a bomber blast gets the same +1")
	for case in [[edge - 50.0, 1], [edge + 50.0, 2]]:
		var t := _quiet()
		t.distance = case[0]
		_place(t, "basic", t.player.x, t.player.z + 1.4)
		var hurt := _of(_run(t, 1), K.PLAYER_HURT)
		eq(hurt.size(), 1, "the touch landed at %.0f m" % case[0])
		if hurt.size() == 1:
			eq(hurt[0]["amount"], case[1], "a real touch at %.0f m" % case[0])
	var b := _quiet({"flanker_lock_distance": 1000.0})
	b.distance = edge + 50.0
	_place(b, "bomber", 0.0, b.player.z + 15.0)
	var blast := _of(_run(b, 120), K.PLAYER_HURT)
	ok(blast.size() > 0 and blast[0]["amount"] == int(b.rules.t("bomber_blast_damage")) + 1, "a real bomber past the edge: %s" % [blast])


## The 18 km run banked 61 armour (14 pickups, Plating which stacks to 99, two Bulwarks).
func test_armour_never_goes_above_the_cap_by_any_route() -> void:
	var s := _quiet()
	var cap := int(s.rules.t("armor_max"))
	s.player.add_armor(cap + 40)
	eq(s.player.armor, cap, "one huge pickup")
	s.player.add_armor(-1000)
	eq(s.player.armor, 0, "never below zero")
	var plating: Dictionary = {}
	var bulwark: Dictionary = {}
	for row in s.rules.perks:
		if row["id"] == "plating":
			plating = row
		if row["id"] == "bulwark":
			bulwark = row
	for i in 99:
		s.player.apply_perk(plating)
	eq(s.player.armor, cap, "99 Plating stacks")
	s.player.armor = cap - 1
	s.player.apply_perk(bulwark)
	eq(s.player.armor, cap, "Bulwark at cap - 1 tops up to the cap, not past it")
	var p := _quiet()
	var u = p.upgrades.pool[0]
	u.kind = "armor"
	for i in 30:
		p._apply_reward(u)  # the real pickup path
	eq(p.player.armor, cap, "30 armour pickups stop at the cap")
	p.player.armor = cap
	var r := p.player.take_damage(3)
	eq(r["absorbed"], 3, "capped armour still absorbs")


func test_dps_counts_every_gun_and_lasting_perk_but_not_timed_buffs() -> void:
	var s := _quiet()
	s.player.set_weapon("pistol")
	var w: Dictionary = s.rules.weapons["pistol"]
	var one := float(w["damage"]) * float(w["bullet_count"]) * float(w["fire_rate"])
	_near(s.player.dps(), one, 1e-6, "one level-1 pistol, no perks")
	s.player.add_gun("pistol")
	_near(s.player.dps(), one * s.player.level_mult(2), 1e-6, "levelled to 2")
	s.player.add_gun("smg")
	ok(s.player.dps() > one * s.player.level_mult(2), "a second gun adds")
	var before := s.player.dps()
	s.player.frenzy_timer = 5.0
	s.player.speed_timer = 5.0
	_near(s.player.dps(), before, 1e-6, "frenzy and speed are timed: not counted")
	s.player.mods["crit_chance"] = 0.5
	_near(s.player.dps(), before * 1.5, 1e-6, "crit doubles: 50% crit = x1.5")


func test_band_boundaries() -> void:
	var s := _quiet()
	var cases := {0.0: "early", 149.9: "early", 150.0: "mid", 399.99: "mid", 400.0: "late", 800.0: "endgame", 5000.0: "endgame"}
	for d in cases:
		eq(s.enemies._band_for(d)["id"], cases[d], "distance %s" % d)


func test_wave_size_grows_with_distance() -> void:
	# Escalation (16 Oct): +1 per tier past 1,000 m, capped; walls off here (they are their own test).
	var cases := {0.0: 1, 299.0: 1, 300.0: 2, 600.0: 3, 999.0: 3, 1000.0: 4, 1800.0: 5, 10000.0: 7}
	for d in cases:
		var s := _quiet({"formation_chance": 0.0, "formation_chance_per_tier": 0.0})
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
		s.enemies._spawn_wave(999.0, func(_k, _f): pass)  # tier 0: waves of 3
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
	var pool_size := s.enemies.pool.size()
	eq(pool_size, int(s.rules.t("enemy_pool")), "pool sized from tuning")
	for i in pool_size:
		_place(s, "basic", 0.0, 100.0)
	var spawned := [0]
	s.enemies._spawn_wave(1000.0, func(_k, _f): spawned[0] += 1)
	eq(spawned[0], 0)
	eq(s.enemies.exhausted_count, 1)
	eq(s.enemies.active_count(), pool_size)
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
	var s := _quiet({"upgrade_spawn_per_second": 0.48, "upgrade_pool": 400, "upgrade_pair_chance": 0, "drop_min_gap": 0})
	var spawned := _of(_run(s, 36000), K.UPGRADE_SPAWNED).size()
	ok(spawned >= 230 and spawned <= 346, "10 sim-minutes: %d spawns, expect 288 +- 58" % spawned)
	# All pairs: the same drop rate (one reward per drop), so exactly twice the pickups on the road.
	var p := _quiet({"upgrade_spawn_per_second": 0.48, "upgrade_pool": 400, "upgrade_pair_chance": 1, "drop_min_gap": 0})
	var halves := _of(_run(p, 36000), K.UPGRADE_SPAWNED)
	ok(halves.size() >= 460 and halves.size() <= 692, "10 sim-minutes of pairs: %d halves, expect 576 +- 116" % halves.size())
	eq(halves.size() % 2, 0, "pickups only ever come in twos")

	var b := _quiet({"upgrade_spawn_per_second": 0.48, "boss.steer": 0.0})
	b._start_boss()
	b.boss.hp = 1000000
	b.boss.max_hp = 1000000
	b.player.x = 7.0
	eq(_of(_run(b, 3600), K.UPGRADE_SPAWNED).size(), 0, "no upgrades during a boss")


func test_grenade_explodes_at_the_end_of_its_range() -> void:
	var s := _quiet()
	var range_z: float = s.rules.weapons["grenade"]["max_range"]
	# An enemy 2 units beyond where the grenade's range ends, inside the 4.0 blast, never touched directly.
	var target = _place(s, "basic", 2.0, range_z + 0.5)
	s.enemies.pool[0].slow_mult = 0.0
	_shoot(s, "grenade", 0.0, 0.0)
	var ev: Array[Dictionary] = []
	for i in 80:
		target.z = range_z + 0.5  # hold it still so only the blast can reach it
		target.prev_z = target.z
		s.step({})
		ev.append_array(s.events)
	var blasts := _of(ev, K.EXPLOSION)
	eq(blasts.size(), 1, "one explosion")
	if blasts.size() == 1:
		eq(blasts[0]["impact"], false, "detonated at range, not on impact")
	var killed := _of(ev, K.ENEMY_KILLED)
	eq(killed.size(), 1, "the blast killed the enemy it never touched")
	if killed.size() == 1:
		eq(killed[0]["source"], "splash")


func test_non_explosive_bullets_just_stop_at_range() -> void:
	var s := _quiet()
	_shoot(s, "pistol", 0.0, 0.0)
	eq(_of(_run(s, 120), K.EXPLOSION).size(), 0)


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


# ---------- hit reach ----------

## 15 Oct PC runs: "zombie at x=0.6, you at x=2.7 -> hit". With real models that is a visible 2 m gap.
func test_enemy_passing_beside_you_misses_and_one_brushing_you_hits() -> void:
	for case in [[1.8, 0], [1.2, 1]]:
		var s := _quiet()
		s.player.x = 0.0
		var e = _place(s, "basic", case[0], s.player.z + 6.0)
		e.slow_mult = 1.0
		var ev := _run(s, 120)
		eq(_of(ev, K.PLAYER_HURT).size(), case[1], "basic enemy passing %.1f m to the side" % case[0])


# ---------- gun loadout (plan 2026-10-16-gun-loadout) ----------

func _ids(s: Sim) -> Array:
	return s.player.guns.map(func(g): return "%s:%d" % [g.id, g.level])


func test_a_gun_you_hold_levels_up_and_never_takes_another_slot() -> void:
	var s := _quiet()
	var cap := int(s.rules.t("gun_max_level"))
	eq(_ids(s), ["pistol:1"], "start")
	var actions: Array = []
	for i in cap + 2:
		actions.append(s.player.add_gun("pistol")["action"])
	eq(_ids(s), ["pistol:%d" % cap], "one slot, capped at %d" % cap)
	eq(actions.count("levelled"), cap - 1)
	eq(actions.count("maxed"), 3)


## 16 Oct: "accidentally pick up another weapon after you've had the minigun". With every slot full, a new gun
## replaces the weakest - for every order the guns can arrive in, the levelled minigun survives.
func test_a_new_gun_never_replaces_a_stronger_one_in_any_order() -> void:
	var guns := ["smg", "laser", "flamethrower"]
	var orders := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	for order in orders:
		var s := _quiet()
		s.player.add_gun("minigun")
		s.player.add_gun("minigun")
		s.player.add_gun("minigun")  # lv 3
		for i in order:
			var r: Dictionary = s.player.add_gun(guns[i])
			ok(r["replaced"] != "minigun", "order %s: %s replaced the minigun" % [order, guns[i]])
		ok(_ids(s).has("minigun:3"), "order %s: minigun kept %s" % [order, _ids(s)])
		ok(not _ids(s).has("pistol:1"), "order %s: the pistol went first %s" % [order, _ids(s)])
		eq(s.player.guns.size(), int(s.rules.t("gun_slots")), "order %s: slots full, never more" % [order])


func test_replacing_takes_the_weakest_by_power_not_by_slot() -> void:
	var s := _quiet()
	s.player.set_weapon("railgun")
	s.player.add_gun("smg")
	s.player.add_gun("pistol")
	var weakest := 0
	for i in s.player.guns.size():
		if s.player.gun_power(s.player.guns[i]) < s.player.gun_power(s.player.guns[weakest]):
			weakest = i
	var expect: String = s.player.guns[weakest].id
	var r: Dictionary = s.player.add_gun("rocket")
	eq(r["replaced"], expect, "weakest by power")
	eq(r["action"], "replaced")


func test_every_gun_fires_at_its_own_rate_from_its_own_muzzle() -> void:
	var s := _quiet()
	s.player.fire_timer = 0.0
	s.player.add_gun("minigun")
	s.player.add_gun("rocket")
	var shots := {}
	var muzzles := {}
	var seconds := 10
	for i in 60 * seconds:
		s.step({})
		for e in s.events:
			if e["kind"] == K.FIRED:
				shots[e["weapon"]] = shots.get(e["weapon"], 0) + 1
				muzzles[e["weapon"]] = e["x"] - s.player.x
	for id in ["pistol", "minigun", "rocket"]:
		var rate: float = s.rules.weapons[id]["fire_rate"]
		var steps := ceili(60.0 / rate - 1e-9)  # the timer fires on whole steps (weapons.tsv)
		var want := 60.0 * seconds / steps
		ok(absf(shots.get(id, 0) - want) <= 2.0, "%s fired %d times in %d s, want ~%.0f" % [id, shots.get(id, 0), seconds, want])
	eq(muzzles.size(), 3)
	var xs: Array = muzzles.values()
	xs.sort()
	ok(xs[1] - xs[0] > 0.5 and xs[2] - xs[1] > 0.5, "three muzzles apart: %s" % [xs])


func test_gun_level_five_adds_four_level_bonuses() -> void:
	var s := _quiet()
	s.player.set_weapon("railgun")
	var base := s.player.shot_damage()
	for i in 4:
		s.player.add_gun("railgun")
	eq(s.player.guns[0].level, 5)
	eq(s.player.shot_damage(), int(floor(base * (1.0 + 4.0 * s.rules.t("gun_level_damage")) + 1e-9)), "lv 5 = 1 + 4 x gun_level_damage")


func test_gun_pickup_in_play_says_what_changed_and_the_hash_sees_levels() -> void:
	var s := _quiet()
	var before := s.state_hash()
	s.player.add_gun("pistol")
	ok(s.state_hash() != before, "a gun level is game state")
	var s2 := _quiet()
	var u = s2.upgrades._inactive()
	s2.upgrades._place(u, s2.upgrades._reward_row("smg"), s2.player.x, 0.0, s2.player.z, s2._emit)
	u.thawed = true
	var ev := _run(s2, 2)
	var changed := _of(ev, K.GUN_CHANGED)
	eq(changed.size(), 1, "one GUN_CHANGED")
	if changed.size() == 1:
		eq([changed[0]["action"], changed[0]["gun"], changed[0]["level"]], ["added", "smg", 1])
		ok(changed[0].has("x") and changed[0].has("z"), "juice can place its text")
	eq(_ids(s2), ["pistol:1", "smg:1"])


# ---------- lightning (Corne, 16 Oct: 100% -> 60% -> 20%, levels add arcs) ----------

## A column of tough enemies 4 m apart, one lightning bolt of `damage` with `arcs` arcs into the first.
## Returns [serials in column order, hit amounts by serial, chain hits by serial].
func _bolt_column(count: int, damage: int, arcs: int, gap := 4.0) -> Array:
	var s := _quiet()
	var serials: Array = []
	for i in count:
		var e = _place(s, "armored", 0.0, 20.0 + gap * i)
		e.hp = 100000
		serials.append(e.serial)
	var b = _shoot(s, "lightning", 0.0, 0.0, damage)
	b.chain_arcs = arcs
	var hits := {}
	var chains := {}
	for ev in _run(s, 60):
		if ev["kind"] == K.ENEMY_HIT:
			hits[ev["serial"]] = hits.get(ev["serial"], 0) + ev["amount"]
			if ev["source"] == "chain":
				chains[ev["serial"]] = chains.get(ev["serial"], 0) + 1
	return [serials, hits, chains]


func test_lightning_arcs_100_60_20_and_no_further_at_level_1() -> void:
	var r := _bolt_column(5, 10, 2)
	var amounts: Array = r[0].map(func(serial): return r[1].get(serial, 0))
	eq(amounts, [10, 6, 2, 0, 0], "direct hit, then 60%, then 20%, then nothing")


func test_each_lightning_level_adds_an_arc_at_the_floor() -> void:
	var r := _bolt_column(6, 10, 4)
	var amounts: Array = r[0].map(func(serial): return r[1].get(serial, 0))
	eq(amounts, [10, 6, 2, 2, 2, 0], "arcs 3 and 4 stay at chain_min (20%)")
	var s := _quiet()
	s.player.set_weapon("lightning")
	s.player.add_gun("lightning")
	s.player.add_gun("lightning")  # lv 3
	s.player.fire_timer = 1000.0
	s.step({})
	var arcs := []
	for b in s.bullets.pool:
		if b.active:
			arcs.append(b.chain_arcs)
	eq(arcs, [2 + 2 * int(s.rules.t("chain_arcs_per_level"))], "a lv 3 gun fires bolts with more arcs")


func test_lightning_never_strikes_one_enemy_twice() -> void:
	var r := _bolt_column(2, 10, 6)
	eq(r[2].values(), [1], "two enemies, six arcs: one chain hit only")
	eq(r[1][r[0][0]], 10, "the first one only took its direct hit")


func test_lightning_reach_ends_at_chain_range() -> void:
	var reach: float = _quiet().rules.t("chain_range")
	var inside := _bolt_column(2, 10, 2, reach - 0.5)
	eq(inside[2].size(), 1, "arcs %.1f m" % (reach - 0.5))
	var outside := _bolt_column(2, 10, 2, reach + 0.5)
	eq(outside[2].size(), 0, "not %.1f m" % (reach + 0.5))


func test_lightning_alone_on_the_road_and_ties_go_to_the_lower_serial() -> void:
	var lone := _bolt_column(1, 10, 3)
	eq(lone[2].size(), 0, "no one to arc to, no crash")
	var s := _quiet()
	var first = _place(s, "armored", 0.0, 20.0)
	first.hp = 100000
	var left = _place(s, "armored", -3.0, 20.0)
	left.hp = 100000
	var right = _place(s, "armored", 3.0, 20.0)
	right.hp = 100000
	var b = _shoot(s, "lightning", 0.0, 0.0, 10)
	b.chain_arcs = 1
	var chained := []
	for ev in _run(s, 60):
		if ev["kind"] == K.ENEMY_HIT and ev["source"] == "chain":
			chained.append(ev["serial"])
	eq(chained, [mini(left.serial, right.serial)], "equal distance: lower serial, so replays match")


# ---------- evolutions + boss loot (depth plan items 3 and 5) ----------

func _perk(s: Sim, id: String) -> Dictionary:
	for row in s.rules.perks:
		if row["id"] == id:
			return row
	return {}


## Lightning at max level plus a Magnet stack, boss beaten: evolve is offered, taking it gives Tempest.
func _ready_to_evolve(seed_value := 1) -> Sim:
	var s := _quiet({}, seed_value)
	s.player.set_weapon("lightning")
	for i in int(s.rules.t("gun_max_level")) - 1:
		s.player.add_gun("lightning")
	s.player.apply_perk(_perk(s, "magnet"))
	return s


func test_a_maxed_gun_with_its_perk_is_always_offered_its_evolution() -> void:
	for seed_value in 20:
		var s := _ready_to_evolve(seed_value)
		s._start_boss()
		s._boss_defeated()
		eq(s.choice_kind, "loot", "seed %d" % seed_value)
		ok(Array(s.choices).has("evolve:lightning"), "seed %d: %s" % [seed_value, s.choices])
		eq(s.choices.size(), 3, "seed %d: three cards %s" % [seed_value, s.choices])
		var tick := s.tick
		_run(s, 30)
		eq(s.tick, tick, "the game waits for the pick")
		s.step({"pick": Array(s.choices).find("evolve:lightning")})
		eq(_ids(s), ["tempest:5"], "seed %d: evolved, level kept" % seed_value)
		ok(s.choices.is_empty(), "closed")


func test_no_evolve_card_without_the_perk_or_below_max_level() -> void:
	for case in [["no perk", false, 0], ["lv 4", true, 1]]:
		for seed_value in 10:
			var s := _quiet({}, seed_value)
			s.player.set_weapon("lightning")
			for i in int(s.rules.t("gun_max_level")) - 1 - case[2]:
				s.player.add_gun("lightning")
			if case[1]:
				s.player.apply_perk(_perk(s, "magnet"))
			s._start_boss()
			s._boss_defeated()
			for c in s.choices:
				ok(not c.begins_with("evolve:"), "%s seed %d: %s" % [case[0], seed_value, s.choices])


func test_evolved_gun_counts_as_its_base_for_pickups_and_loot() -> void:
	var s := _ready_to_evolve()
	s.player.evolve(0)
	var r := s.player.add_gun("lightning")
	eq(r["action"], "maxed", "the base gun is already held, as Tempest")
	eq(_ids(s), ["tempest:5"], "no second slot for it")
	for seed_value in 30:
		var t := _ready_to_evolve(seed_value)
		t.player.evolve(0)
		t.player.add_gun("smg")
		t._start_boss()
		t._boss_defeated()
		for c in t.choices:
			ok(c != "gun:lightning" and c != "gun:smg", "seed %d offers a gun already held: %s" % [seed_value, t.choices])


func test_boss_loot_waits_for_an_open_level_up_then_follows() -> void:
	var s := _quiet()
	s.xp = s.xp_needed(s.level)
	s._check_level_up()
	eq(s.choice_kind, "level")
	var perks := s.choices.duplicate()
	s._start_boss()
	s._boss_defeated()
	eq(s.choices, perks, "level-up still showing")
	eq(s.pending_loot, 1)
	s.step({"pick": 0})
	eq(s.choice_kind, "loot", "loot follows the level-up")
	eq(s.pending_loot, 0)


func test_every_loot_card_does_what_it_says() -> void:
	var s := _quiet()
	s.player.hp = 3
	s.player.max_hp = 8
	s._take_loot("heal")
	eq(s.player.hp, 8, "full heal")
	s._take_loot("gun:rocket")
	eq(_ids(s), ["pistol:1", "rocket:1"], "new gun")
	s._take_loot("level:rocket")
	eq(_ids(s), ["pistol:1", "rocket:2"], "+1 level")
	s._take_loot("perk:damage")
	eq(s.player.perk_stacks["damage"], 2, "double perk")
	s._take_loot("perk:multishot")  # max 1 stack: never past the cap
	eq(s.player.perk_stacks["multishot"], 1, "capped at max_stacks")
	var before := s.state_hash()
	s.choice_kind = "loot"
	ok(s.state_hash() != before, "an open loot choice is game state")


func test_evolved_guns_keep_their_base_strengths_and_every_one_is_reachable() -> void:
	var rules := _quiet().rules
	eq(rules.multiplier("scattergun", "basic"), rules.multiplier("shotgun", "basic"), "inherits shotgun vs runner")
	var bases := {}
	for row in rules.rewards:
		if row["kind"] == "weapon":
			bases[row["id"]] = true
	bases["pistol"] = true
	for base in bases:
		ok(rules.evolution_of.has(base), "%s has no evolution" % base)


func test_perk_card_says_which_held_gun_it_evolves() -> void:
	var s := _quiet()
	s.player.add_gun("lightning")
	ok(String(s.choice_card("magnet")["footer"]).contains("EVOLVES LIGHTNING"), s.choice_card("magnet")["footer"])
	ok(not String(s.choice_card("damage")["footer"]).contains("EVOLVES"), "damage evolves nothing held")
	ok(String(s.choice_card("evolve:lightning")["name"]).to_upper().contains("TEMPEST"), s.choice_card("evolve:lightning")["name"])


# ---------- enemy behaviours (depth plan item 4) ----------

func _bomber_run(side: float) -> Array:
	var s := _quiet({"flanker_lock_distance": 1000.0})  # it runs straight at the spot it was placed
	var b = _place(s, "bomber", side, s.player.z + 15.0)
	var ev := _run(s, 120)
	return [s, ev, b]


func test_bomber_blast_is_wider_than_a_touch() -> void:
	var fuse: float = _quiet().rules.t("bomber_fuse")
	for case in [[0.0, true], [2.0, true], [fuse + 1.0, false]]:
		var r := _bomber_run(case[0])
		var hurt := _of(r[1], K.PLAYER_HURT)
		eq(hurt.size() > 0, case[1], "bomber passing %.1f m to the side" % case[0])
		if case[1] and hurt.size() > 0:
			eq(hurt[0]["amount"], int(r[0].rules.t("bomber_blast_damage")))
		eq(_of(r[1], K.EXPLOSION).size(), 1 if case[0] < fuse else 0, "%.1f m: it blows up only inside the fuse" % case[0])


func test_shooting_a_bomber_in_a_crowd_blasts_the_crowd_and_sets_off_bombers() -> void:
	var s := _quiet()
	var bomb = _place(s, "bomber", 0.0, 30.0)
	var other_bomb = _place(s, "bomber", 2.5, 30.0)
	var tank = _place(s, "armored", -0.5, 30.0)  # inside both blasts
	tank.hp = 100
	var far = _place(s, "armored", 0.0, 40.0)
	far.hp = 100
	ok(s.damage_enemy(bomb, 5, "bullet", "pistol"), "killed")
	ok(not other_bomb.active, "the bomber beside it went off too")
	eq(tank.hp, 100 - 2 * int(s.rules.t("bomber_enemy_damage")), "the tank took both blasts")
	eq(far.hp, 100, "10 m away: untouched")
	eq(s.player.hp, s.player.max_hp, "you were 38 m away")


func test_healer_heals_inside_its_radius_only_and_never_above_max() -> void:
	var s := _quiet({"enemy_speed": 0.0})  # held still: speeds differ, so they would drift into reach
	var healer = _place(s, "healer", 0.0, 60.0)
	var near = _place(s, "armored", 3.0, 60.0)
	var far = _place(s, "armored", 0.0, 60.0 + s.rules.t("healer_radius") + 1.0)
	var full = _place(s, "armored", -2.0, 60.0)
	near.hp = 1
	far.hp = 1
	var ev := _run(s, int(60 * (s.rules.t("healer_every") * 3 + 0.1)))
	eq(near.hp, mini(near.max_hp, 1 + 3 * int(s.rules.t("healer_amount"))), "three heals")
	eq(far.hp, 1, "out of reach")
	eq(full.hp, full.max_hp, "a full enemy stays full")
	ok(_of(ev, K.ENEMY_HEALED).size() >= 1, "you can see it heal")
	ok(healer.active, "healer alive")


func test_splitter_becomes_runners_that_do_not_split_again() -> void:
	var s := _quiet()
	var sp = _place(s, "splitter", 1.0, 40.0)
	s.damage_enemy(sp, 100, "bullet", "pistol")
	var runners := []
	for e in s.enemies.pool:
		if e.active:
			runners.append(e)
	eq(runners.size(), int(s.rules.t("split_count")))
	for r in runners:
		eq(r.type_id, "basic")
		ok(absf(r.z - 40.0) < 0.01, "they appear where it died")
	s.damage_enemy(runners[0], 100, "bullet", "pistol")
	var left := 0
	for e in s.enemies.pool:
		left += 1 if e.active else 0
	eq(left, int(s.rules.t("split_count")) - 1, "a runner just dies")


func test_shield_soaks_bullets_but_not_splash_chain_or_burn() -> void:
	for source in ["bullet", "splash", "chain", "burn"]:
		var s := _quiet()
		var e = _place(s, "shielded", 0.0, 40.0)
		e.hp = 50
		e.max_hp = 50
		var shield: int = e.shield_hp
		ok(shield >= int(s.rules.t("shield_hp")), "it has a shield (%d)" % shield)
		s.damage_enemy(e, 3, source, "pistol")
		if source == "bullet":
			eq([e.hp, e.shield_hp], [50 - maxi(0, 3 - shield), maxi(0, shield - 3)], "bullet: shield first")
		else:
			eq([e.hp, e.shield_hp], [47, shield], "%s goes round the shield" % source)


func test_every_enemy_behaviour_is_known() -> void:
	var rules := _quiet().rules
	var seen := {}
	for id in rules.enemies:
		seen[rules.enemies[id]["behaviour"]] = true
	for b in ["bomber", "healer", "splitter", "shield"]:
		ok(seen.has(b), "some enemy is a %s" % b)


# ---------- escalation (depth plan item 6) ----------

func _wave_at(s: Sim, d: float) -> Array:
	for e in s.enemies.pool:
		e.active = false
	s.enemies._spawn_wave(d, func(_k, _f): pass)
	return s.enemies.pool.filter(func(e): return e.active)


func test_no_elites_or_walls_before_escalation() -> void:
	var s := _quiet()
	for w in 300:
		var wave := _wave_at(s, s.rules.t("escalation_start") - 1.0)
		ok(wave.size() <= int(s.rules.t("wave_size_max")), "wave %d: %d enemies" % [w, wave.size()])
		for e in wave:
			ok(not e.elite, "elite before %d m" % s.rules.t("escalation_start"))


func test_elites_come_at_the_tuned_rate_and_are_what_they_say() -> void:
	var s := _quiet({"formation_chance": 0.0, "formation_chance_per_tier": 0.0})
	var d := 3000.0
	var want: float = s.enemies.elite_chance(d)
	ok(want > 0.0, "elites by %d m" % d)
	var n := 0
	var elites := 0
	for w in 600:
		for e in _wave_at(s, d):
			n += 1
			if e.elite:
				elites += 1
				var normal_hp: int = s.enemies.hp_at(int(e.row["hp"]), d)
				eq(e.hp, int(ceil(normal_hp * s.rules.t("elite_hp_mult"))), "elite hp")
				ok(absf(e.radius - float(e.row["size"]) * s.rules.t("enemy_radius_per_size") * s.rules.t("elite_size_mult")) < 1e-6, "elite hit radius grows with it")
	var rate := float(elites) / n
	ok(absf(rate - want) < 0.03, "elite rate %.3f over %d enemies, tuned %.3f" % [rate, n, want])
	var t := _quiet()
	var e = _place(t, "basic", 0.0, 30.0)
	e.elite = true
	var before := t.score
	t.damage_enemy(e, 100, "bullet", "pistol")
	eq(t.score - before, int(e.row["score"]) * int(t.rules.t("elite_score_mult")), "elite worth double")


## Every wall leaves exactly one gap at least formation_gap wide, wide enough to stand in without a touch.
func test_every_wall_has_one_gap_you_fit_through() -> void:
	var s := _quiet({"formation_chance": 1.0, "formation_chance_max": 1.0})
	var reach: float = s.rules.t("enemy_hit_player_radius") + s.rules.t("enemy_radius_per_size") * 1.4  # biggest enemy
	var half: float = s.rules.t("road_width") / 2.0 - s.rules.t("player_road_margin")
	for w in 200:
		var wall := _wave_at(s, 2000.0)
		ok(wall.size() >= 4, "wall %d: %d enemies" % [w, wall.size()])
		var xs: Array = wall.map(func(e): return e.x)
		xs.sort()
		var safe := 0  # player positions (every 0.1 m) no enemy in the wall can touch
		var x := -half
		while x <= half:
			var clear := true
			for ex in xs:
				clear = clear and absf(ex - x) >= reach
			safe += 1 if clear else 0
			x += 0.1
		ok(safe >= 5, "wall %d: somewhere to stand (%d spots) %s" % [w, safe, xs])
		var gaps := 0
		for i in range(1, xs.size()):
			if xs[i] - xs[i - 1] > s.rules.t("formation_spacing") + 0.01:
				gaps += 1
		ok(gaps <= 1, "wall %d: one gap, not %d" % [w, gaps])


## 16 Oct critique: shotgun (24 m) and flamer (16 m) could never reach a Summoner or Gunner holding at 30-32 m, so
## with those guns a boss was a 20 s wait. Every gun, evolved ones too, must reach every holding boss unaided.
func test_every_gun_reaches_every_holding_boss() -> void:
	var rules := _quiet().rules
	for b in rules.bosses:
		if float(b["hold_z"]) <= 0.0:
			continue
		var need: float = float(b["hold_z"]) - rules.t("boss_radius") - rules.t("bullet_hit_radius")
		for id in rules.weapons:
			ok(float(rules.weapons[id]["max_range"]) >= need, "%s (range %s) cannot reach %s holding at %s m (needs %.1f)" % [id, rules.weapons[id]["max_range"], b["id"], b["hold_z"], need])


# ---------- risk choices (depth plan item 7) ----------

func test_glass_cannon_trades_max_hp_and_never_takes_the_last_point() -> void:
	var s := _quiet()
	s.player.max_hp = 5
	s.player.hp = 5
	var gc := _perk(s, "glass_cannon")
	s.player.apply_perk(gc)
	eq([s.player.max_hp, s.player.hp], [3, 3], "-2 max HP")
	ok(absf(s.player.mods["damage_mult"] - 0.3) < 1e-9, "+30% damage")
	s.player.max_hp = 2
	s.player.hp = 1
	s.player.apply_perk(gc)
	eq([s.player.max_hp, s.player.hp], [1, 1], "never below 1, never kills you")


func test_overclock_really_slows_you() -> void:
	var a := _quiet()
	var b := _quiet()
	b.player.apply_perk(_perk(b, "overclock"))
	_run(a, 30, {"move": 1.0})
	_run(b, 30, {"move": 1.0})
	ok(b.player.x < a.player.x - 0.3, "overclocked %.2f m vs %.2f m in half a second" % [b.player.x, a.player.x])


func test_cursed_loot_levels_every_gun_for_max_hp_and_only_when_affordable() -> void:
	var s := _quiet()
	s.player.add_gun("smg")
	s.player.add_gun("rocket")
	for i in 4:
		s.player.add_gun("rocket")  # rocket at max
	s.player.max_hp = 6
	s.player.hp = 6
	s._take_loot("curse")
	eq(_ids(s), ["pistol:2", "smg:2", "rocket:5"], "every gun not at max +1")
	eq([s.player.max_hp, s.player.hp], [4, 4], "-2 max HP")
	for seed_value in 30:
		var t := _quiet({}, seed_value)
		t.player.max_hp = int(t.rules.t("curse_max_hp"))
		t.player.hp = t.player.max_hp
		t._start_boss()
		t._boss_defeated()
		ok(not Array(t.choices).has("curse"), "seed %d: curse offered at %d max HP" % [seed_value, t.player.max_hp])


# ---------- lane switchers ----------

## 16 Oct: a lane switcher "quickly steps into my lane, I don't even have a chance to shoot it". Inside
## flanker_lock_distance it runs straight - even one caught mid-slide - and further out it still switches.
func test_lane_switchers_run_straight_once_close() -> void:
	for type_id in ["fast", "bomber"]:
		var s := _quiet()
		var lock: float = s.rules.t("flanker_lock_distance")
		var near = _place(s, type_id, -5.0, s.player.z + lock + 1.0)
		near.target_x = 5.0      # mid-slide to the far side as it crosses the line
		near.lane_timer = 1e9
		var far = _place(s, type_id, -5.0, s.player.z + 70.0)
		far.target_x = 5.0
		far.lane_timer = 1e9
		var near_x: Array[float] = []
		var moved_far := false
		for i in 60 * 3:
			s.step({})
			if near.active and near.z - s.player.z < lock:
				near_x.append(near.x)
			moved_far = moved_far or far.x > -4.0
		ok(near_x.size() > 30, "%s: watched it inside the lock (%d steps)" % [type_id, near_x.size()])
		if near_x.size() > 0:
			ok(near_x.max() - near_x.min() < 0.2, "%s: no sideways move inside %d m (%.2f..%.2f)" % [type_id, lock, near_x.min(), near_x.max()])
		ok(moved_far, "%s: still switches lanes further out" % type_id)


# ---------- first weapon ----------

## Three of five PC runs on 15 Oct died at 200-340 m without ever seeing a gun. Every seed must offer two
## different weapons early, even with random drops switched off.
func test_every_run_is_offered_two_different_weapons_early() -> void:
	for seed_value in 25:
		var s := _sim(seed_value, {"upgrade_spawn_per_second": 0, "trap_spawn_per_second": 0})
		var offered := []
		for i in int(60 * (s.rules.t("first_weapon_seconds") + 1.0)):
			s.step({})
			for e in s.events:
				if e["kind"] == K.UPGRADE_SPAWNED:
					offered.append(e["reward"])
		eq(offered.size(), 2, "seed %d: one pair" % seed_value)
		if offered.size() == 2:
			ok(offered[0] != offered[1], "seed %d: two different guns %s" % [seed_value, offered])
			for id in offered:
				ok(s.rules.weapons.has(id), "seed %d: %s is a weapon" % [seed_value, id])
		ok(s.first_weapon_given, "given once")
		var more := 0
		for i in 600:
			s.step({})
			for e in s.events:
				if e["kind"] == K.UPGRADE_SPAWNED:
					more += 1
		eq(more, 0, "seed %d: only once per run" % seed_value)


## 16 Oct run 1: a speed/heal pair landed 2.3 s before the gun pair, in the same two lanes, and its ice ate every
## pistol shot until both guns had passed. At absurd drop rates nothing - pickup or trap - may beat the gun pair onto
## the road, the pair wears thin ice, and later drops wear the normal ice.
func test_gun_pair_is_the_first_drop_and_wears_thin_ice() -> void:
	for seed_value in 25:
		var s := _sim(seed_value, {"upgrade_spawn_per_second": 10, "trap_spawn_per_second": 10, "upgrade_pool": 40, "trap_pool": 40})
		var first: Array = []
		var later_ice: Array = []
		for i in 60 * 40:  # drop spacing allows ~4 drops per 20 s; traps can take all four (seed 13)
			s.step({"pick": 0})  # a level-up would otherwise stop the clock
			for e in s.events:
				if e["kind"] == K.TRAP_SPAWNED and first.size() < 2:
					first.append("trap")
				elif e["kind"] == K.UPGRADE_SPAWNED:
					var u = s.upgrades.pool.filter(func(x): return x.active and x.serial == e["serial"])[0]
					if first.size() < 2:
						first.append(e["reward"])
						eq(u.ice_hp, int(s.rules.t("first_weapon_ice_hp")), "seed %d: gun pair ice" % seed_value)
					else:
						later_ice.append(u.ice_hp)
		eq(first.size(), 2, "seed %d: %s" % [seed_value, first])
		for id in first:
			ok(s.rules.weapons.has(id), "seed %d: first drops %s must both be guns" % [seed_value, first])
		ok(later_ice.size() > 0, "seed %d: drops resume after the pair" % seed_value)
		for hp in later_ice:
			eq(hp, int(s.rules.t("upgrade_ice_hp")), "seed %d: later drops wear normal ice" % seed_value)


## The pistol, standing in line with one half and nothing in the way, frees it while it is still well ahead.
func test_pistol_frees_the_gun_pair_before_it_arrives() -> void:
	for seed_value in 10:
		var s := _sim(seed_value, {"upgrade_spawn_per_second": 0, "trap_spawn_per_second": 0})
		s.enemies.pause_spawning()
		var thawed_at := -1.0
		for i in 60 * 30:
			var target = null
			for u in s.upgrades.pool:
				if u.active and not u.thawed:
					target = u
					break
			if target != null:
				s.player.x = clampf(target.x, -7.0, 7.0)
			s.step({})
			for e in s.events:
				if e["kind"] == K.ICE_SHATTERED and thawed_at < 0.0:
					thawed_at = e["z"] - s.player.z
			if thawed_at >= 0.0:
				break
		ok(thawed_at > 20.0, "seed %d: freed with %.1f m to spare (want > 20 m)" % [seed_value, thawed_at])


# ---------- drop spacing ----------

## At absurd drop rates every step wants a pickup and a trap. None may appear while an older one is still within
## drop_min_gap of the spawn line (15 Oct: they spawned "on top of each other").
func test_drops_never_stack_even_at_absurd_rates() -> void:
	var s := _quiet({"upgrade_spawn_per_second": 10, "trap_spawn_per_second": 10, "upgrade_pool": 40, "trap_pool": 40})
	var spawn_line: float = s.rules.t("enemy_spawn_distance") + s.rules.t("enemy_spawn_jitter")
	var gap: float = s.rules.t("drop_min_gap")
	var drops := 0
	for i in 60 * 60:
		var before := {}
		for u in s.upgrades.pool:
			if u.active:
				before[u.serial] = u
		var traps_before := {}
		for t in s.traps.pool:
			if t.active:
				traps_before[t.serial] = t
		s.step({})
		var spawned := false
		for e in s.events:
			if e["kind"] in [K.UPGRADE_SPAWNED, K.TRAP_SPAWNED]:
				spawned = true
		if not spawned:
			continue
		drops += 1
		for u in before.values():
			ok(not u.active or u.z <= spawn_line - gap + s.rules.t("upgrade_speed") / 60.0 + 1e-6,
				"step %d: drop spawned with upgrade %d still at z %.1f" % [s.tick, u.serial, u.z])
		for t in traps_before.values():
			ok(not t.active or t.z <= spawn_line - gap + 1.0, "step %d: drop spawned with trap still at z %.1f" % [s.tick, t.z])
	ok(drops > 20, "drops still come: %d in a minute" % drops)
	ok(drops < 300, "but spaced: %d in a minute at 10/s" % drops)


# ---------- pick-one pairs ----------

## Pairs with no weave and no drift: halves sit exactly where the test puts them.
func _pair(left := "rocket", right := "heal") -> Array:
	var s := _quiet({"upgrade_sway_amplitude": 0, "upgrade_speed": 0.01})
	ok(s.upgrades.spawn_pair(s._emit, [left, right]), "pair spawned")
	var halves := []
	for u in s.upgrades.pool:
		if u.active:
			halves.append(u)
	return [s, halves]


func test_pair_is_two_different_rewards_mirrored_and_linked() -> void:
	var p := _pair()
	var halves: Array = p[1]
	eq(halves.size(), 2)
	var a = halves[0]
	var b = halves[1]
	eq([a.reward_id, b.reward_id], ["rocket", "heal"])
	eq(a.x, -b.x, "one each side of the road")
	ok(a.x < 0.0, "left first")
	eq(a.z, b.z, "side by side")
	eq([a.partner, b.partner], [b.serial, a.serial])


func test_rolled_pairs_never_offer_the_same_thing_twice() -> void:
	for seed_value in 40:
		var s := _quiet({}, seed_value)
		s.upgrades.spawn_pair(s._emit)
		var ids := []
		for u in s.upgrades.pool:
			if u.active:
				ids.append(u.reward_id)
		ok(ids.size() == 2 and ids[0] != ids[1], "seed %d gave %s" % [seed_value, ids])


func test_freeing_one_half_loses_the_other() -> void:
	var p := _pair()
	var s: Sim = p[0]
	var a = p[1][0]
	var b = p[1][1]
	a.z = 5.0
	b.z = 5.0
	_shoot(s, "railgun", a.x, 0.0)
	var ev := _run(s, 10)
	eq(_of(ev, K.ICE_SHATTERED).size(), 1)
	var lost := _of(ev, K.UPGRADE_LOST)
	eq(lost.size(), 1, "partner lost")
	if lost.size() == 1:
		eq(lost[0]["serial"], b.serial)
	ok(a.active and a.thawed, "the one you freed is yours to take")
	ok(not b.active, "the other is gone")


## Worst order: both halves break on the same step. Only the first may be freed.
func test_both_halves_shot_on_the_same_step_frees_only_one() -> void:
	var p := _pair()
	var s: Sim = p[0]
	var a = p[1][0]
	var b = p[1][1]
	a.z = 5.0
	b.z = 5.0
	_shoot(s, "railgun", a.x, 0.0)
	_shoot(s, "railgun", b.x, 0.0)
	var ev := _run(s, 10)
	eq(_of(ev, K.ICE_SHATTERED).size(), 1, "only one shatters")
	eq(_of(ev, K.UPGRADE_LOST).size(), 1)
	ok(a.active != b.active, "exactly one half left: a=%s b=%s" % [a.active, b.active])


## The partner rolled off the road and its slot now holds a new pickup with a new serial: freeing the old half
## must not destroy the stranger in that slot.
func test_freeing_a_half_never_kills_whatever_reused_the_partner_slot() -> void:
	var p := _pair()
	var s: Sim = p[0]
	var a = p[1][0]
	var b = p[1][1]
	b.active = false
	s.upgrades.spawn("armor", s._emit)
	ok(b.active and b.reward_id == "armor" and b.serial != a.partner, "slot reused by a new pickup")
	b.z = 40.0
	a.z = 5.0
	_shoot(s, "railgun", a.x, 0.0)
	var ev := _run(s, 10)
	eq(_of(ev, K.UPGRADE_LOST).size(), 0, "nothing lost")
	ok(b.active, "the new armour pickup survived")


func test_single_pickups_never_lose_anything() -> void:
	var s := _quiet({"upgrade_sway_amplitude": 0, "upgrade_speed": 0.01})
	s.upgrades.spawn("heal", s._emit)
	s.upgrades.spawn("armor", s._emit)
	var first = s.upgrades.pool[0]
	first.x = 0.0
	first.z = 5.0
	s.upgrades.pool[1].z = 5.0
	_shoot(s, "railgun", 0.0, 0.0)
	eq(_of(_run(s, 10), K.UPGRADE_LOST).size(), 0)
	ok(s.upgrades.pool[1].active, "unpaired neighbour untouched")


func test_pair_with_one_free_slot_falls_back_to_a_single() -> void:
	var s := _quiet()
	for i in s.upgrades.pool.size() - 1:
		s.upgrades.spawn("heal", s._emit)
	ok(s.upgrades.spawn_pair(s._emit), "still spawns something")
	eq(s.upgrades.active_count(), s.upgrades.pool.size())
	for u in s.upgrades.pool:
		eq(u.partner, 0, "no half-pair with a missing partner")


func test_pair_halves_weave_in_step() -> void:
	var s := _quiet({"upgrade_speed": 0.01})
	s.upgrades.spawn_pair(s._emit, ["rocket", "heal"])
	var halves := []
	for u in s.upgrades.pool:
		if u.active:
			halves.append(u)
	var gap: float = halves[1].x - halves[0].x
	for i in 120:
		s.step({})
		ok(is_equal_approx(halves[1].x - halves[0].x, gap), "gap changed at step %d" % i)
		if halves[1].x - halves[0].x != gap:
			break


# ---------- determinism and structure ----------

func _input_for(tick: int) -> Dictionary:
	return {"move": sin(tick * 0.013) * 1.3, "pick": tick % 3}  # pick only read while a level-up is open


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
	ok(a.kills > 0 and a.distance > 300.0, "the run actually played: kills=%d distance=%.0f" % [a.kills, a.distance])
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
