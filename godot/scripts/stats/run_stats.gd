extends RefCounted
## Turns a run's sim events into numbers and a readable timeline. Pure: fed after every sim step, by the
## windowed game (via replay), the headless batch and tests alike.
##
## Per weapon: seconds held, kills, damage dealt, kills per minute while held (the "is the laser too strong"
## number). Per enemy type: kills. Damage taken: by attacker type. Pickups, boss fights, and a timeline.

const Events = preload("res://scripts/sim/events.gd")
const K = Events.Kind
const STEP := 1.0 / 60.0
const TIMELINE_MAX := 2000

var ticks_by_weapon := {}
var kills_by_weapon := {}
var damage_by_weapon := {}
var kills_by_enemy := {}
var hurt_by := {}        ## attacker type -> hp + armour lost
var hits_taken_by := {}  ## attacker type -> number of hits
var pickups := {}
var bosses: Array[Dictionary] = []
var timeline: PackedStringArray = []
var ticks := 0


## Call once after each sim step.
func step(sim: Object) -> void:
	ticks = sim.tick
	for g in sim.player.guns:  # every gun carried counts as held (they all fire)
		ticks_by_weapon[g.id] = ticks_by_weapon.get(g.id, 0) + 1
	for ev in sim.events:
		match ev["kind"]:
			K.ENEMY_HIT:
				_add(damage_by_weapon, ev["weapon"], ev["amount"])
			K.ENEMY_KILLED:
				_add(damage_by_weapon, ev["weapon"], ev["amount"])
				_add(kills_by_weapon, ev["weapon"], 1)
				_add(kills_by_enemy, ev["enemy"], 1)
			K.PLAYER_HURT:
				_add(hurt_by, ev["by"], ev["amount"])
				_add(hits_taken_by, ev["by"], 1)
				_line(sim, "HURT -%d by %s from x=%.1f, you at x=%.1f holding %s -> hp %d armour %d" % [
					ev["amount"], ev["by"], ev["by_x"], ev["player_x"], ev["weapon"], ev["hp"], ev["armor"]])
			K.PICKUP:
				_add(pickups, ev["reward"], 1)
				_line(sim, "PICKUP %s at x=%.1f" % [ev["reward"], ev["x"]])
			K.BOSS_STARTED:
				bosses.append({"wave": ev["wave"], "start": sim.tick, "end": -1})
				_line(sim, "BOSS %d starts (%d hp)" % [ev["wave"], ev["hp"]])
			K.BOSS_DEFEATED:
				if not bosses.is_empty():
					bosses[-1]["end"] = sim.tick
				_line(sim, "BOSS %d defeated" % ev["wave"])
			K.BOSS_WRAPPED:
				_line(sim, "BOSS dodged, comes round again")
			K.GAME_OVER:
				_line(sim, "GAME OVER score %d, %d m, %d kills" % [ev["score"], int(ev["distance"]), ev["kills"]])


## One row per weapon ever held, sorted by kills per minute held (highest first).
func weapon_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var weapons := {}
	for k in ticks_by_weapon:
		weapons[k] = true
	for k in kills_by_weapon:
		weapons[k] = true
	for w in weapons:
		var held_s: float = ticks_by_weapon.get(w, 0) * STEP
		rows.append({
			"weapon": w, "held_s": held_s, "kills": kills_by_weapon.get(w, 0), "damage": damage_by_weapon.get(w, 0),
			"kills_per_min": kills_by_weapon.get(w, 0) * 60.0 / held_s if held_s > 0.0 else 0.0,
			"damage_per_s": damage_by_weapon.get(w, 0) / held_s if held_s > 0.0 else 0.0,
		})
	rows.sort_custom(func(a, b): return a["kills_per_min"] > b["kills_per_min"])
	return rows


## Adds another run's numbers into this one (batch totals).
func merge(other: Object) -> void:
	ticks += other.ticks
	for pair in [[ticks_by_weapon, other.ticks_by_weapon], [kills_by_weapon, other.kills_by_weapon],
			[damage_by_weapon, other.damage_by_weapon], [kills_by_enemy, other.kills_by_enemy],
			[hurt_by, other.hurt_by], [hits_taken_by, other.hits_taken_by], [pickups, other.pickups]]:
		for k in pair[1]:
			_add(pair[0], k, pair[1][k])


func _line(sim: Object, text: String) -> void:
	if timeline.size() < TIMELINE_MAX:
		timeline.append("%7.2fs %5dm  %s" % [sim.tick * STEP, int(sim.distance), text])


static func _add(d: Dictionary, key: Variant, amount: Variant) -> void:
	d[key] = d.get(key, 0) + amount
