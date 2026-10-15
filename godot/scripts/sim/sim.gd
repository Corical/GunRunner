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
##  10 bullets hit ice          11 thawed rewards picked up
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
const Boss = preload("res://scripts/sim/boss.gd")

const STEP := 1.0 / 60.0

var tick := 0
var distance := 0.0
var score := 0
var kills := 0
var combo := 0
var over := false
var events: Array[Dictionary] = []

var rules: Rules
var rng: Rng
var player: Player
var bullets: Bullets
var enemies: Enemies
var towers: Towers
var upgrades: Upgrades
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
	boss = Boss.new(rules, logger)
	_emit = _push_event
	_damage = damage_enemy
	_log.info("sim", "start", {"seed": seed_value})


## input: {"move": float in [-1, 1]}. Missing, NaN or infinite values count as 0.
func step(input: Dictionary) -> void:
	events.clear()
	if over:
		return
	tick += 1
	_log.tick = tick
	var dt := STEP

	player.prev_x = player.x
	player.move(_axis(input.get("move", 0.0)), dt)
	player.update_timers(dt)
	if player.try_fire():
		var w := player.weapon()
		var fired := bullets.fire(player.x, player.z + rules.t("muzzle_z_offset"), w, player.shot_damage())
		if fired > 0:
			_push_event(Events.Kind.FIRED, {"weapon": w["id"], "x": player.x, "z": player.z, "bullets": fired})
		if fired < int(w["bullet_count"]):
			_push_event(Events.Kind.POOL_EXHAUSTED, {"pool": "bullet", "wanted": w["bullet_count"]})
	bullets.update(dt)
	enemies.update(dt, distance, _damage, _emit)
	towers.update(dt, enemies.pool, _emit)
	_bullets_vs_enemies()
	if boss.active:
		_boss_step(dt)
	if not boss.active and rng.next_float() < rules.t("upgrade_spawn_per_second") * dt:
		upgrades.spawn("", _emit)
	upgrades.update(dt, _emit)
	_bullets_vs_ice()
	_pickups()
	_enemies_vs_player()
	if not boss.active and distance >= (boss.wave + 1) * rules.t("boss_interval"):
		_start_boss()
	distance += dt * rules.t("game_speed")
	if not player.alive():
		_game_over()


## The only way an enemy loses health. Applies scoring on a kill. Returns true if the enemy died.
func damage_enemy(e: Enemies.Enemy, amount: int, source: String) -> bool:
	if not e.active:
		return false
	e.hp -= amount
	if e.hp > 0:
		_push_event(Events.Kind.ENEMY_HIT, {"serial": e.serial, "enemy": e.type_id, "x": e.x, "z": e.z, "amount": amount, "source": source})
		return false
	e.active = false
	var gain: int = int(e.row["score"]) * maxi(1, combo)
	score += gain
	kills += 1
	combo += 1
	_log.debug("score", "kill", {"enemy": e.type_id, "source": source, "gain": gain, "combo": combo})
	_push_event(Events.Kind.ENEMY_KILLED, {
		"serial": e.serial, "enemy": e.type_id, "x": e.x, "z": e.z, "amount": amount, "source": source,
		"score_gain": gain, "combo": combo,
	})
	return true


## Damage after the weapon-vs-enemy table: max(1, round(base * multiplier)).
func effective_damage(base: int, weapon_id: String, enemy_id: String) -> int:
	return maxi(1, int(round(base * rules.multiplier(weapon_id, enemy_id))))


func _bullets_vs_enemies() -> void:
	var hit_r := rules.t("bullet_hit_radius")
	for b in bullets.pool:
		if not b.active:
			continue
		for e in enemies.pool:
			if not e.active or b.hit.has(e.serial):
				continue
			if not Collision.swept_hit(b.prev_x, b.prev_z, b.x, b.z, e.prev_x, e.prev_z, e.x, e.z, hit_r + e.radius):
				continue
			b.hit[e.serial] = true
			var hx := e.x
			var hz := e.z
			damage_enemy(e, effective_damage(b.damage, b.weapon_id, e.type_id), "bullet")
			if b.splash_radius > 0.0:
				_splash(b, hx, hz, e)
			if bullets.spend(b):
				break


## Splash centred on the enemy that was hit: up to splash_max_victims others, half damage (min 1),
## weapon-vs-enemy table applied (plan D4; Babylon ignored it for splash).
func _splash(b: Bullets.Bullet, cx: float, cz: float, centre: Enemies.Enemy) -> void:
	var r2 := b.splash_radius * b.splash_radius
	var base := maxi(1, b.damage / 2)
	var victims := 0
	for other in enemies.pool:
		if victims >= int(rules.t("splash_max_victims")):
			break
		if not other.active or other == centre:
			continue
		if Collision.dist_sq(cx, cz, other.x, other.z) >= r2:
			continue
		damage_enemy(other, effective_damage(base, b.weapon_id, other.type_id), "splash")
		victims += 1


func _boss_step(dt: float) -> void:
	boss.update(dt, player.x)
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
			_hurt_player(int(rules.t("boss_contact_damage")), "boss")
			_push_event(Events.Kind.BOSS_CONTACT, {"damage": rules.t("boss_contact_damage")})
			boss.push_back()
		2:
			boss.wrap_around()
			_push_event(Events.Kind.BOSS_WRAPPED, {"wave": boss.wave})


func _start_boss() -> void:
	boss.activate(boss.wave + 1)
	enemies.pause_spawning()
	_push_event(Events.Kind.BOSS_STARTED, {"wave": boss.wave, "hp": boss.hp})


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
	for b in bullets.pool:
		if not b.active:
			continue
		for u in upgrades.pool:
			if not u.active or u.thawed:
				continue
			if not Collision.swept_hit(b.prev_x, b.prev_z, b.x, b.z, u.prev_x, u.prev_z, u.x, u.z, reach):
				continue
			var shattered := upgrades.hit_ice(u, b.damage)
			b.active = false
			if shattered:
				_log.info("upgrades", "shattered", {"serial": u.serial, "reward": u.reward_id})
				_push_event(Events.Kind.ICE_SHATTERED, {"serial": u.serial, "reward": u.reward_id, "x": u.x, "z": u.z})
			else:
				_push_event(Events.Kind.ICE_HIT, {"serial": u.serial, "x": u.x, "z": u.z, "amount": b.damage, "ice_hp": u.ice_hp})
			break


func _pickups() -> void:
	for u in upgrades.pool:
		if not u.active or not u.thawed:
			continue
		if absf(u.x - player.x) >= rules.t("pickup_dx") or absf(u.z - player.z) >= rules.t("pickup_dz"):
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
			towers.deploy(u.reward_id, player.x, _emit)
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
		_hurt_player(1, "enemy")
	if hits > 0 and combo > 0:
		_push_event(Events.Kind.COMBO_BROKEN, {"combo": combo})
	if hits > 0:
		combo = 0


func _hurt_player(amount: int, source: String) -> void:
	var r := player.take_damage(amount)
	_log.info("player", "hurt", {"amount": amount, "absorbed": r["absorbed"], "hp": player.hp, "armor": player.armor, "source": source})
	_push_event(Events.Kind.PLAYER_HURT, {"amount": amount, "absorbed": r["absorbed"], "hp": player.hp, "armor": player.armor, "source": source})


func _game_over() -> void:
	over = true
	_log.info("sim", "game_over", {
		"score": score, "distance": distance, "kills": kills, "ticks": tick,
		"bullet_pool_full": bullets.exhausted_count, "enemy_pool_full": enemies.exhausted_count,
		"tower_pool_full": towers.exhausted_count, "upgrade_pool_full": upgrades.exhausted_count,
	})
	_push_event(Events.Kind.GAME_OVER, {"score": score, "distance": distance, "kills": kills})


func _push_event(kind: int, fields: Dictionary) -> void:
	assert(not fields.has("kind"), "event field 'kind' is reserved for the event type: %s" % [fields])
	fields["kind"] = kind
	events.append(fields)


static func _axis(v: Variant) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return 0.0
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return 0.0
	return clampf(f, -1.0, 1.0)


## Everything that affects future steps, hashed. Equal hashes = equal games.
func state_hash() -> int:
	var parts: Array = [tick, distance, score, kills, combo, over, rng.state(),
		player.x, player.hp, player.max_hp, player.armor, player.weapon_id, player.fire_timer,
		player.frenzy_timer, player.speed_timer, enemies.spawn_timer, enemies.spawn_interval, enemies.spawning_paused]
	for e in enemies.pool:
		if e.active:
			parts.append_array([e.serial, e.type_id, e.x, e.z, e.hp, e.target_x, e.lane_timer, e.slow_mult, e.burning, e.burn_timer, e.poison_timer, e.poison_tick_timer])
	for b in bullets.pool:
		if b.active:
			parts.append_array([b.serial, b.x, b.z, b.damage, b.penetration, b.hit.size()])
	for u in upgrades.pool:
		if u.active:
			parts.append_array([u.serial, u.reward_id, u.x, u.z, u.ice_hp, u.thawed])
	for t in towers.pool:
		if t.active:
			parts.append_array([t.serial, t.type_id, t.x, t.time_left])
	parts.append_array([boss.active, boss.wave, boss.hp, boss.x, boss.z, boss.speed])
	return hash(parts)
