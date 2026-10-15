extends RefCounted
## Frozen upgrades: rewards locked in ice that drift toward the player. Shoot the ice off, then touch the
## reward to collect it. Source: src/systems/FrozenUpgradeManager.ts, src/entities/FrozenUpgrade.ts.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Rng = preload("res://scripts/sim/rng.gd")
const Events = preload("res://scripts/sim/events.gd")


class Upgrade:
	extends RefCounted
	var serial := 0
	var active := false
	var reward_id := ""
	var kind := ""
	var x := 0.0
	var z := 0.0
	var prev_x := 0.0
	var prev_z := 0.0
	var ice_hp := 0
	var thawed := false
	var centre_x := 0.0  ## the drift swings around this
	var phase := 0.0


var pool: Array[Upgrade] = []
var exhausted_count := 0

var _rules: Rules
var _log: GLog
var _rng: Rng
var _next_serial := 1


func _init(rules: Rules, rng: Rng, logger: GLog) -> void:
	_rules = rules
	_rng = rng
	_log = logger
	for i in int(rules.t("upgrade_pool")):
		pool.append(Upgrade.new())


## Spawns one upgrade; reward_id "" = roll from rewards.tsv. Returns false when every slot is busy.
func spawn(reward_id: String, emit: Callable) -> bool:
	var u := _inactive()
	if u == null:
		exhausted_count += 1
		_log.info("upgrades", "pool_full", {"pool": pool.size(), "wanted": reward_id if reward_id != "" else "roll"})
		return false
	var reward := _roll() if reward_id == "" else _reward_row(reward_id)
	var amp := _rules.t("upgrade_sway_amplitude")
	var half := maxf(0.0, _rules.t("road_width") / 2.0 - _rules.t("enemy_road_margin") - amp)
	u.serial = _next_serial
	_next_serial += 1
	u.active = true
	u.reward_id = reward["id"]
	u.kind = reward["kind"]
	u.centre_x = _rng.range_float(-half, half)
	u.phase = _rng.next_float() * TAU
	u.x = u.centre_x + amp * sin(u.phase)
	u.z = _rules.t("enemy_spawn_distance") + _rng.next_float() * _rules.t("enemy_spawn_jitter")
	u.prev_x = u.x
	u.prev_z = u.z
	u.ice_hp = int(_rules.t("upgrade_ice_hp"))
	u.thawed = false
	_log.info("upgrades", "spawned", {"serial": u.serial, "reward": u.reward_id, "x": u.x, "z": u.z})
	emit.call(Events.Kind.UPGRADE_SPAWNED, {"serial": u.serial, "reward": u.reward_id, "reward_kind": u.kind, "x": u.x, "z": u.z})
	return true


func update(dt: float, emit: Callable) -> void:
	var speed := _rules.t("upgrade_speed")
	var despawn := _rules.t("upgrade_despawn_z")
	for u in pool:
		if not u.active:
			continue
		u.prev_x = u.x
		u.prev_z = u.z
		u.z -= speed * dt
		u.phase += _rules.t("upgrade_sway_speed") * dt
		u.x = u.centre_x + _rules.t("upgrade_sway_amplitude") * sin(u.phase)
		if u.z < despawn:
			u.active = false
			_log.info("upgrades", "expired", {"serial": u.serial, "reward": u.reward_id, "thawed": u.thawed})
			emit.call(Events.Kind.UPGRADE_EXPIRED, {"serial": u.serial, "reward": u.reward_id, "thawed": u.thawed})


## Returns true when this hit shattered the ice.
func hit_ice(u: Upgrade, amount: int) -> bool:
	if u.thawed:
		return false
	u.ice_hp = maxi(0, u.ice_hp - amount)
	if u.ice_hp == 0:
		u.thawed = true
		return true
	return false


func _roll() -> Dictionary:
	var roll := _rng.range_int(0, 99)
	var cumulative := 0
	for row in _rules.rewards:
		cumulative += row["weight"]
		if roll < cumulative:
			return row
	return _rules.rewards[0]


func _reward_row(id: String) -> Dictionary:
	for row in _rules.rewards:
		if row["id"] == id:
			return row
	assert(false, "unknown reward " + id)
	return _rules.rewards[0]


func active_count() -> int:
	var n := 0
	for u in pool:
		if u.active:
			n += 1
	return n


func _inactive() -> Upgrade:
	for u in pool:
		if not u.active:
			return u
	return null
