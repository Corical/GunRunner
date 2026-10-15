extends RefCounted
## Deployable towers (freeze / fire / poison). Source: src/systems/TowerManager.ts, src/entities/Tower.ts.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Events = preload("res://scripts/sim/events.gd")


class Tower:
	extends RefCounted
	var serial := 0
	var active := false
	var type_id := ""
	var row := {}
	var x := 0.0
	var z := 0.0
	var time_left := 0.0


var pool: Array[Tower] = []
var exhausted_count := 0

var _rules: Rules
var _log: GLog
var _next_serial := 1


func _init(rules: Rules, logger: GLog) -> void:
	_rules = rules
	_log = logger
	for i in int(rules.t("tower_pool")):
		pool.append(Tower.new())


## Places a tower at the player's x. When every slot is busy the pickup is still used up and nothing is
## placed (Babylon parity), logged and announced so the HUD can say so.
## duration_mult: Engineer perk (towers last longer); 1.0 = as in towers.tsv.
func deploy(type_id: String, x: float, emit: Callable, duration_mult := 1.0) -> bool:
	var t := _inactive()
	if t == null:
		exhausted_count += 1
		_log.warn("towers", "pool_exhausted", {"pool": pool.size(), "tower": type_id})
		emit.call(Events.Kind.POOL_EXHAUSTED, {"pool": "tower", "wanted": type_id})
		return false
	t.serial = _next_serial
	_next_serial += 1
	t.active = true
	t.type_id = type_id
	t.row = _rules.towers[type_id]
	t.x = x
	t.z = _rules.t("tower_z")
	t.time_left = float(t.row["duration"]) * duration_mult
	_log.info("towers", "deployed", {"serial": t.serial, "tower": type_id, "x": x})
	emit.call(Events.Kind.TOWER_DEPLOYED, {"serial": t.serial, "tower": type_id, "x": x, "z": t.z})
	return true


## Counts down, then marks enemies in range. Effects are read by the enemies on their next update.
func update(dt: float, enemies: Array, emit: Callable) -> void:
	for t in pool:
		if not t.active:
			continue
		t.time_left -= dt
		if t.time_left <= 0.0:
			t.active = false
			_log.info("towers", "expired", {"serial": t.serial, "tower": t.type_id})
			emit.call(Events.Kind.TOWER_EXPIRED, {"serial": t.serial, "tower": t.type_id})
			continue
		var r: float = t.row["radius"]
		var slow: float = t.row["slow_multiplier"]
		var burn: int = t.row["burn_damage"]
		var poison: float = t.row["poison_duration"]
		var poison_dmg: int = t.row["poison_damage"]
		for e in enemies:
			if not e.active:
				continue
			if (e.x - t.x) * (e.x - t.x) + (e.z - t.z) * (e.z - t.z) >= r * r:
				continue
			if slow < 1.0:
				e.slow_mult = minf(e.slow_mult, slow)
			if burn > 0:
				e.burning = true
				e.burn_damage = maxi(e.burn_damage, burn)
			if poison > 0.0:
				e.poison_timer = maxf(e.poison_timer, poison)
				e.poison_damage = maxi(e.poison_damage, poison_dmg)


func active_count() -> int:
	var n := 0
	for t in pool:
		if t.active:
			n += 1
	return n


func _inactive() -> Tower:
	for t in pool:
		if not t.active:
			return t
	return null
