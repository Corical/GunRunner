extends RefCounted
## Positive checks run after every sim step in headless batches. A batch passes only when every run
## produced kills, ended properly and never broke one of these - "no errors logged" is not enough.

const Sim = preload("res://scripts/sim/sim.gd")
const Events = preload("res://scripts/sim/events.gd")

var failures: PackedStringArray = []
var game_over_events := 0

var _prev_tick := 0
var _prev_score := 0
var _prev_kills := 0
var _prev_distance := -1.0


func check_step(s: Sim) -> void:
	if s.tick != _prev_tick + 1:
		_fail(s, "tick jumped %d -> %d" % [_prev_tick, s.tick])
	if s.score < _prev_score:
		_fail(s, "score fell %d -> %d" % [_prev_score, s.score])
	if s.kills < _prev_kills:
		_fail(s, "kills fell")
	if s.distance <= _prev_distance:
		_fail(s, "distance did not grow")
	if s.combo < 0:
		_fail(s, "negative combo")
	var p := s.player
	var half: float = s.rules.t("road_width") / 2.0 - s.rules.t("player_road_margin")
	if p.hp < 0 or p.hp > p.max_hp or p.max_hp > int(s.rules.t("max_hp")) or p.armor < 0:
		_fail(s, "player hp=%d max=%d armor=%d" % [p.hp, p.max_hp, p.armor])
	if absf(p.x) > half + 1e-6:
		_fail(s, "player off road x=%f" % p.x)
	var enemy_half: float = s.rules.t("road_width") / 2.0 - s.rules.t("enemy_road_margin")
	for e in s.enemies.pool:
		if e.active and (e.hp <= 0 or absf(e.x) > enemy_half + 1e-6):
			_fail(s, "enemy %d %s hp=%d x=%f" % [e.serial, e.type_id, e.hp, e.x])
	if s.boss.active and (s.boss.hp <= 0 or s.boss.hp > s.boss.max_hp):
		_fail(s, "boss hp=%d/%d" % [s.boss.hp, s.boss.max_hp])
	for ev in s.events:
		if ev["kind"] == Events.Kind.GAME_OVER:
			game_over_events += 1
	if s.over != (game_over_events == 1) or game_over_events > 1:
		_fail(s, "over=%s with %d GAME_OVER events" % [s.over, game_over_events])
	_prev_tick = s.tick
	_prev_score = s.score
	_prev_kills = s.kills
	_prev_distance = s.distance


func check_end(s: Sim, tick_cap: int) -> void:
	if s.kills == 0:
		_fail(s, "run ended with no kills")
	if not s.over and s.tick < tick_cap:
		_fail(s, "run stopped early without game over")


func _fail(s: Sim, what: String) -> void:
	if failures.size() < 20:
		failures.append("tick %d: %s" % [s.tick, what])
