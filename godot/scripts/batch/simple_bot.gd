extends RefCounted
## A plain rule-based player for headless runs. Reads sim state, returns a move axis. No randomness of its
## own, so a run is fully decided by the sim seed. Priorities: dodge, collect, aim.

const Sim = preload("res://scripts/sim/sim.gd")

const DODGE_AHEAD := 12.0
const COLLECT_AHEAD := 30.0
const AIM_AHEAD := 90.0


func decide(s: Sim) -> float:
	var p := s.player
	var half: float = s.rules.t("road_width") / 2.0 - s.rules.t("player_road_margin")

	# 1. Dodge the boss when it is close and lined up.
	if s.boss.active and s.boss.z - p.z < DODGE_AHEAD + 4.0 and absf(s.boss.x - p.x) < 5.0:
		return _away_from(s.boss.x, p.x, half)

	# 1b. Dodge a boss shot about to land on us (where it will be when it reaches our z).
	for sh in s.boss.shots:
		if not sh.active or sh.z < p.z or sh.z - p.z > DODGE_AHEAD:
			continue
		var land_x: float = sh.x + sh.vx * (sh.z - p.z) / -sh.vz
		if absf(land_x - p.x) < s.rules.t("boss_shot_radius") + 0.8:
			return _away_from(land_x, p.x, half)

	# 2. Dodge the nearest enemy that would hit us.
	var threat = null
	for e in s.enemies.pool:
		if not e.active:
			continue
		var ahead: float = e.z - p.z
		if ahead < 0.0 or ahead > DODGE_AHEAD:
			continue
		if absf(e.x - p.x) < s.rules.t("enemy_hit_player_radius") + e.radius + 0.8:
			if threat == null or e.z < threat.z:
				threat = e
	if threat != null:
		return _away_from(threat.x, p.x, half)

	# 3. Collect a shattered reward coming our way.
	for u in s.upgrades.pool:
		if u.active and u.thawed and u.z - p.z > -1.0 and u.z - p.z < COLLECT_AHEAD:
			return _toward(u.x, p.x)

	# 4. Aim: ice first (it holds rewards), then the nearest enemy.
	var target_x := p.x
	var best := INF
	for u in s.upgrades.pool:
		if u.active and not u.thawed and u.z - p.z < AIM_AHEAD and u.z < best:
			best = u.z
			target_x = u.x
	if best == INF:
		for e in s.enemies.pool:
			if e.active and e.z > p.z and e.z < best:
				best = e.z
				target_x = e.x
	if s.boss.active and best == INF:
		target_x = s.boss.x
	return _toward(target_x, p.x)


## Level-up choice: a fixed preference order (damage and rate first), so bot runs stay deterministic.
const PERK_PREFERENCE := ["damage", "fire_rate", "multishot", "pierce", "vitality", "crit", "range", "plating",
	"bullet_speed", "agility", "magnet", "engineer"]


## The full step input: steering, plus a pick that the sim only reads while a level-up choice is open.
func input(s: Sim) -> Dictionary:
	return {"move": decide(s), "pick": pick(s)}


func pick(s: Sim) -> int:
	var best := 0
	var best_rank := 999
	for i in s.choices.size():
		var rank := PERK_PREFERENCE.find(s.choices[i])
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best = i
	return best


static func _toward(target: float, x: float) -> float:
	return clampf((target - x) * 0.6, -1.0, 1.0)


static func _away_from(danger_x: float, x: float, half: float) -> float:
	var room_left := x + half
	var room_right := half - x
	if absf(danger_x - x) < 0.05:
		return 1.0 if room_right > room_left else -1.0
	var away := signf(x - danger_x)
	if (away > 0.0 and room_right < 1.0) or (away < 0.0 and room_left < 1.0):
		away = -away
	return away
