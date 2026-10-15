extends RefCounted
## Validated game rules built from already-parsed table rows (no file access here; see data/rules_loader.gd).
## Cross-checks every reference between tables. A Rules with errors must not be used to run a game.

const TABLES := {
	"weapons": ["id", "name", "fire_rate", "damage", "bullet_count", "bullet_spread", "bullet_size", "bullet_color", "max_range", "penetration", "splash_radius"],
	"enemies": ["id", "name", "hp", "speed", "color", "size", "score", "switches_lanes"],
	"towers": ["id", "name", "color", "duration", "radius", "damage_per_sec", "slow_multiplier", "poison_duration"],
	"effectiveness": ["id", "weapon", "enemy", "multiplier"],
	"rewards": ["id", "kind", "weight"],
	"spawns": ["id", "start"],
	"tuning": ["id", "value", "source"],
}

const REWARD_KINDS := ["weapon", "tower", "heal", "armor", "maxhp", "frenzy", "speed"]
const DEFAULT_WEAPON := "pistol"

## Every tuning key the sim reads. A key in tuning.tsv that is not here is dead data and an error.
const TUNING_KEYS := [
	"game_speed", "road_width", "initial_hp", "max_hp", "player_z", "player_move_speed", "player_road_margin",
	"muzzle_z_offset", "enemy_speed", "enemy_spawn_distance", "enemy_spawn_jitter", "enemy_despawn_z", "enemy_pool",
	"enemy_road_margin", "enemy_radius_per_size", "spawn_interval", "spawn_interval_min", "spawn_interval_decay",
	"wave_size_max", "wave_size_metres", "spawn_min_gap", "spawn_tries", "flanker_first_min", "flanker_first_extra",
	"flanker_retarget_min", "flanker_retarget_extra", "flanker_lateral_speed", "burn_tick", "poison_tick",
	"bullet_speed", "bullet_despawn_z", "bullet_pool", "bullet_spread_speed", "bullet_hit_radius",
	"splash_max_victims", "enemy_hit_player_radius", "upgrade_spawn_per_second", "upgrade_ice_hp", "upgrade_speed",
	"upgrade_pool", "upgrade_despawn_z", "upgrade_radius", "pickup_dx", "pickup_dz", "heal_amount", "armor_amount",
	"maxhp_amount", "frenzy_seconds", "frenzy_damage_mult", "speed_buff_seconds", "speed_buff_rate_mult", "tower_z",
	"tower_pool", "boss_interval", "boss_base_hp", "boss_hp_per_wave", "boss_spawn_z", "boss_radius",
	"boss_speed_full_hp", "boss_speed_bonus_at_zero_hp", "boss_contact_dx", "boss_contact_player_radius",
	"boss_contact_damage", "boss_pushback", "boss_score_per_wave", "boss_steer_speed",
]

var errors: PackedStringArray = []
var weapons := {}        ## id -> row
var enemies := {}        ## id -> row
var enemy_ids: PackedStringArray = []   ## table order (stable iteration)
var towers := {}         ## id -> row
var effectiveness := {}  ## "weapon|enemy" -> multiplier
var rewards: Array[Dictionary] = []     ## rows in roll order
var spawn_bands: Array[Dictionary] = [] ## {id, start, weights: Array of [enemy_id, weight]} ascending by start
var tuning := {}         ## id -> float


func ok() -> bool:
	return errors.is_empty()


## Tuning value. Keys are validated at build time, so a missing key here is a programming error.
func t(key: String) -> float:
	assert(tuning.has(key), "unknown tuning key " + key)
	return tuning[key]


func multiplier(weapon_id: String, enemy_id: String) -> float:
	return effectiveness.get(weapon_id + "|" + enemy_id, 1.0)


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
	for row in tables["weapons"]:
		weapons[row["id"]] = row
		if row["fire_rate"] <= 0.0: errors.append("weapon %s: fire_rate must be > 0" % row["id"])
		if row["damage"] < 1: errors.append("weapon %s: damage must be >= 1" % row["id"])
		if row["bullet_count"] < 1: errors.append("weapon %s: bullet_count must be >= 1" % row["id"])
		if row["penetration"] < 1: errors.append("weapon %s: penetration must be >= 1" % row["id"])
		if row["max_range"] <= 0.0: errors.append("weapon %s: max_range must be > 0" % row["id"])
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

	for row in tables["effectiveness"]:
		if not weapons.has(row["weapon"]): errors.append("effectiveness %s: unknown weapon '%s'" % [row["id"], row["weapon"]])
		if not enemies.has(row["enemy"]): errors.append("effectiveness %s: unknown enemy '%s'" % [row["id"], row["enemy"]])
		var key: String = row["weapon"] + "|" + row["enemy"]
		if effectiveness.has(key): errors.append("effectiveness: pair %s listed twice" % key)
		effectiveness[key] = row["multiplier"]

	var reward_total := 0
	for row in tables["rewards"]:
		rewards.append(row)
		reward_total += row["weight"]
		if row["weight"] <= 0: errors.append("reward %s: weight must be > 0" % row["id"])
		if not REWARD_KINDS.has(row["kind"]): errors.append("reward %s: unknown kind '%s'" % [row["id"], row["kind"]])
		if row["kind"] == "weapon" and not weapons.has(row["id"]): errors.append("reward %s: no such weapon" % row["id"])
		if row["kind"] == "tower" and not towers.has(row["id"]): errors.append("reward %s: no such tower" % row["id"])
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
