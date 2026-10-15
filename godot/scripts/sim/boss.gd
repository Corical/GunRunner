extends RefCounted
## The boss: appears every boss_interval metres. Which boss comes is data (bosses.tsv, by wave in row order):
## a charger walks at the player and speeds up as it loses health (Boss.ts); a holder stops hold_z ahead and
## fights from there - sliding side to side, calling in minions, or firing slow shots you dodge.
## Port changes (plan D13): a charger steers toward the player's x, and if the player dodges it completely it
## comes round again from the far end instead of walking off forever.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const ExactMath = preload("res://scripts/sim/exact_math.gd")
const Collision = preload("res://scripts/sim/collision.gd")


class Shot:
	extends RefCounted
	var active := false
	var x := 0.0
	var z := 0.0
	var prev_x := 0.0
	var prev_z := 0.0
	var vx := 0.0
	var vz := 0.0
	var damage := 0


var active := false
var wave := 0
var serial := 0
var hp := 0
var max_hp := 0
var x := 0.0
var z := 0.0
var prev_x := 0.0
var prev_z := 0.0
var speed := 0.0
var row: Dictionary = {}     ## this fight's bosses.tsv row
var phase := 0.0             ## strafe position (ExactMath.wave)
var strafe_centre := 0.0     ## x it strafes around: where it stopped
var hold_left := 0.0         ## seconds of holding left; at 0 a holder charges like a brute (no endless fights)
var summon_timer := 0.0
var shoot_timer := 0.0
var shots: Array[Shot] = []
var shots_exhausted := 0

var _rules: Rules
var _log: GLog


func _init(rules: Rules, logger: GLog) -> void:
	_rules = rules
	_log = logger
	for i in int(rules.t("boss_shot_pool")):
		shots.append(Shot.new())


func activate(new_wave: int) -> void:
	wave = new_wave
	row = _rules.bosses[(new_wave - 1) % _rules.bosses.size()]
	serial = -new_wave  # unique per fight, never collides with enemy serials (> 0) in a bullet's hit set
	max_hp = maxi(1, int((_rules.t("boss_base_hp") + _rules.t("boss_hp_per_wave") * new_wave) * float(row["hp_mult"])))
	hp = max_hp
	x = 0.0
	z = _rules.t("boss_spawn_z")
	prev_x = x
	prev_z = z
	speed = row["speed"]
	phase = TAU * 0.25  # wave() = 0 here: strafing starts from where it stopped, no sideways jump
	strafe_centre = 0.0
	hold_left = row["hold_seconds"]
	summon_timer = row["summon_every"]
	shoot_timer = row["shoot_every"]
	for s in shots:
		s.active = false
	active = true
	_log.info("boss", "started", {"wave": wave, "boss": row["id"], "hp": hp})


## True while this boss is a holder that still has patience left.
func holds() -> bool:
	return row["hold_z"] > 0.0 and hold_left > 0.0


## Moves, then recomputes speed from health (Babylon order: this step used last step's speed).
func update(dt: float, player_x: float, player_z: float) -> void:
	prev_x = x
	prev_z = z
	var stop: float = player_z + row["hold_z"]
	if holds() and z <= stop:
		if hold_left == row["hold_seconds"]:  # first step in position: strafe round where it stopped, kept on the road
			var room := maxf(0.0, _rules.t("road_width") / 2.0 - _rules.t("enemy_road_margin") - row["strafe"])
			strafe_centre = clampf(x, -room, room)
		z = stop
		hold_left -= dt
		if hold_left <= 0.0:
			_log.info("boss", "charges", {"wave": wave, "boss": row["id"], "hp": hp})
		if row["strafe"] > 0.0:
			phase += dt
			x = strafe_centre + row["strafe"] * ExactMath.wave(phase)
	else:
		z -= speed * dt
		if holds():
			z = maxf(z, stop)
		var step: float = row["steer"] * dt
		x += clampf(player_x - x, -step, step)
	speed = row["speed"] + (1.0 - float(hp) / max_hp) * _rules.t("boss_speed_bonus_at_zero_hp")


## Counts down the summon timer. Returns how many minions to call this step (0 most steps). Only while holding.
func summons_due(dt: float, player_z: float) -> int:
	if row["summon_every"] <= 0.0 or not _in_position(player_z):
		return 0
	summon_timer -= dt
	if summon_timer > 0.0:
		return 0
	summon_timer += row["summon_every"]
	return row["summon_count"]


## Counts down the shot timer and fires one shot aimed at where the player is now (they dodge it by moving).
## Returns true when a shot left the barrel, false also when the pool was full.
func shoot_due(dt: float, player_x: float, player_z: float) -> bool:
	if row["shoot_every"] <= 0.0 or not _in_position(player_z):
		return false
	shoot_timer -= dt
	if shoot_timer > 0.0:
		return false
	shoot_timer += row["shoot_every"]
	var s := _free_shot()
	if s == null:
		shots_exhausted += 1
		_log.info("boss", "shot_pool_full", {"pool": shots.size()})
		return false
	var dz := maxf(1.0, z - player_z)
	s.active = true
	s.x = x
	s.z = z - _rules.t("boss_radius")
	s.prev_x = s.x
	s.prev_z = s.z
	s.vz = -float(row["shot_speed"])
	s.vx = (player_x - x) / dz * row["shot_speed"]  # straight line to the player's spot; no trig in the sim
	s.damage = row["shot_damage"]
	return true


## Moves shots. Returns the damage of every shot that hit the player this step (each hit shot is spent).
func update_shots(dt: float, player_prev_x: float, player_x: float, player_z: float) -> Array[int]:
	var hits: Array[int] = []
	var reach := _rules.t("boss_shot_radius")
	for s in shots:
		if not s.active:
			continue
		s.prev_x = s.x
		s.prev_z = s.z
		s.x += s.vx * dt
		s.z += s.vz * dt
		if Collision.swept_hit(s.prev_x, s.prev_z, s.x, s.z, player_prev_x, player_z, player_x, player_z, reach):
			s.active = false
			hits.append(s.damage)
		elif s.z < _rules.t("enemy_despawn_z"):
			s.active = false
	return hits


## 0 = no contact, 1 = touching the player, 2 = passed the player entirely.
func contact(player_x: float, player_z: float) -> int:
	var reach := _rules.t("boss_contact_player_radius") + _rules.t("boss_radius")
	var dz := z - player_z
	if dz <= -reach:
		return 2
	if dz < reach and absf(x - player_x) < row["contact_dx"]:
		return 1
	return 0


func push_back() -> void:
	z += _rules.t("boss_pushback")


func wrap_around() -> void:
	z = _rules.t("boss_spawn_z")
	prev_z = z
	_log.info("boss", "wrapped", {"wave": wave, "hp": hp})


## Returns true when this hit defeated the boss. Its shots in flight vanish with it.
func take_damage(amount: int) -> bool:
	hp = maxi(0, hp - amount)
	if hp == 0:
		active = false
		for s in shots:
			s.active = false
		return true
	return false


func _in_position(player_z: float) -> bool:
	return holds() and z <= player_z + row["hold_z"]


func _free_shot() -> Shot:
	for s in shots:
		if not s.active:
			return s
	return null
