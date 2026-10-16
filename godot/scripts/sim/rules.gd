extends RefCounted
## Validated game rules built from already-parsed table rows (no file access here; see data/rules_loader.gd).
## Cross-checks every reference between tables. A Rules with errors must not be used to run a game.

const TABLES := {
	"weapons": ["id", "name", "fire_rate", "damage", "bullet_count", "bullet_spread", "bullet_size", "bullet_color", "max_range", "penetration", "splash_radius", "detonates", "chain_arcs"],
	"enemies": ["id", "name", "hp", "speed", "color", "size", "score", "switches_lanes", "behaviour"],
	"towers": ["id", "name", "color", "duration", "radius", "burn_damage", "slow_multiplier", "poison_duration", "poison_damage"],
	"effectiveness": ["id", "weapon", "enemy", "multiplier"],
	"evolutions": ["id", "base", "perk"],
	"rewards": ["id", "kind", "weight", "label", "color"],
	"spawns": ["id", "start"],
	"tuning": ["id", "value", "source"],
	"perks": ["id", "name", "desc", "stat", "amount", "max_stacks", "weight"],
	"weapon_looks": ["id", "kick_ms", "kick_amp", "muzzle_color", "muzzle_sparks", "muzzle_smoke", "bullet_stretch",
		"bullet_arc", "bullet_grow", "smoke_trail", "model_length", "model_radius", "model", "model_scale", "model_yaw"],
	"traps": ["id", "name", "effect", "amount", "seconds", "weight", "label", "color"],
	"character_looks": ["id", "model", "scale", "yaw", "anim"],
	"bosses": ["id", "name", "color", "hp_mult", "speed", "steer", "contact_dx", "contact_damage", "hold_z", "hold_seconds", "strafe",
		"summon_every", "summon_count", "summon_enemy", "shoot_every", "shot_speed", "shot_damage"],
}

const REWARD_KINDS := ["weapon", "tower", "heal", "armor", "maxhp", "frenzy", "speed"]
const DEFAULT_WEAPON := "pistol"

## Every tuning key the sim reads. A key in tuning.tsv that is not here is dead data and an error.
const TUNING_KEYS := [
	"game_speed", "road_width", "initial_hp", "max_hp", "player_z", "player_move_speed", "player_road_margin",
	"player_accel", "player_drag_gain", "player_drag_max_speed", "enemy_hp_per_100m", "xp_base", "xp_growth",
	"muzzle_z_offset", "enemy_speed", "enemy_spawn_distance", "enemy_spawn_jitter", "enemy_despawn_z", "enemy_pool",
	"enemy_road_margin", "enemy_radius_per_size", "spawn_interval", "spawn_interval_min", "spawn_interval_decay",
	"wave_size_max", "wave_size_metres", "spawn_min_gap", "spawn_tries", "flanker_first_min", "flanker_first_extra",
	"flanker_retarget_min", "flanker_retarget_extra", "flanker_lateral_speed", "flanker_lock_distance", "burn_tick", "poison_tick",
	"bullet_speed", "bullet_despawn_z", "bullet_pool", "bullet_spread_speed", "bullet_hit_radius",
	"splash_max_victims", "enemy_hit_player_radius", "upgrade_spawn_per_second", "upgrade_ice_hp", "upgrade_speed",
	"upgrade_pool", "upgrade_despawn_z", "upgrade_radius", "pickup_dx", "pickup_dz", "heal_amount", "armor_amount",
	"maxhp_amount", "frenzy_seconds", "frenzy_damage_mult", "speed_buff_seconds", "speed_buff_rate_mult", "tower_z",
	"tower_pool", "boss_interval", "boss_base_hp", "boss_hp_per_wave", "boss_spawn_z", "boss_radius",
	"boss_speed_bonus_at_zero_hp", "boss_contact_player_radius", "boss_pushback", "boss_score_per_wave",
	"boss_shot_radius", "boss_shot_pool",
	"trap_spawn_per_second", "trap_hp", "trap_pool", "trap_sway_amplitude", "trap_sway_speed", "upgrade_sway_amplitude",
	"upgrade_sway_speed", "upgrade_pair_chance", "drop_min_gap", "first_weapon_seconds", "first_weapon_ice_hp", "gun_slots", "gun_max_level", "gun_level_damage", "gun_slot_spacing", "chain_range", "chain_falloff", "chain_min",
	"chain_arcs_per_level", "bomber_fuse", "bomber_blast_radius", "bomber_blast_damage", "bomber_enemy_damage",
	"healer_every", "healer_radius", "healer_amount", "split_count", "split_spacing", "shield_hp",
]
## Chances: must lie in 0..1.
const TUNING_PROBABILITY := ["upgrade_pair_chance"]

## Range checks for tuning (Fable review #6: xp_growth < 1 made xp_needed() round to 0 and the level-up loop never
## ended). Every key must be >= 0 unless listed in TUNING_NEGATIVE_OK; keys here need at least this value.
const TUNING_NEGATIVE_OK := ["player_z", "enemy_despawn_z", "upgrade_despawn_z"]
const TUNING_MIN := {
	"game_speed": 0.01, "road_width": 1.0, "initial_hp": 1.0, "max_hp": 1.0, "player_move_speed": 0.01,
	"enemy_speed": 0.01, "enemy_pool": 1.0, "enemy_radius_per_size": 0.01, "spawn_interval": 0.05,
	"spawn_interval_min": 0.05, "wave_size_max": 1.0, "wave_size_metres": 1.0, "spawn_tries": 1.0,
	"burn_tick": 0.05, "poison_tick": 0.05, "bullet_speed": 0.01, "bullet_pool": 1.0, "bullet_hit_radius": 0.01,
	"upgrade_ice_hp": 1.0, "upgrade_speed": 0.01, "upgrade_pool": 1.0, "upgrade_radius": 0.01, "tower_pool": 1.0,
	"boss_interval": 1.0, "boss_base_hp": 1.0, "boss_radius": 0.01, "boss_shot_radius": 0.01, "boss_shot_pool": 1.0, "xp_base": 1.0, "xp_growth": 1.0,
	"trap_hp": 1.0, "trap_pool": 1.0, "frenzy_damage_mult": 1.0, "speed_buff_rate_mult": 0.01,
}

var errors: PackedStringArray = []
var weapons := {}        ## id -> row
var enemies := {}        ## id -> row
var enemy_ids: PackedStringArray = []   ## table order (stable iteration)
var towers := {}         ## id -> row
var effectiveness := {}  ## "weapon|enemy" -> multiplier
var evolution_of := {}   ## base gun id -> evolutions.tsv row
var base_of := {}        ## evolved gun id -> the base gun id
var rewards: Array[Dictionary] = []     ## rows in roll order
var spawn_bands: Array[Dictionary] = [] ## {id, start, weights: Array of [enemy_id, weight]} ascending by start
var tuning := {}         ## id -> float
var perks: Array[Dictionary] = []  ## rows in table order (roll order)
var traps: Array[Dictionary] = []  ## rows in roll order
var trap_by_id := {}  ## id -> row
var bosses: Array = []  ## bosses.tsv rows in order; wave n fights bosses[(n - 1) % size]
var character_looks := {}  ## "player" / enemy id / boss id -> presentation row (the sim never reads it)


## Half the road an enemy may use, read from raw tuning rows (the bosses table is checked before tuning is built).
static func tuning_half_road(tables: Dictionary) -> float:
	var v := {"road_width": 0.0, "enemy_road_margin": 0.0}
	for r in tables.get("tuning", []):
		if v.has(r["id"]):
			v[r["id"]] = float(r["value"])
	return v["road_width"] / 2.0 - v["enemy_road_margin"]
var weapon_looks := {}  ## weapon id -> presentation row (weapon_looks.tsv; the sim never reads it)
const TRAP_EFFECTS := ["fire_rate_mult", "no_crit"]

## Player modifiers a perk may add to (player.gd reads each one).
const PERK_STATS := ["damage_mult", "fire_rate_mult", "range_mult", "pierce_add", "extra_bullets", "bullet_speed_mult",
	"max_hp_add", "armor_add", "move_speed_mult", "crit_chance", "tower_duration_mult", "pickup_mult"]


func ok() -> bool:
	return errors.is_empty()


## Tuning value. Keys are validated at build time, so a missing key here is a programming error.
func t(key: String) -> float:
	assert(tuning.has(key), "unknown tuning key " + key)
	return tuning[key]


func multiplier(weapon_id: String, enemy_id: String) -> float:
	var key := weapon_id + "|" + enemy_id
	if not effectiveness.has(key) and base_of.has(weapon_id):  # an evolved gun keeps its base's strengths
		key = base_of[weapon_id] + "|" + enemy_id
	return effectiveness.get(key, 1.0)


static func from_tables(tables: Dictionary) -> Object:
	var r := new()
	for name in TABLES:
		if not tables.has(name):
			r.errors.append("missing table '%s'" % name)
			continue
		var rows: Array = tables[name]
		if rows.is_empty():
			r.errors.append("table '%s' is empty" % name)
			continue
		for col in TABLES[name]:
			if not rows[0].has(col):
				r.errors.append("table '%s' missing column '%s'" % [name, col])
	if not r.errors.is_empty():
		return r
	r._build(tables)
	return r


func _build(tables: Dictionary) -> void:
	for row in tables["perks"]:
		perks.append(row)
		if not PERK_STATS.has(row["stat"]): errors.append("perk %s: unknown stat '%s'" % [row["id"], row["stat"]])
		if row["max_stacks"] < 1: errors.append("perk %s: max_stacks must be >= 1" % row["id"])
		if row["weight"] < 1: errors.append("perk %s: weight must be >= 1" % row["id"])
		if row["amount"] <= 0.0: errors.append("perk %s: amount must be > 0" % row["id"])
	var trap_total := 0
	for row in tables["traps"]:
		traps.append(row)
		trap_by_id[row["id"]] = row
		trap_total += row["weight"]
		if not TRAP_EFFECTS.has(row["effect"]): errors.append("trap %s: unknown effect '%s'" % [row["id"], row["effect"]])
		if row["seconds"] <= 0.0: errors.append("trap %s: seconds must be > 0" % row["id"])
		if row["weight"] <= 0: errors.append("trap %s: weight must be > 0" % row["id"])
		if row["effect"] == "fire_rate_mult" and (row["amount"] <= 0.0 or row["amount"] >= 1.0):
			errors.append("trap %s: fire_rate_mult amount must be between 0 and 1 (a trap slows, never speeds)" % row["id"])
	if trap_total != 100:
		errors.append("traps: weights sum to %d, must be 100" % trap_total)
	for row in tables["weapons"]:
		weapons[row["id"]] = row
		if row["fire_rate"] <= 0.0: errors.append("weapon %s: fire_rate must be > 0" % row["id"])
		if row["damage"] < 1: errors.append("weapon %s: damage must be >= 1" % row["id"])
		if row["bullet_count"] < 1: errors.append("weapon %s: bullet_count must be >= 1" % row["id"])
		if row["penetration"] < 1: errors.append("weapon %s: penetration must be >= 1" % row["id"])
		if row["max_range"] <= 0.0: errors.append("weapon %s: max_range must be > 0" % row["id"])
	for row in tables["weapon_looks"]:
		weapon_looks[row["id"]] = row
		if not weapons.has(row["id"]): errors.append("weapon_looks %s: no such weapon" % row["id"])
	for id in weapons:
		if not weapon_looks.has(id): errors.append("weapon %s: no row in weapon_looks.tsv" % id)
	if not weapons.has(DEFAULT_WEAPON):
		errors.append("weapons: default weapon '%s' missing" % DEFAULT_WEAPON)

	for row in tables["enemies"]:
		enemies[row["id"]] = row
		enemy_ids.append(row["id"])
		if row["hp"] < 1: errors.append("enemy %s: hp must be >= 1" % row["id"])
		if row["size"] <= 0.0: errors.append("enemy %s: size must be > 0" % row["id"])
		if row["speed"] <= 0.0: errors.append("enemy %s: speed must be > 0" % row["id"])

	for row in tables["towers"]:
		towers[row["id"]] = row
		if row["duration"] <= 0.0: errors.append("tower %s: duration must be > 0" % row["id"])
		if row["radius"] <= 0.0: errors.append("tower %s: radius must be > 0" % row["id"])
		if row["burn_damage"] < 0 or row["poison_damage"] < 0: errors.append("tower %s: damage must not be negative" % row["id"])
		if row["poison_duration"] > 0.0 and row["poison_damage"] < 1: errors.append("tower %s: poisons for %ss but poison_damage is 0" % [row["id"], row["poison_duration"]])

	for id in enemies:
		if not enemies[id]["behaviour"] in ["-", "bomber", "healer", "splitter", "shield"]:
			errors.append("enemy %s: unknown behaviour '%s'" % [id, enemies[id]["behaviour"]])
	for row in tables["evolutions"]:
		if not weapons.has(row["id"]): errors.append("evolution %s: not in weapons.tsv" % row["id"])
		if not weapons.has(row["base"]): errors.append("evolution %s: unknown base gun '%s'" % [row["id"], row["base"]])
		if evolution_of.has(row["base"]): errors.append("evolution %s: %s already evolves" % [row["id"], row["base"]])
		var perk_known := false
		for p in tables["perks"]:
			perk_known = perk_known or p["id"] == row["perk"]
		if not perk_known: errors.append("evolution %s: unknown perk '%s'" % [row["id"], row["perk"]])
		for r in tables["rewards"]:
			if r["id"] == row["id"]: errors.append("evolution %s: evolved guns are earned, never dropped" % row["id"])
		evolution_of[row["base"]] = row
		base_of[row["id"]] = row["base"]
	for row in tables["effectiveness"]:
		if not weapons.has(row["weapon"]): errors.append("effectiveness %s: unknown weapon '%s'" % [row["id"], row["weapon"]])
		if not enemies.has(row["enemy"]): errors.append("effectiveness %s: unknown enemy '%s'" % [row["id"], row["enemy"]])
		var key: String = row["weapon"] + "|" + row["enemy"]
		if effectiveness.has(key): errors.append("effectiveness: pair %s listed twice" % key)
		effectiveness[key] = row["multiplier"]

	for row in tables["bosses"]:
		bosses.append(row)
		var id: String = row["id"]
		if row["hp_mult"] <= 0.0: errors.append("boss %s: hp_mult must be > 0" % id)
		if row["speed"] <= 0.0: errors.append("boss %s: speed must be > 0 (it has to reach you or its hold_z)" % id)
		if row["hold_z"] > 0.0 and row["hold_seconds"] <= 0.0:
			errors.append("boss %s: holds, so hold_seconds must be > 0 (or a boss you cannot kill is never-ending)" % id)
		for col in ["steer", "contact_dx", "hold_z", "hold_seconds", "strafe", "summon_every", "shoot_every", "shot_speed"]:
			if row[col] < 0.0: errors.append("boss %s: %s must not be negative" % [id, col])
		if row["contact_damage"] < 0 or row["summon_count"] < 0 or row["shot_damage"] < 0:
			errors.append("boss %s: contact_damage, summon_count and shot_damage must not be negative" % id)
		if row["summon_every"] > 0.0 and row["summon_count"] < 1: errors.append("boss %s: summons nothing (summon_count 0)" % id)
		if row["summon_every"] > 0.0 and not enemies.has(row["summon_enemy"]):
			errors.append("boss %s: summon_enemy '%s' is not an enemy" % [id, row["summon_enemy"]])
		if row["shoot_every"] > 0.0 and (row["shot_speed"] <= 0.0 or row["shot_damage"] < 1):
			errors.append("boss %s: shoots, so shot_speed must be > 0 and shot_damage >= 1" % id)
		if row["strafe"] > 0.0 and row["hold_z"] <= 0.0: errors.append("boss %s: strafe only works while holding (hold_z 0)" % id)
		if row["steer"] <= 0.0: errors.append("boss %s: steer must be > 0 (a charger that cannot follow you wraps round forever)" % id)
		if row["strafe"] > tuning_half_road(tables): errors.append("boss %s: strafe %s goes off the road" % [id, row["strafe"]])
		if not Color.html_is_valid(row["color"]): errors.append("boss %s: color '%s' is not a colour" % [id, row["color"]])

	var boss_ids := {}
	for b in bosses:
		boss_ids[b["id"]] = true
	for row in tables["character_looks"]:
		character_looks[row["id"]] = row
		if row["id"] != "player" and not enemies.has(row["id"]) and not boss_ids.has(row["id"]):
			errors.append("character_looks %s: not the player, an enemy or a boss" % row["id"])
		if row["scale"] <= 0.0: errors.append("character_looks %s: scale must be > 0" % row["id"])
	for id in ["player"] + enemies.keys() + boss_ids.keys():
		if not character_looks.has(id): errors.append("%s: no row in character_looks.tsv" % id)

	var reward_total := 0
	for row in tables["rewards"]:
		rewards.append(row)
		reward_total += row["weight"]
		if row["weight"] <= 0: errors.append("reward %s: weight must be > 0" % row["id"])
		if not REWARD_KINDS.has(row["kind"]): errors.append("reward %s: unknown kind '%s'" % [row["id"], row["kind"]])
		if row["kind"] == "weapon" and not weapons.has(row["id"]): errors.append("reward %s: no such weapon" % row["id"])
		if row["kind"] == "tower" and not towers.has(row["id"]): errors.append("reward %s: no such tower" % row["id"])
		if String(row["label"]).strip_edges() == "": errors.append("reward %s: label is empty" % row["id"])
		if not Color.html_is_valid(row["color"]): errors.append("reward %s: color '%s' is not a colour" % [row["id"], row["color"]])
	if reward_total != 100:
		errors.append("rewards: weights sum to %d, must be 100" % reward_total)

	var last_start := -INF
	for row in tables["spawns"]:
		var band := {"id": row["id"], "start": row["start"], "weights": []}
		var total := 0
		for col in row:
			if col == "id" or col == "start":
				continue
			if not enemies.has(col):
				errors.append("spawns: column '%s' is not an enemy id" % col)
				continue
			band["weights"].append([col, row[col]])
			total += row[col]
			if row[col] < 0: errors.append("spawns %s: negative weight for %s" % [row["id"], col])
		if total != 100: errors.append("spawns %s: weights sum to %d, must be 100" % [row["id"], total])
		if row["start"] <= last_start: errors.append("spawns %s: start %s not after previous band" % [row["id"], row["start"]])
		last_start = row["start"]
		spawn_bands.append(band)
	if not spawn_bands.is_empty() and spawn_bands[0]["start"] != 0.0:
		errors.append("spawns: first band must start at 0")

	for row in tables["tuning"]:
		tuning[row["id"]] = row["value"]
		if not TUNING_KEYS.has(row["id"]):
			errors.append("tuning: '%s' is not read by the sim (dead key)" % row["id"])
	for key in TUNING_KEYS:
		if not tuning.has(key):
			errors.append("tuning: missing '%s'" % key)
			continue
		var v: float = tuning[key]
		if TUNING_MIN.has(key) and v < TUNING_MIN[key]:
			errors.append("tuning: %s = %s, must be at least %s" % [key, v, TUNING_MIN[key]])
		elif v < 0.0 and not TUNING_NEGATIVE_OK.has(key):
			errors.append("tuning: %s = %s, must not be negative" % [key, v])
		if TUNING_PROBABILITY.has(key) and v > 1.0:
			errors.append("tuning: %s = %s, is a chance and must be at most 1" % [key, v])
	if tuning.get("initial_hp", 1.0) > tuning.get("max_hp", 1.0):
		errors.append("tuning: initial_hp is above max_hp")
