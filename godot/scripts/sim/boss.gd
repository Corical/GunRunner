extends RefCounted
## The boss: appears every boss_interval metres, walks at the player, speeds up as it loses health.
## Source: src/entities/Boss.ts. Port changes (plan D13): it steers toward the player's x, and if the
## player dodges it completely it comes round again from the far end instead of walking off forever
## (which left spawning paused for the rest of the run).

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")

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

var _rules: Rules
var _log: GLog


func _init(rules: Rules, logger: GLog) -> void:
	_rules = rules
	_log = logger


func activate(new_wave: int) -> void:
	wave = new_wave
	serial = -new_wave  # unique per fight, never collides with enemy serials (> 0) in a bullet's hit set
	max_hp = int(_rules.t("boss_base_hp") + _rules.t("boss_hp_per_wave") * new_wave)
	hp = max_hp
	x = 0.0
	z = _rules.t("boss_spawn_z")
	prev_x = x
	prev_z = z
	speed = _rules.t("boss_speed_full_hp")
	active = true
	_log.info("boss", "started", {"wave": wave, "hp": hp})


## Moves, then recomputes speed from health (Babylon order: this step used last step's speed).
func update(dt: float, player_x: float) -> void:
	prev_x = x
	prev_z = z
	z -= speed * dt
	var step := _rules.t("boss_steer_speed") * dt
	x += clampf(player_x - x, -step, step)
	speed = _rules.t("boss_speed_full_hp") + (1.0 - float(hp) / max_hp) * _rules.t("boss_speed_bonus_at_zero_hp")


## 0 = no contact, 1 = touching the player, 2 = passed the player entirely.
func contact(player_x: float, player_z: float) -> int:
	var reach := _rules.t("boss_contact_player_radius") + _rules.t("boss_radius")
	var dz := z - player_z
	if dz <= -reach:
		return 2
	if dz < reach and absf(x - player_x) < _rules.t("boss_contact_dx"):
		return 1
	return 0


func push_back() -> void:
	z += _rules.t("boss_pushback")


func wrap_around() -> void:
	z = _rules.t("boss_spawn_z")
	prev_z = z
	_log.info("boss", "wrapped", {"wave": wave, "hp": hp})


## Returns true when this hit defeated the boss.
func take_damage(amount: int) -> bool:
	hp = maxi(0, hp - amount)
	if hp == 0:
		active = false
		return true
	return false
