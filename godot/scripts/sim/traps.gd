extends RefCounted
## Booby traps: drift down the lane like frozen upgrades, weaving side to side (Corne: "move from side to side
## slowly... now all of a sudden you need to concentrate on sideways movement as well"). Touch one and its
## debuff runs on the player; shoot it to 0 hp first and it is destroyed harmlessly. Rows: data/traps.tsv.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Rng = preload("res://scripts/sim/rng.gd")
const Events = preload("res://scripts/sim/events.gd")
const ExactMath = preload("res://scripts/sim/exact_math.gd")


class Trap:
	extends RefCounted
	var serial := 0
	var active := false
	var trap_id := ""
	var x := 0.0
	var z := 0.0
	var prev_x := 0.0
	var prev_z := 0.0
	var hp := 0
	var centre_x := 0.0   ## the weave swings around this
	var phase := 0.0      ## radians


var pool: Array[Trap] = []
var exhausted_count := 0

var _rules: Rules
var _log: GLog
var _rng: Rng
var _next_serial := 1


func _init(rules: Rules, rng: Rng, logger: GLog) -> void:
	_rules = rules
	_rng = rng
	_log = logger
	for i in int(rules.t("trap_pool")):
		pool.append(Trap.new())


## trap_id "" = roll from traps.tsv. Returns false when every slot is busy.
func spawn(trap_id: String, emit: Callable) -> bool:
	var t := _inactive()
	if t == null:
		exhausted_count += 1
		_log.info("traps", "pool_full", {"pool": pool.size()})
		return false
	var row := _roll() if trap_id == "" else row_for(trap_id)
	var amp := _rules.t("trap_sway_amplitude")
	var half := maxf(0.0, _rules.t("road_width") / 2.0 - _rules.t("enemy_road_margin") - amp)
	t.serial = _next_serial
	_next_serial += 1
	t.active = true
	t.trap_id = row["id"]
	t.centre_x = _rng.range_float(-half, half)
	t.phase = _rng.next_float() * TAU
	t.x = t.centre_x + amp * ExactMath.wave(t.phase)
	t.z = _rules.t("enemy_spawn_distance") + _rng.next_float() * _rules.t("enemy_spawn_jitter")
	t.prev_x = t.x
	t.prev_z = t.z
	t.hp = int(_rules.t("trap_hp"))
	_log.info("traps", "spawned", {"serial": t.serial, "trap": t.trap_id, "x": t.x, "z": t.z})
	emit.call(Events.Kind.TRAP_SPAWNED, {"serial": t.serial, "trap": t.trap_id, "x": t.x, "z": t.z})
	return true


func update(dt: float, emit: Callable) -> void:
	var speed := _rules.t("upgrade_speed")
	var despawn := _rules.t("upgrade_despawn_z")
	var amp := _rules.t("trap_sway_amplitude")
	var w := _rules.t("trap_sway_speed")
	for t in pool:
		if not t.active:
			continue
		t.prev_x = t.x
		t.prev_z = t.z
		t.z -= speed * dt
		t.phase += w * dt
		t.x = t.centre_x + amp * ExactMath.wave(t.phase)
		if t.z < despawn:
			t.active = false
			_log.info("traps", "expired", {"serial": t.serial, "trap": t.trap_id})
			emit.call(Events.Kind.TRAP_EXPIRED, {"serial": t.serial, "trap": t.trap_id})


## Returns true when this hit destroyed the trap.
func hit(t: Trap, amount: int) -> bool:
	t.hp = maxi(0, t.hp - amount)
	if t.hp == 0:
		t.active = false
		return true
	return false


func row_for(id: String) -> Dictionary:
	for row in _rules.traps:
		if row["id"] == id:
			return row
	assert(false, "unknown trap " + id)
	return _rules.traps[0]


func _roll() -> Dictionary:
	var roll := _rng.range_int(0, 99)
	var cumulative := 0
	for row in _rules.traps:
		cumulative += row["weight"]
		if roll < cumulative:
			return row
	return _rules.traps[0]


func _inactive() -> Trap:
	for t in pool:
		if not t.active:
			return t
	return null
