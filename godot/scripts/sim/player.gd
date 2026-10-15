extends RefCounted
## The player: lateral position, health, armour, weapon and timed buffs. Source: src/entities/Player.ts.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")

var x := 0.0
## x at the start of the current step, so the view can draw smoothly between steps.
var prev_x := 0.0
var z := 0.0
var hp := 0
var max_hp := 0
var armor := 0
var weapon_id := Rules.DEFAULT_WEAPON
var fire_timer := 0.0
var frenzy_timer := 0.0
var speed_timer := 0.0

var _rules: Rules
var _log: GLog
var _half_road := 0.0


func _init(rules: Rules, logger: GLog) -> void:
	_rules = rules
	_log = logger
	_half_road = rules.t("road_width") / 2.0 - rules.t("player_road_margin")
	x = 0.0
	z = rules.t("player_z")
	hp = int(rules.t("initial_hp"))
	max_hp = hp


## axis in [-1, 1]; anything else (incl. NaN) is clamped or treated as 0 by the caller.
func move(axis: float, dt: float) -> void:
	if axis == 0.0:
		return
	x = clampf(x + axis * _rules.t("player_move_speed") * dt, -_half_road, _half_road)


func update_timers(dt: float) -> void:
	fire_timer += dt
	if frenzy_timer > 0.0:
		frenzy_timer -= dt
	if speed_timer > 0.0:
		speed_timer -= dt


func weapon() -> Dictionary:
	return _rules.weapons[weapon_id]


## Fires when the timer has reached the interval; the timer then resets to 0 (Babylon parity: the rate is
## quantised to whole steps, see weapons.tsv).
func try_fire() -> bool:
	var rate: float = weapon()["fire_rate"]
	if speed_timer > 0.0:
		rate *= _rules.t("speed_buff_rate_mult")
	if fire_timer >= 1.0 / rate:
		fire_timer = 0.0
		return true
	return false


func shot_damage() -> int:
	var base: int = weapon()["damage"]
	if frenzy_timer > 0.0:
		return int(ceil(base * _rules.t("frenzy_damage_mult")))
	return base


## Armour absorbs first. Returns {"absorbed": int, "taken": int}.
func take_damage(amount: int) -> Dictionary:
	var absorbed := mini(armor, amount)
	armor -= absorbed
	var taken := amount - absorbed
	hp = maxi(0, hp - taken)
	return {"absorbed": absorbed, "taken": taken}


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


func add_armor(amount: int) -> void:
	armor += amount


func add_max_hp(amount: int) -> void:
	max_hp = mini(int(_rules.t("max_hp")), max_hp + amount)
	hp = mini(max_hp, hp + amount)


func set_weapon(id: String) -> void:
	weapon_id = id
	fire_timer = 0.0
	_log.info("player", "weapon", {"weapon": id})


func start_frenzy(seconds: float) -> void:
	frenzy_timer = seconds


func start_speed_buff(seconds: float) -> void:
	speed_timer = seconds


func alive() -> bool:
	return hp > 0
