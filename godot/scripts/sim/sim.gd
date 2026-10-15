extends RefCounted
## The whole game rules, with no rendering, no clock and no global randomness.
## step() advances exactly 1/60 s and fills `events`. Same seed + same inputs = same game, on any frame rate.
##
## Tick order (Babylon GameManager.update order, so same-tick outcomes match):
##   1 player moves            2 player timers          3 auto-fire
##   4 bullets move            5 enemies spawn + move (burn/poison applied here, set by towers LAST step)
##   6 towers count down and mark enemies in range (read next step)
##   7 bullets hit enemies (swept, pool order, splash, penetration)
##   8 boss moves, bullets hit boss, boss touches player
##   9 maybe spawn an upgrade (not during a boss), upgrades move
##  10 bullets hit ice; maybe spawn a trap (not during a boss), traps move, bullets hit traps, traps touched
##  11 thawed rewards picked up
##  12 enemies reaching the player hurt them and break the combo
##  13 boss trigger             14 distance grows          15 game over
## Consequences, each tested in test_sim.gd:
## - an enemy killed by a bullet in the step it reaches the player does NOT hurt the player (7 before 12);
## - a heal picked up in the step an enemy reaches the player is applied first (11 before 12);
## - death is decided once, at the end of the step (15), so nothing after it in the same step is undone.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Rng = preload("res://scripts/sim/rng.gd")
const Events = preload("res://scripts/sim/events.gd")
const Collision = preload("res://scripts/sim/collision.gd")
const Player = preload("res://scripts/sim/player.gd")
const Bullets = preload("res://scripts/sim/bullets.gd")
const Enemies = preload("res://scripts/sim/enemies.gd")
const Towers = preload("res://scripts/sim/towers.gd")
const Upgrades = preload("res://scripts/sim/upgrades.gd")
const Traps = preload("res://scripts/sim/traps.gd")
const ExactMath = preload("res://scripts/sim/exact_math.gd")
const Boss = preload("res://scripts/sim/boss.gd")

const STEP := 1.0 / 60.0

var tick := 0
var distance := 0.0
var score := 0
var kills := 0
var combo := 0
var over := false
## Level-ups: kills give xp (enemy base score). While `choices` is not empty the game waits for a pick:
## step() does nothing until its input carries {"pick": index}.
var xp := 0
var level := 1
var choices: PackedStringArray = []
var pending_levels := 0
var events: Array[Dictionary] = []

var rules: Rules
var rng: Rng
var player: Player
var bullets: Bullets
var enemies: Enemies
var towers: Towers
var upgrades: Upgrades
var traps: Traps
var boss: Boss

var _log: GLog
var _emit: Callable
var _damage: Callable


func _init(game_rules: Rules, seed_value: int, logger: GLog) -> void:
	assert(game_rules.ok(), "sim given rules with errors")
	rules = game_rules
	_log = logger
	rng = Rng.new(seed_value)
	player = Player.new(rules, logger)
	bullets = Bullets.new(rules, logger)
	enemies = Enemies.new(rules, rng, logger)
	towers = Towers.new(rules, logger)
	upgrades = Upgrades.new(rules, rng, logger)
	traps = Traps.new(rules, rng, logger)
	boss = Boss.new(rules, logger)
	_emit = _push_event
	_damage = damage_enemy
	_log.info("sim", "start", {"seed": seed_value})


## input: {"move": float in [-1, 1]} for keys/bot, or {"target_x": float} while dragging (wins over move).
## Missing, NaN, infinite or non-number values count as "no input".
func step(input: Dictionary) -> void:
	events.clear()
	if over:
		return
	if not choices.is_empty():
		var pick = input.get("pick", null)
		if typeof(pick) != TYPE_INT and typeof(pick) != TYPE_FLOAT:
			return  # waiting for the player to choose; no time passes
		var i := int(pick)
		if i < 0 or i >= choices.size():
			_log.warn("levels", "bad_pick", {"pick": i, "choices": choices.size()})
			return
		_take_perk(choices[i])
		choices.clear()
		if pending_levels > 0:
			pending_levels -= 1
			_offer_perks()
			return
	tick += 1
	_log.tick = tick
	var dt := STEP

	player.prev_x = player.x
	player.move(_axis(input.get("move", 0.0)), _target(input.get("target_x", NAN)), dt)
	player.update_timers(dt)
	if player.try_fire():
		var w := player.weapon()
		var fired := bullets.fire(player.x, player.z + rules.t("muzzle_z_offset"), w, player.shot_damage(), player.mods)
		if fired > 0:
			_push_event(Events.Kind.FIRED, {"weapon": w["id"], "x": player.x, "z": player.z, "bullets": fired})
		if fired < int(w["bullet_count"]):
			_push_event(Events.Kind.POOL_EXHAUSTED, {"pool": "bullet", "wanted": w["bullet_count"]})
	bullets.update(dt)
	enemies.update(dt, distance, _damage, _emit)
	towers.update(dt, enemies.pool, _emit)
	_bullets_vs_enemies()
	for b in bullets.detonations:
		_splash(b, b.x, b.z, null)  # grenade/rocket reached the end of its range: it explodes there
	if boss.active:
		_boss_step(dt)
	if not boss.active and rng.next_float() < rules.t("upgrade_spawn_per_second") * dt and _drop_lane_clear():
		if rng.next_float() < rules.t("upgrade_pair_chance"):
			upgrades.spawn_pair(_emit)
		else:
			upgrades.spawn("", _emit)
	upgrades.update(dt, _emit)
	_bullets_vs_ice()
	if not boss.active and rng.next_float() < rules.t("trap_spawn_per_second") * dt and _drop_lane_clear():
		traps.spawn("", _emit)
	traps.update(dt, _emit)
	_bullets_vs_traps()
	_trap_contact()
	_pickups()
	_enemies_vs_player()
	if not boss.active and distance >= (boss.wave + 1) * rules.t("boss_interval"):
		_start_boss()
	distance += dt * rules.t("game_speed")
	_check_level_up()
	if not player.alive():
		_game_over()


## The only way an enemy loses health. Applies scoring on a kill. Returns true if the enemy died.
## weapon: the weapon id for bullet/splash damage, "fire"/"poison" tower ids for burn/poison (stats attribution).
func damage_enemy(e: Enemies.Enemy, amount: int, source: String, weapon := "") -> bool:
	if not e.active:
		return false
	if weapon == "":
		weapon = "fire" if source == "burn" else ("poison" if source == "poison" else source)
	e.hp -= amount
	if e.hp > 0:
		_push_event(Events.Kind.ENEMY_HIT, {"serial": e.serial, "enemy": e.type_id, "x": e.x, "z": e.z, "amount": amount, "source": source, "weapon": weapon})
		return false
	e.active = false
	var gain: int = int(e.row["score"]) * maxi(1, combo)
	score += gain
	kills += 1
	xp += int(e.row["score"])
	combo += 1
	_log.debug("score", "kill", {"enemy": e.type_id, "source": source, "gain": gain, "combo": combo})
	_push_event(Events.Kind.ENEMY_KILLED, {
		"serial": e.serial, "enemy": e.type_id, "x": e.x, "z": e.z, "amount": amount, "source": source,
		"weapon": weapon, "score_gain": gain, "combo": combo,
	})
	return true


## xp needed to go from `lvl` to lvl+1.
func xp_needed(lvl: int) -> int:
	return maxi(1, int(round(rules.t("xp_base") * ExactMath.int_power(rules.t("xp_growth"), lvl - 1))))  # never 0: that loops forever


func _check_level_up() -> void:
	while xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		if choices.is_empty():
			_offer_perks()
		else:
			pending_levels += 1


## Rolls up to 3 different perks that still have stacks left (weighted, seeded). None left = no pause.
func _offer_perks() -> void:
	var pool: Array[Dictionary] = []
	for row in rules.perks:
		if player.perk_stacks.get(row["id"], 0) < int(row["max_stacks"]):
			pool.append(row)
	choices.clear()
	while choices.size() < 3 and not pool.is_empty():
		var total := 0
		for row in pool:
			total += int(row["weight"])
		var roll := rng.range_int(0, total - 1)
		for j in pool.size():
			roll -= int(pool[j]["weight"])
			if roll < 0:
				choices.append(pool[j]["id"])
				pool.remove_at(j)
				break
	_log.info("levels", "level_up", {"level": level, "choices": ",".join(choices)})
	_push_event(Events.Kind.LEVEL_UP, {"level": level, "choices": choices.duplicate()})


func _take_perk(id: String) -> void:
	for row in rules.perks:
		if row["id"] == id:
			player.apply_perk(row)
			_push_event(Events.Kind.PERK_TAKEN, {"perk": id, "stacks": player.perk_stacks[id], "level": level})
			return
	_log.error("levels", "unknown_perk", {"perk": id})


## Damage after the weapon-vs-enemy table: max(1, round(base * multiplier)).
func effective_damage(base: int, weapon_id: String, enemy_id: String) -> int:
	return maxi(1, int(round(base * rules.multiplier(weapon_id, enemy_id))))


var _candidates: Array = []  ## [entry t, serial, enemy] for one bullet; reused to avoid per-bullet allocation
var _live: Array[Enemies.Enemy] = []  ## active enemies this step (reused)


static func _nearer(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])


func _bullets_vs_enemies() -> void:
	var hit_r := rules.t("bullet_hit_radius")
	# Live enemies once per step, with each one's z/x extent this step (bench: this loop was 85% of the sim).
	_live.clear()
	for e in enemies.pool:
		if e.active:
			_live.append(e)
	for b in bullets.pool:
		if not b.active:
			continue
		_candidates.clear()
		var bz0 := minf(b.prev_z, b.z)
		var bz1 := maxf(b.prev_z, b.z)
		var bx0 := minf(b.prev_x, b.x)
		var bx1 := maxf(b.prev_x, b.x)
		for e in _live:
			# Exact reject: if this step's z (or x) ranges are further apart than the reach, the swept test is
			# false too (both move in straight lines over the step), so skipping changes no result.
			var reach: float = hit_r + e.radius
			if minf(e.prev_z, e.z) - reach > bz1 or maxf(e.prev_z, e.z) + reach < bz0:
				continue
			if minf(e.prev_x, e.x) - reach > bx1 or maxf(e.prev_x, e.x) + reach < bx0:
				continue
			if not e.active or b.hit.has(e.serial):
				continue
			var at := Collision.swept_entry(b.prev_x, b.prev_z, b.x, b.z, e.prev_x, e.prev_z, e.x, e.z, hit_r + e.radius)
			if at >= 0.0:
				_candidates.append([at, e.serial, e])
		if _candidates.size() > 1:
			_candidates.sort_custom(_nearer)  # path order; serial breaks ties so replays match
		for cand in _candidates:
			var e: Enemies.Enemy = cand[2]
			if not e.active:
				continue  # killed by this bullet's own splash a moment ago
			b.hit[e.serial] = true
			var hx := e.x
			var hz := e.z
			var dmg := effective_damage(b.damage, b.weapon_id, e.type_id)
			if player.crit_chance() > 0.0 and rng.next_float() < player.crit_chance():
				dmg *= 2
				_push_event(Events.Kind.CRIT, {"x": e.x, "z": e.z, "amount": dmg, "enemy": e.type_id})
			damage_enemy(e, dmg, "bullet", b.weapon_id)
			if b.splash_radius > 0.0:
				_splash(b, hx, hz, e)
			if bullets.spend(b):
				break


## Splash centred on the enemy that was hit: up to splash_max_victims others, half damage (min 1),
## weapon-vs-enemy table applied (plan D4; Babylon ignored it for splash).
## centre: the enemy that was hit directly (excluded, it already took the full hit); null for a detonation.
func _splash(b: Bullets.Bullet, cx: float, cz: float, centre: Enemies.Enemy) -> void:
	_push_event(Events.Kind.EXPLOSION, {"x": cx, "z": cz, "radius": b.splash_radius, "weapon": b.weapon_id, "impact": centre != null})
	var r2 := b.splash_radius * b.splash_radius
	var base := maxi(1, b.damage / 2)
	# Nearest victims first (Fable review #3: pool-slot order picked who got splashed).
	var near: Array = []
	for other in enemies.pool:
		if not other.active or other == centre:
			continue
		var d2 := Collision.dist_sq(cx, cz, other.x, other.z)
		if d2 < r2:
			near.append([d2, other.serial, other])
	near.sort_custom(_nearer)
	var cap := int(rules.t("splash_max_victims"))
	for i in mini(cap, near.size()):
		var other: Enemies.Enemy = near[i][2]
		damage_enemy(other, effective_damage(base, b.weapon_id, other.type_id), "splash", b.weapon_id)


func _boss_step(dt: float) -> void:
	boss.update(dt, player.x, player.z)
	var calls := boss.summons_due(dt, player.z)
	if calls > 0:
		var z := boss.z - rules.t("boss_radius") - 1.0
		var placed := enemies.summon(boss.row["summon_enemy"], calls, boss.x, z, 2.5, distance, _emit)
		_push_event(Events.Kind.BOSS_SUMMONED, {"boss": boss.row["id"], "x": boss.x, "z": z, "count": placed})
	if boss.shoot_due(dt, player.x, player.z):
		_push_event(Events.Kind.BOSS_SHOT, {"boss": boss.row["id"], "x": boss.x, "z": boss.z})
	for dmg in boss.update_shots(dt, player.prev_x, player.x, player.z):
		_hurt_player(dmg, "boss", boss.row["id"] + "_shot", boss.x)
	var reach := rules.t("bullet_hit_radius") + rules.t("boss_radius")
	for b in bullets.pool:
		if not b.active or b.hit.has(boss.serial):
			continue
		if not Collision.swept_hit(b.prev_x, b.prev_z, b.x, b.z, boss.prev_x, boss.prev_z, boss.x, boss.z, reach):
			continue
		b.hit[boss.serial] = true
		var defeated := boss.take_damage(b.damage)
		_push_event(Events.Kind.BOSS_HIT, {"x": b.x, "z": b.z, "amount": b.damage, "hp": boss.hp, "max_hp": boss.max_hp})
		bullets.spend(b)
		if defeated:
			_boss_defeated()
			return
	match boss.contact(player.x, player.z):
		1:
			var hit: int = boss.row["contact_damage"]
			_hurt_player(hit, "boss", boss.row["id"], boss.x)
			_push_event(Events.Kind.BOSS_CONTACT, {"damage": hit})
			boss.push_back()
		2:
			boss.wrap_around()
			_push_event(Events.Kind.BOSS_WRAPPED, {"wave": boss.wave})


## True when the newest pickup or trap has moved at least drop_min_gap metres down the road, so a new one cannot
## land on top of it (Corne, 15 Oct: "they spawn all over, they on top of each other").
func _drop_lane_clear() -> bool:
	var limit := rules.t("enemy_spawn_distance") + rules.t("enemy_spawn_jitter") - rules.t("drop_min_gap")
	for u in upgrades.pool:
		if u.active and u.z > limit:
			return false
	for t in traps.pool:
		if t.active and t.z > limit:
			return false
	return true


## Debug and replay: fight the boss with bosses.tsv id `id` right now (as its first appearance). Returns false
## for an unknown id or when a boss is already on.
func start_boss_now(id: String) -> bool:
	if boss.active:
		return false
	for i in rules.bosses.size():
		if rules.bosses[i]["id"] == id:
			boss.wave = i  # _start_boss fights wave + 1, which is this row
			_start_boss()
			return true
	return false


func _start_boss() -> void:
	boss.activate(boss.wave + 1)
	enemies.pause_spawning()
	_push_event(Events.Kind.BOSS_STARTED, {"wave": boss.wave, "hp": boss.hp, "boss": boss.row["id"], "name": boss.row["name"]})


func _boss_defeated() -> void:
	var gain := int(rules.t("boss_score_per_wave")) * boss.wave
	score += gain
	enemies.resume_spawning(distance)
	_log.info("boss", "defeated", {"wave": boss.wave, "score_gain": gain, "distance": distance})
	_push_event(Events.Kind.BOSS_DEFEATED, {"wave": boss.wave, "x": boss.x, "z": boss.z, "score_gain": gain})
	upgrades.spawn("", _emit)


## Ice stops any bullet, whatever its penetration (Babylon parity, plan D6).
func _bullets_vs_ice() -> void:
	var reach := rules.t("bullet_hit_radius") + rules.t("upgrade_radius")
	if upgrades.active_count() == 0:
		return  # most steps: no ice on the road, nothing to test
	for b in bullets.pool:
		if not b.active:
			continue
		for u in upgrades.pool:
			if not u.active or u.thawed:
				continue
			if not Collision.extents_overlap(b.prev_x, b.prev_z, b.x, b.z, u.prev_x, u.prev_z, u.x, u.z, reach):
				continue
			if not Collision.swept_hit(b.prev_x, b.prev_z, b.x, b.z, u.prev_x, u.prev_z, u.x, u.z, reach):
				continue
			var shattered := upgrades.hit_ice(u, b.damage)
			b.active = false
			if shattered:
				_log.info("upgrades", "shattered", {"serial": u.serial, "reward": u.reward_id})
				_push_event(Events.Kind.ICE_SHATTERED, {"serial": u.serial, "reward": u.reward_id, "x": u.x, "z": u.z})
				var other = upgrades.frozen_partner(u)
				if other != null:
					upgrades.lose(other, _emit)
			else:
				_push_event(Events.Kind.ICE_HIT, {"serial": u.serial, "x": u.x, "z": u.z, "amount": b.damage, "ice_hp": u.ice_hp})
			break


## A trap stops the bullet that hits it (like ice). Shot to 0 hp it is gone, harmlessly.
func _bullets_vs_traps() -> void:
	var reach := rules.t("bullet_hit_radius") + rules.t("upgrade_radius")
	var any := false
	for t in traps.pool:
		any = any or t.active
	if not any:
		return  # most steps: no trap on the road
	for b in bullets.pool:
		if not b.active:
			continue
		for t in traps.pool:
			if not t.active:
				continue
			if not Collision.extents_overlap(b.prev_x, b.prev_z, b.x, b.z, t.prev_x, t.prev_z, t.x, t.z, reach):
				continue
			if not Collision.swept_hit(b.prev_x, b.prev_z, b.x, b.z, t.prev_x, t.prev_z, t.x, t.z, reach):
				continue
			b.active = false
			if traps.hit(t, b.damage):
				_log.info("traps", "destroyed", {"serial": t.serial, "trap": t.trap_id})
				_push_event(Events.Kind.TRAP_DESTROYED, {"serial": t.serial, "trap": t.trap_id, "x": t.x, "z": t.z})
			else:
				_push_event(Events.Kind.TRAP_HIT, {"serial": t.serial, "x": t.x, "z": t.z, "amount": b.damage, "hp": t.hp})
			break


## Touching a trap sets off its debuff. Same reach as a pickup, but Magnet does not widen it: Magnet pulls
## rewards toward you, it should never pull traps into you.
func _trap_contact() -> void:
	for t in traps.pool:
		if not t.active:
			continue
		if absf(t.x - player.x) >= rules.t("pickup_dx") or absf(t.z - player.z) >= rules.t("pickup_dz"):
			continue
		t.active = false
		var row := traps.row_for(t.trap_id)
		player.apply_trap(row)
		_log.info("traps", "triggered", {"serial": t.serial, "trap": t.trap_id, "effect": row["effect"], "seconds": row["seconds"]})
		_push_event(Events.Kind.TRAP_TRIGGERED, {"serial": t.serial, "trap": t.trap_id, "effect": row["effect"],
			"seconds": row["seconds"], "x": t.x, "z": t.z})


func _pickups() -> void:
	for u in upgrades.pool:
		if not u.active or not u.thawed:
			continue
		var reach: float = 1.0 + player.mods["pickup_mult"]
		if absf(u.x - player.x) >= rules.t("pickup_dx") * reach or absf(u.z - player.z) >= rules.t("pickup_dz") * reach:
			continue
		u.active = false
		_apply_reward(u)
		_log.info("upgrades", "picked_up", {"serial": u.serial, "reward": u.reward_id})
		_push_event(Events.Kind.PICKUP, {"serial": u.serial, "reward": u.reward_id, "reward_kind": u.kind, "x": u.x, "z": u.z})


func _apply_reward(u: Upgrades.Upgrade) -> void:
	match u.kind:
		"weapon":
			player.set_weapon(u.reward_id)
		"tower":
			towers.deploy(u.reward_id, player.x, _emit, 1.0 + player.mods["tower_duration_mult"])
		"heal":
			player.heal(int(rules.t("heal_amount")))
		"armor":
			player.add_armor(int(rules.t("armor_amount")))
		"maxhp":
			player.add_max_hp(int(rules.t("maxhp_amount")))
		"frenzy":
			player.start_frenzy(rules.t("frenzy_seconds"))
		"speed":
			player.start_speed_buff(rules.t("speed_buff_seconds"))
		_:
			_log.error("upgrades", "unknown_kind", {"reward_kind": u.kind, "reward": u.reward_id})


func _enemies_vs_player() -> void:
	var reach_z := player.z + rules.t("enemy_hit_player_radius")
	var hits := 0
	for e in enemies.pool:
		if not e.active or e.z > reach_z:
			continue
		if absf(e.x - player.x) >= rules.t("enemy_hit_player_radius") + e.radius:
			continue
		e.active = false
		hits += 1
		_hurt_player(1, "enemy", e.type_id, e.x)
	if hits > 0 and combo > 0:
		_push_event(Events.Kind.COMBO_BROKEN, {"combo": combo})
	if hits > 0:
		combo = 0


## by: the enemy type ("boss" for the boss); by_x: where it hit from; player_x: where the player stood.
func _hurt_player(amount: int, source: String, by: String, by_x: float) -> void:
	var r := player.take_damage(amount)
	var fields := {"amount": amount, "absorbed": r["absorbed"], "hp": player.hp, "armor": player.armor, "source": source,
		"by": by, "by_x": by_x, "player_x": player.x, "weapon": player.weapon_id, "distance": distance}
	_log.info("player", "hurt", fields)
	_push_event(Events.Kind.PLAYER_HURT, fields.duplicate())


func _game_over() -> void:
	over = true
	_log.info("sim", "game_over", {
		"score": score, "distance": distance, "kills": kills, "ticks": tick,
		"bullet_pool_full": bullets.exhausted_count, "enemy_pool_full": enemies.exhausted_count,
		"tower_pool_full": towers.exhausted_count, "upgrade_pool_full": upgrades.exhausted_count, "trap_pool_full": traps.exhausted_count,
	})
	_push_event(Events.Kind.GAME_OVER, {"score": score, "distance": distance, "kills": kills})


func _push_event(kind: int, fields: Dictionary) -> void:
	assert(not fields.has("kind"), "event field kind is reserved for the event type")  # constant message: no per-event string
	fields["kind"] = kind
	events.append(fields)


static func _axis(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0.0
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return 0.0
	return snappedf(clampf(f, -1.0, 1.0), INPUT_GRID)


## Drag target: a finite number, else NaN (= not dragging). Rounded like every input (see INPUT_GRID).
static func _target(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return NAN
	var f := float(v)
	return NAN if is_inf(f) or is_nan(f) else snappedf(f, INPUT_GRID)


## Inputs are rounded to 1/4096: such values have short exact decimal forms, so a recorded run survives JSON
## exactly. Unrounded, -0.19641278469132342 came back as ...345 and a replay diverged at tick 96.
const INPUT_GRID := 1.0 / 4096.0


## The input exactly as the sim will use it; record this, not the raw controller value.
## "pick" is kept only while a level-up is open (choosing = true): then a pick is always an input change, so
## the recorder (which writes changes) always records it, and a replay can treat it as one-shot.
static func quantize_input(inp: Dictionary, choosing := false) -> Dictionary:
	var out := {}
	if choosing and (typeof(inp.get("pick")) == TYPE_INT or typeof(inp.get("pick")) == TYPE_FLOAT):
		out["pick"] = int(inp["pick"])
	if inp.has("move"):
		out["move"] = _axis(inp["move"])
	if inp.has("target_x") and not is_nan(_target(inp["target_x"])):
		out["target_x"] = _target(inp["target_x"])
	return out


## Everything that affects future steps, hashed. Equal hashes = equal games.
func state_hash() -> int:
	var parts: Array = [tick, distance, score, kills, combo, over, rng.state(),
		player.x, player.vx, player.hp, player.max_hp, player.armor, player.weapon_id, player.fire_timer,
		player.frenzy_timer, player.speed_timer, player.trap_left,
		enemies.spawn_timer, enemies.spawn_interval, enemies.spawning_paused]
	for e in enemies.pool:
		if e.active:
			parts.append_array([e.serial, e.type_id, e.x, e.z, e.hp, e.target_x, e.lane_timer, e.slow_mult, e.burning, e.burn_timer, e.poison_timer, e.poison_tick_timer, e.burn_damage, e.poison_damage])
	for b in bullets.pool:
		if b.active:
			parts.append_array([b.serial, b.x, b.z, b.vx, b.vz, b.start_z, b.damage, b.penetration, b.splash_radius,
				b.max_range, b.weapon_id, b.detonates, b.hit.keys()])
	for u in upgrades.pool:
		if u.active:
			parts.append_array([u.serial, u.reward_id, u.x, u.z, u.ice_hp, u.thawed, u.phase, u.centre_x, u.partner])
	for t in traps.pool:
		if t.active:
			parts.append_array([t.serial, t.trap_id, t.x, t.z, t.hp, t.phase, t.centre_x])
	for t in towers.pool:
		if t.active:
			parts.append_array([t.serial, t.type_id, t.x, t.time_left])
	parts.append_array([boss.active, boss.wave, boss.hp, boss.max_hp, boss.x, boss.z, boss.speed, enemies.manual_interval,
		boss.row.get("id", ""), boss.phase, boss.summon_timer, boss.shoot_timer, boss.hold_left, boss.strafe_centre])
	for sh in boss.shots:
		if sh.active:
			parts.append_array([sh.x, sh.z, sh.vx, sh.vz, sh.damage])
	parts.append_array([xp, level, choices, pending_levels, player.perk_stacks, player.mods])
	return hash(parts)
