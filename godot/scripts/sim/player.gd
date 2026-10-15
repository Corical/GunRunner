extends RefCounted
## The player: lateral position, health, armour, weapon and timed buffs. Source: src/entities/Player.ts.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")

var x := 0.0
## x at the start of the current step, so the view can draw smoothly between steps.
var prev_x := 0.0
## Sideways speed (units/s); the view leans the player by it.
var vx := 0.0
var z := 0.0
var hp := 0
var max_hp := 0
var armor := 0
var weapon_id := Rules.DEFAULT_WEAPON
var fire_timer := 0.0
var frenzy_timer := 0.0
var speed_timer := 0.0
var jam_timer := 0.0     ## trap: fire rate x jam_mult while > 0
var jam_mult := 1.0
var jinx_timer := 0.0    ## trap: no crits while > 0
## Level-up perk modifiers, all start at 0 (Rules.PERK_STATS); perk id -> stacks taken.
var mods := {}
var perk_stacks := {}

var _rules: Rules
var _log: GLog
var _half_road := 0.0


func _init(rules: Rules, logger: GLog) -> void:
	_rules = rules
	_log = logger
	_half_road = rules.t("road_width") / 2.0 - rules.t("player_road_margin")
	for stat in Rules.PERK_STATS:
		mods[stat] = 0.0
	x = 0.0
	z = rules.t("player_z")
	hp = int(rules.t("initial_hp"))
	max_hp = hp


## Steering, with acceleration so movement eases in and out (Babylon went 0 -> full speed in one frame).
## Keys: axis in [-1, 1] sets the wanted speed. Drag: target_x (NaN = not dragging) sets a point to move to;
## wanted speed is proportional to the distance, so it slows as it arrives and does not overshoot.
func move(axis: float, target_x: float, dt: float) -> void:
	var wanted := 0.0
	if not is_nan(target_x):
		var max_drag: float = _rules.t("player_drag_max_speed") * (1.0 + mods["move_speed_mult"])
		wanted = clampf((clampf(target_x, -_half_road, _half_road) - x) * _rules.t("player_drag_gain"), -max_drag, max_drag)
	else:
		wanted = axis * _rules.t("player_move_speed") * (1.0 + mods["move_speed_mult"])
	var dragging := not is_nan(target_x)
	if dragging and signf(wanted) == signf(vx) and absf(wanted) < absf(vx):
		# Dragging: speeding up is limited by acceleration, slowing down is not. Wanted speed shrinks with the
		# distance, so the player closes in exponentially and can never overshoot the finger.
		vx = wanted
	elif dragging and wanted == 0.0:
		vx = 0.0
	else:
		vx = move_toward(vx, wanted, _rules.t("player_accel") * dt)
	if dragging:
		# Never step past the target in one step; when within 0.0001 just sit on it (an exponential approach
		# otherwise never quite arrives and leaves a tiny speed forever).
		var to_target := clampf(target_x, -_half_road, _half_road) - x
		if absf(to_target) < 1e-4:
			x += to_target
			vx = 0.0
			return
		if absf(vx * dt) > absf(to_target) and signf(vx) == signf(to_target):
			vx = to_target / dt
	x += vx * dt
	if x <= -_half_road or x >= _half_road:
		x = clampf(x, -_half_road, _half_road)
		vx = 0.0


func update_timers(dt: float) -> void:
	fire_timer += dt
	if frenzy_timer > 0.0:
		frenzy_timer -= dt
	if speed_timer > 0.0:
		speed_timer -= dt
	if jam_timer > 0.0:
		jam_timer -= dt
	if jinx_timer > 0.0:
		jinx_timer -= dt


func weapon() -> Dictionary:
	return _rules.weapons[weapon_id]


## Fires when the timer has reached the interval; the timer then resets to 0 (Babylon parity: the rate is
## quantised to whole steps, see weapons.tsv).
func try_fire() -> bool:
	var rate: float = weapon()["fire_rate"]
	if speed_timer > 0.0:
		rate *= _rules.t("speed_buff_rate_mult")
	rate *= 1.0 + mods["fire_rate_mult"]
	if jam_timer > 0.0:
		rate *= jam_mult
	if fire_timer >= 1.0 / rate:
		fire_timer = 0.0
		return true
	return false


func shot_damage() -> int:
	var dmg: float = float(weapon()["damage"]) * (1.0 + mods["damage_mult"])
	if frenzy_timer > 0.0:
		dmg *= _rules.t("frenzy_damage_mult")
	return int(ceil(dmg - 1e-9))


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


## Takes one stack of a perk (row from perks.tsv). Immediate effects (hp, armour) happen here.
func apply_perk(row: Dictionary) -> void:
	var stat: String = row["stat"]
	mods[stat] += float(row["amount"])
	perk_stacks[row["id"]] = perk_stacks.get(row["id"], 0) + 1
	match stat:
		"max_hp_add":
			max_hp += int(row["amount"])
			hp = mini(max_hp, hp + int(row["amount"]))
		"armor_add":
			armor += int(row["amount"])
	_log.info("player", "perk", {"perk": row["id"], "stacks": perk_stacks[row["id"]], "stat": stat, "total": mods[stat]})


## The max-HP pickup's cap; Vitality perks raise it.
func max_hp_cap() -> int:
	return int(_rules.t("max_hp")) + int(mods["max_hp_add"])


func add_max_hp(amount: int) -> void:
	max_hp = mini(max_hp_cap(), max_hp + amount)
	hp = mini(max_hp, hp + amount)


func set_weapon(id: String) -> void:
	weapon_id = id
	fire_timer = 0.0
	_log.info("player", "weapon", {"weapon": id})


## A trap's effect (traps.tsv row). Touching the same trap kind again restarts its timer, it does not stack.
func apply_trap(row: Dictionary) -> void:
	match row["effect"]:
		"fire_rate_mult":
			jam_timer = row["seconds"]
			jam_mult = row["amount"]
		"no_crit":
			jinx_timer = row["seconds"]


## Crit chance after debuffs (Jinx trap = 0).
func crit_chance() -> float:
	return 0.0 if jinx_timer > 0.0 else mods["crit_chance"]


func start_frenzy(seconds: float) -> void:
	frenzy_timer = seconds


func start_speed_buff(seconds: float) -> void:
	speed_timer = seconds


func alive() -> bool:
	return hp > 0
