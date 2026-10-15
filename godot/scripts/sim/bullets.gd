extends RefCounted
## Bullet pool. Source: src/systems/BulletManager.ts, src/entities/Bullet.ts.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")


class Bullet:
	extends RefCounted
	var serial := 0
	var active := false
	var x := 0.0
	var z := 0.0
	var prev_x := 0.0
	var prev_z := 0.0
	var vx := 0.0
	var vz := 0.0
	var start_z := 0.0
	var damage := 1
	var penetration := 1
	var splash_radius := 0.0
	var max_range := 0.0
	var weapon_id := ""
	## Targets this bullet already hit, kept across steps so a piercing bullet never hits the same one twice.
	var hit := {}
	var detonates := false


var pool: Array[Bullet] = []
var exhausted_count := 0

var _rules: Rules
var _log: GLog
var _next_serial := 1


func _init(rules: Rules, logger: GLog) -> void:
	_rules = rules
	_log = logger
	for i in int(rules.t("bullet_pool")):
		pool.append(Bullet.new())


## Fires one shot of `weapon` from (x, z). Returns how many bullets left the muzzle.
## mods: the player's perk modifiers (extra_bullets, range_mult, bullet_speed_mult, pierce_add); {} = none.
func fire(x: float, z: float, weapon: Dictionary, damage: int, mods := {}) -> int:
	var extra := int(mods.get("extra_bullets", 0.0))
	var count: int = int(weapon["bullet_count"]) + extra
	# A single-shot weapon with Split Shot fans its bullets out a little; spread weapons keep their own fan.
	var spread: float = weapon["bullet_spread"] if int(weapon["bullet_count"]) > 1 else 0.8 * extra
	var fired := 0
	for i in count:
		var b := _inactive()
		if b == null:
			exhausted_count += 1
			if exhausted_count == 1:
				_log.warn("bullets", "pool_exhausted", {"pool": pool.size(), "weapon": weapon["id"], "wanted": count, "fired": fired})
			break
		var spread_offset := 0.0
		if count > 1:
			spread_offset = (float(i) / (count - 1) - 0.5) * spread
		b.serial = _next_serial
		_next_serial += 1
		b.active = true
		b.x = x
		b.z = z
		b.prev_x = x
		b.prev_z = z
		b.vx = spread_offset * _rules.t("bullet_spread_speed")
		b.vz = _rules.t("bullet_speed") * (1.0 + mods.get("bullet_speed_mult", 0.0))
		b.start_z = z
		b.damage = damage
		b.penetration = int(weapon["penetration"]) + int(mods.get("pierce_add", 0.0))
		b.splash_radius = weapon["splash_radius"]
		b.max_range = float(weapon["max_range"]) * (1.0 + mods.get("range_mult", 0.0))
		b.weapon_id = weapon["id"]
		b.detonates = bool(weapon.get("detonates", false))
		b.hit.clear()
		fired += 1
	return fired


## Bullets that ran out of range this step and explode (grenade, rocket); the sim splashes them after
## the bullet-vs-enemy pass. Cleared at the start of every update.
var detonations: Array[Bullet] = []


func update(dt: float) -> void:
	detonations.clear()
	var despawn_z := _rules.t("bullet_despawn_z")
	for b in pool:
		if not b.active:
			continue
		b.prev_x = b.x
		b.prev_z = b.z
		b.x += b.vx * dt
		b.z += b.vz * dt
		if b.z - b.start_z > b.max_range or b.z > despawn_z:
			b.active = false
			if b.detonates:
				detonations.append(b)


## Penetration used up -> bullet gone. Returns true when the bullet is spent.
func spend(b: Bullet) -> bool:
	b.penetration -= 1
	if b.penetration <= 0:
		b.active = false
		return true
	return false


func active_count() -> int:
	var n := 0
	for b in pool:
		if b.active:
			n += 1
	return n


func _inactive() -> Bullet:
	for b in pool:
		if not b.active:
			return b
	return null
