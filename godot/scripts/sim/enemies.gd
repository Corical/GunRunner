extends RefCounted
## Enemy pool, spawner and per-enemy movement/status. Source: src/systems/EnemyManager.ts, src/entities/Enemy.ts.
## Damage is never applied here directly: burn and poison call the sim's damage function so tower kills
## score like any other kill (plan D2).

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Rng = preload("res://scripts/sim/rng.gd")
const Events = preload("res://scripts/sim/events.gd")
const ExactMath = preload("res://scripts/sim/exact_math.gd")


class Enemy:
	extends RefCounted
	var serial := 0
	var active := false
	var type_id := ""
	var row := {}
	var x := 0.0
	var z := 0.0
	var prev_x := 0.0
	var prev_z := 0.0
	var target_x := 0.0
	var hp := 1
	var max_hp := 1
	var radius := 0.5
	var lane_timer := 0.0
	var shield_hp := 0       ## shield behaviour: soaks bullet damage first
	var elite := false       ## tougher, bigger, worth more (escalation)
	var heal_timer := 0.0    ## healer behaviour: seconds to the next heal
	## Status effects. slow and burning are set by towers each step and consumed (reset) on the next
	## enemy update, so they act one step late - Babylon parity, see sim.gd tick order.
	var slow_mult := 1.0
	var burning := false
	var burn_damage := 0     ## per burn tick, from the tower (towers.tsv burn_damage)
	var poison_damage := 0   ## per poison tick, from the tower (towers.tsv poison_damage)
	var burn_timer := 0.0
	var poison_timer := 0.0
	var poison_tick_timer := 0.0


var pool: Array[Enemy] = []
var spawn_timer := 0.0
var spawn_interval := 0.0
## > 0 = player chose a spawn interval on the Settings slider; it survives bosses (plan D16).
var manual_interval := 0.0
var spawning_paused := false
var exhausted_count := 0

var _rules: Rules
var _log: GLog
var _rng: Rng
var _next_serial := 1


func _init(rules: Rules, rng: Rng, logger: GLog) -> void:
	_rules = rules
	_rng = rng
	_log = logger
	for i in int(rules.t("enemy_pool")):
		pool.append(Enemy.new())
	spawn_interval = rules.t("spawn_interval")


func set_manual_interval(seconds: float) -> void:
	manual_interval = seconds
	spawn_interval = seconds if seconds > 0.0 else _auto_interval(0.0)
	_log.info("spawn", "interval_set", {"manual": seconds, "interval": spawn_interval})


func pause_spawning() -> void:
	spawning_paused = true


## The spawn timer kept counting during the pause, so the next wave comes immediately (Babylon parity).
func resume_spawning(distance: float) -> void:
	spawning_paused = false
	spawn_interval = manual_interval if manual_interval > 0.0 else _auto_interval(distance)


## Spawns, then moves every active enemy. `damage` is the sim's Callable(enemy, amount, source) -> bool (killed).
## `emit` is the sim's Callable(kind, fields) for ENEMY_SPAWNED / ENEMY_ESCAPED.
func update(dt: float, distance: float, damage: Callable, emit: Callable) -> void:
	spawn_timer += dt
	if not spawning_paused and spawn_timer >= spawn_interval:
		_spawn_wave(distance, emit)
		spawn_timer = 0.0
	for e in pool:
		if e.active:
			_update_enemy(e, dt, damage, emit)


func _update_enemy(e: Enemy, dt: float, damage: Callable, emit: Callable) -> void:
	e.prev_x = e.x
	e.prev_z = e.z
	var speed := _rules.t("enemy_speed") * float(e.row["speed"]) * e.slow_mult
	e.slow_mult = 1.0
	e.z -= speed * dt

	if e.burning:
		e.burn_timer += dt
		if e.burn_timer >= _rules.t("burn_tick"):
			e.burn_timer = 0.0
			if damage.call(e, e.burn_damage, "burn"):
				return
		e.burning = false
		e.burn_damage = 0

	if e.poison_timer > 0.0:
		e.poison_timer -= dt
		e.poison_tick_timer += dt
		if e.poison_tick_timer >= _rules.t("poison_tick"):
			e.poison_tick_timer = 0.0
			if damage.call(e, e.poison_damage, "poison"):
				return

	if e.row["switches_lanes"] and e.z - _rules.t("player_z") > _rules.t("flanker_lock_distance"):  # close in: straight line
		e.lane_timer -= dt
		if e.lane_timer <= 0.0:
			e.lane_timer = _rules.t("flanker_retarget_min") + _rng.next_float() * _rules.t("flanker_retarget_extra")
			var half := _half_road()
			e.target_x = _rng.range_float(-half, half)
		var dx := e.target_x - e.x
		if absf(dx) > 0.1:
			e.x += signf(dx) * minf(absf(dx), _rules.t("flanker_lateral_speed") * dt)

	if e.z < _rules.t("enemy_despawn_z"):
		e.active = false
		emit.call(Events.Kind.ENEMY_ESCAPED, {"serial": e.serial, "enemy": e.type_id})


## Escalation tier: 0 until escalation_start, then +1 every escalation_every metres.
func tier(distance: float) -> int:
	if distance < _rules.t("escalation_start"):
		return 0
	return 1 + int(floor((distance - _rules.t("escalation_start")) / _rules.t("escalation_every")))


func elite_chance(distance: float) -> float:
	return minf(_rules.t("elite_max"), _rules.t("elite_per_tier") * tier(distance))


func formation_chance(distance: float) -> float:
	if distance < _rules.t("formation_start"):
		return 0.0
	return minf(_rules.t("formation_chance_max"), _rules.t("formation_chance") + _rules.t("formation_chance_per_tier") * tier(distance))


func _spawn_wave(distance: float, emit: Callable) -> void:
	if _rng.next_float() < formation_chance(distance):
		_spawn_wall(distance, emit)
		if manual_interval <= 0.0:
			spawn_interval = _auto_interval(distance)
		return
	var cap := mini(int(_rules.t("wave_size_cap")), int(_rules.t("wave_size_max")) + int(_rules.t("escalation_wave_add")) * tier(distance))
	var wave_size := mini(cap, 1 + int(floor(distance / _rules.t("wave_size_metres"))))
	var half := _half_road()
	var gap := _rules.t("spawn_min_gap")
	var used: Array[float] = []
	var placed := 0
	var band := _band_for(distance)
	for i in wave_size:
		var e := _inactive()
		if e == null:
			# Expected late in a run: 3 enemies every 0.8 s outlive the 30-slot pool, so the pool caps how many
			# are on screen (Babylon parity). Counted in the game_over line; INFO, not a warning.
			exhausted_count += 1
			_log.info("spawn", "pool_full", {"pool": pool.size(), "wanted": wave_size, "placed": placed})
			break
		var x := 0.0
		var tries := 0
		while true:
			x = _rng.range_float(-half, half)
			tries += 1
			if tries >= int(_rules.t("spawn_tries")) or not _too_close(x, used, gap):
				break
		used.append(x)
		var type_id := _roll_type(band)
		var z := _rules.t("enemy_spawn_distance") + _rng.next_float() * _rules.t("enemy_spawn_jitter")
		_activate(e, type_id, x, z, distance)
		if _rng.next_float() < elite_chance(distance):
			_make_elite(e)
		placed += 1
		emit.call(Events.Kind.ENEMY_SPAWNED, {"serial": e.serial, "enemy": type_id, "x": x, "z": z, "elite": e.elite})
	if manual_interval <= 0.0:
		spawn_interval = _auto_interval(distance)
	_log.debug("spawn", "wave", {"distance": distance, "band": band["id"], "size": wave_size, "placed": placed, "next_in": spawn_interval})


## A wall across the road with one gap of formation_gap metres somewhere: find it (16 Oct critique: spawns were
## independent random dots, nothing to read). One type from the band; as many as the pool allows.
func _spawn_wall(distance: float, emit: Callable) -> void:
	var half := _half_road()
	var gap := _rules.t("formation_gap")
	var gap_centre := _rng.range_float(-half + gap / 2.0, half - gap / 2.0)
	var type_id := _roll_type(_band_for(distance))
	var z := _rules.t("enemy_spawn_distance")
	var x := -half
	var placed := 0
	while x <= half + 1e-6:
		if absf(x - gap_centre) >= gap / 2.0:
			var e := _inactive()
			if e == null:
				exhausted_count += 1
				break
			_activate(e, type_id, x, z, distance)
			e.target_x = x
			e.lane_timer = 1e9  # a wall holds its lanes
			placed += 1
			emit.call(Events.Kind.ENEMY_SPAWNED, {"serial": e.serial, "enemy": type_id, "x": x, "z": z, "elite": false})
		x += _rules.t("formation_spacing")
	_log.debug("spawn", "wall", {"distance": distance, "type": type_id, "gap_x": gap_centre, "placed": placed})


func _make_elite(e: Enemy) -> void:
	e.elite = true
	e.hp = int(ceil(e.hp * _rules.t("elite_hp_mult")))
	e.max_hp = e.hp
	e.radius *= _rules.t("elite_size_mult")


## A boss calls in `count` minions in a row centred on x, spread `spacing` apart, kept on the road. Works while
## wave spawning is paused. Returns how many it placed (fewer when the pool is full).
func summon(type_id: String, count: int, x: float, z: float, spacing: float, distance: float, emit: Callable) -> int:
	var half := _half_road()
	var placed := 0
	for i in count:
		var e := _inactive()
		if e == null:
			exhausted_count += 1
			_log.info("spawn", "pool_full", {"pool": pool.size(), "wanted": count, "placed": placed, "by": "boss"})
			break
		var ex := clampf(x + (i - (count - 1) / 2.0) * spacing, -half, half)
		_activate(e, type_id, ex, z, distance)
		placed += 1
		emit.call(Events.Kind.ENEMY_SPAWNED, {"serial": e.serial, "enemy": type_id, "x": ex, "z": z})
	return placed


func _activate(e: Enemy, type_id: String, x: float, z: float, distance := 0.0) -> void:
	e.serial = _next_serial
	_next_serial += 1
	e.active = true
	e.type_id = type_id
	e.row = _rules.enemies[type_id]
	e.hp = hp_at(int(e.row["hp"]), distance)
	e.max_hp = e.hp
	e.radius = float(e.row["size"]) * _rules.t("enemy_radius_per_size")
	e.x = x
	e.z = z
	e.prev_x = x
	e.prev_z = z
	e.target_x = x
	e.lane_timer = _rules.t("flanker_first_min") + _rng.next_float() * _rules.t("flanker_first_extra")
	e.slow_mult = 1.0
	e.elite = false
	e.shield_hp = hp_at(int(_rules.t("shield_hp")), distance) if e.row["behaviour"] == "shield" else 0
	e.heal_timer = _rules.t("healer_every")
	e.burning = false
	e.burn_timer = 0.0
	e.poison_timer = 0.0
	e.poison_tick_timer = 0.0
	e.burn_damage = 0
	e.poison_damage = 0


## Enemies get tougher the further you go (Babylon never raised HP, so any upgraded gun one-shot everything):
## hp = ceil(base x (1 + enemy_hp_per_100m x distance / 100) x growth(distance)).
func hp_at(base: int, distance: float) -> int:
	return ceili(base * (1.0 + _rules.t("enemy_hp_per_100m") * maxf(0.0, distance) / 100.0) * growth(distance) - 1e-9)


## Past escalation_start hp also compounds: x enemy_hp_growth_per_100m per whole 100 m (bosses too). A straight line
## never caught up with three levelled, evolved guns: the 18 km run of 16 Oct held dps/hp at ~10 from 0.5 to 17 km.
func growth(distance: float) -> float:
	var steps := int(floor(maxf(0.0, distance - _rules.t("escalation_start")) / 100.0))
	return ExactMath.int_power(_rules.t("enemy_hp_growth_per_100m"), steps)


## What an enemy touch (base 1) or bomber blast (base 2) does here: +1 per enemy_damage_every_tiers tiers.
func hit_damage(base: int, distance: float) -> int:
	return base + int(tier(distance) / int(_rules.t("enemy_damage_every_tiers")))


func _band_for(distance: float) -> Dictionary:
	var chosen: Dictionary = _rules.spawn_bands[0]
	for band in _rules.spawn_bands:
		if distance >= band["start"]:
			chosen = band
	return chosen


func _roll_type(band: Dictionary) -> String:
	var roll := _rng.range_int(0, 99)
	var cumulative := 0
	for pair in band["weights"]:
		cumulative += pair[1]
		if roll < cumulative:
			return pair[0]
	return band["weights"][0][0]


func _auto_interval(distance: float) -> float:
	return maxf(_rules.t("spawn_interval_min"), _rules.t("spawn_interval") - distance * _rules.t("spawn_interval_decay"))


func _half_road() -> float:
	return _rules.t("road_width") / 2.0 - _rules.t("enemy_road_margin")


static func _too_close(x: float, used: Array[float], gap: float) -> bool:
	for u in used:
		if absf(u - x) < gap:
			return true
	return false


func _inactive() -> Enemy:
	for e in pool:
		if not e.active:
			return e
	return null


func active_count() -> int:
	var n := 0
	for e in pool:
		if e.active:
			n += 1
	return n
