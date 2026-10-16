extends RefCounted
## The player: lateral position, health, armour, guns and timed buffs. Source: src/entities/Player.ts.
## Guns (16 Oct, plan 2026-10-16-gun-loadout): up to gun_slots guns, all firing on their own timers; a gun you
## already hold levels up instead of replacing anything; a new gun with every slot full replaces the weakest.

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


class Gun:
	extends RefCounted
	var id := ""
	var level := 1
	var fire_timer := 0.0
	var damage_carry := 0.0  ## fraction of a damage point owed to its next shot (shot_damage)


var guns: Array[Gun] = []
## The gun in your hand: the one last added or levelled (the view draws it; the others float at the shoulders).
var weapon_id := Rules.DEFAULT_WEAPON
## Over every gun: reading gives the first gun's, writing sets all (tests switch firing off with -1e9).
var fire_timer: float:
	get:
		return guns[0].fire_timer if not guns.is_empty() else 0.0
	set(v):
		for g in guns:
			g.fire_timer = v
var damage_carry: float:
	get:
		return guns[0].damage_carry if not guns.is_empty() else 0.0
	set(v):
		for g in guns:
			g.damage_carry = v
var frenzy_timer := 0.0
var speed_timer := 0.0
var trap_left := {}  ## trap id -> seconds its effect still runs (traps.tsv); insertion-ordered, so deterministic
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
	guns.append(_new_gun(Rules.DEFAULT_WEAPON))


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
	for g in guns:
		g.fire_timer += dt
	if frenzy_timer > 0.0:
		frenzy_timer -= dt
	if speed_timer > 0.0:
		speed_timer -= dt
	if not trap_left.is_empty():
		for id in trap_left.keys():
			trap_left[id] -= dt
			if trap_left[id] <= 0.0:
				trap_left.erase(id)


func weapon() -> Dictionary:
	return _rules.weapons[weapon_id]


## Fires gun number slot when its timer has reached the interval; the timer then resets to 0 (Babylon parity: the rate
## is quantised to whole steps, see weapons.tsv).
func try_fire(slot := 0) -> bool:
	var g := guns[slot]
	var rate: float = _rules.weapons[g.id]["fire_rate"]
	if speed_timer > 0.0:
		rate *= _rules.t("speed_buff_rate_mult")
	rate *= 1.0 + mods["fire_rate_mult"]
	for id in trap_left:
		var row: Dictionary = _rules.trap_by_id[id]
		if row["effect"] == "fire_rate_mult":
			rate *= row["amount"]
	if g.fire_timer >= 1.0 / rate:
		g.fire_timer = 0.0
		return true
	return false


func shot_damage(slot := 0) -> int:
	var g := guns[slot]
	var dmg: float = float(_rules.weapons[g.id]["damage"]) * (1.0 + mods["damage_mult"]) * level_mult(g.level)
	if frenzy_timer > 0.0:
		dmg *= _rules.t("frenzy_damage_mult")
	# Was ceil: one +8% pick made every 1-damage gun do 2 (2x) and stacks 2-5 did nothing (16 Oct critique).
	# Whole points per shot, the fraction carried: +8% on a pistol = a 2 every ~12th shot, 1.08 on average.
	var total := dmg + g.damage_carry
	var out := int(floor(total + 1e-9))
	g.damage_carry = total - out
	return out


func level_mult(level: int) -> float:
	return 1.0 + _rules.t("gun_level_damage") * (level - 1)


## How strong a gun is, for choosing which one a new gun replaces: single-target damage per second x level.
func gun_power(g: Gun) -> float:
	var w: Dictionary = _rules.weapons[g.id]
	return float(w["damage"]) * float(w["bullet_count"]) * float(w["fire_rate"]) * level_mult(g.level)


## Picks up the gun with this id. Returns {action: levelled|maxed|added|replaced, slot, gun, level, replaced}.
## (evolve() returns action evolved, replaced = the base gun.)
func add_gun(id: String) -> Dictionary:
	for i in guns.size():
		if guns[i].id == id or _rules.base_of.get(guns[i].id, "") == id:  # its evolved form counts as holding it
			weapon_id = id
			if guns[i].level >= int(_rules.t("gun_max_level")):
				return _gun_result("maxed", i, "")
			guns[i].level += 1
			return _gun_result("levelled", i, "")
	if guns.size() < int(_rules.t("gun_slots")):
		guns.append(_new_gun(id))
		weapon_id = id
		return _gun_result("added", guns.size() - 1, "")
	var weakest := 0
	for i in range(1, guns.size()):
		if gun_power(guns[i]) < gun_power(guns[weakest]):
			weakest = i
	var old := guns[weakest].id
	guns[weakest] = _new_gun(id)
	weapon_id = id
	return _gun_result("replaced", weakest, old)


## Guns that may evolve now: at gun_max_level, with a stack of their perk. Slot order.
func evolvable() -> Array[int]:
	var out: Array[int] = []
	for i in guns.size():
		var row: Dictionary = _rules.evolution_of.get(guns[i].id, {})
		if not row.is_empty() and guns[i].level >= int(_rules.t("gun_max_level")) and perk_stacks.get(row["perk"], 0) > 0:
			out.append(i)
	return out


func evolve(slot: int) -> Dictionary:
	var row: Dictionary = _rules.evolution_of[guns[slot].id]
	var old := guns[slot].id
	guns[slot].id = row["id"]
	weapon_id = row["id"]
	return _gun_result("evolved", slot, old)


func _gun_result(action: String, slot: int, replaced: String) -> Dictionary:
	var r := {"action": action, "slot": slot, "gun": guns[slot].id, "level": guns[slot].level, "replaced": replaced}
	_log.info("player", "gun", r)
	return r


func _new_gun(id: String) -> Gun:
	var g := Gun.new()
	g.id = id
	return g


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
	perk_stacks[row["id"]] = perk_stacks.get(row["id"], 0) + 1
	_add_stat(stat, float(row["amount"]))
	if row.get("cost_stat", "-") != "-":  # the price of a risk perk (Glass Cannon: -2 max HP)
		_add_stat(row["cost_stat"], float(row["cost_amount"]))
	_log.info("player", "perk", {"perk": row["id"], "stacks": perk_stacks[row["id"]], "stat": stat, "total": mods[stat]})


func _add_stat(stat: String, amount: float) -> void:
	mods[stat] += amount
	match stat:
		"max_hp_add":
			max_hp = maxi(1, max_hp + int(amount))
			hp = clampi(hp + maxi(0, int(amount)), 1 if hp > 0 else 0, max_hp)
		"armor_add":
			armor = maxi(0, armor + int(amount))


## The max-HP pickup's cap; Vitality perks raise it.
func max_hp_cap() -> int:
	return int(_rules.t("max_hp")) + int(mods["max_hp_add"])


func add_max_hp(amount: int) -> void:
	max_hp = mini(max_hp_cap(), max_hp + amount)
	hp = mini(max_hp, hp + amount)


## Holds only this gun, at level 1 (debug --weapon, replays, bench, tests).
func set_weapon(id: String) -> void:
	guns.clear()
	guns.append(_new_gun(id))
	weapon_id = id
	_log.info("player", "weapon", {"weapon": id})


## A trap's effect (traps.tsv row). Touching the same trap kind again restarts its timer, it does not stack.
func apply_trap(row: Dictionary) -> void:
	trap_left[row["id"]] = row["seconds"]


## Crit chance after debuffs (Jinx trap = 0).
func crit_chance() -> float:
	for id in trap_left:
		if _rules.trap_by_id[id]["effect"] == "no_crit":
			return 0.0
	return mods["crit_chance"]


func start_frenzy(seconds: float) -> void:
	frenzy_timer = seconds


func start_speed_buff(seconds: float) -> void:
	speed_timer = seconds


func alive() -> bool:
	return hp > 0
