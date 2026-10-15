extends "res://scripts/ports/haptics.gd"
## Vibration through Input.vibrate_handheld(duration_ms, amplitude 0..1) - signature read from the engine 15 Oct.
## Does nothing on PC. Per-weapon kick, hits, kills, damage, explosions, and a "zzz" pulse train on buffs
## (Corne: "when you get a buff... it gives you that little zzz"). A minimum gap between buzzes keeps fast guns
## from blurring into one long vibration; a stronger event may cut in.

const Events = preload("res://scripts/sim/events.gd")
const K = Events.Kind

const HANDLED := [K.FIRED, K.ENEMY_KILLED, K.PLAYER_HURT, K.EXPLOSION, K.PICKUP, K.PERK_TAKEN, K.LEVEL_UP,
	K.BOSS_STARTED, K.BOSS_CONTACT, K.BOSS_DEFEATED, K.ICE_SHATTERED, K.GAME_OVER, K.CRIT, K.TRAP_DESTROYED,
	K.TRAP_TRIGGERED]

## Per-weapon kick comes from data/weapon_looks.tsv (kick_ms, kick_amp); set by play_mode.
var fire_kick := {}  ## weapon id -> [ms, amplitude]
const MIN_GAP_MS := 45

var enabled := true
var _last_ms := -10000
var _last_amp := 0.0
var _pattern: Array = []   ## pending [at_ms, duration_ms, amplitude]
var _supported := false


func _ready() -> void:
	_supported = OS.has_feature("android") or OS.has_feature("ios")


func set_rules(rules) -> void:
	for id in rules.weapon_looks:
		fire_kick[id] = [int(rules.weapon_looks[id]["kick_ms"]), float(rules.weapon_looks[id]["kick_amp"])]


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_pattern.clear()


func handle(events: Array) -> void:
	if not enabled or not _supported:
		return
	for ev in events:
		match ev["kind"]:
			K.FIRED:
				var f: Array = fire_kick.get(ev["weapon"], [0, 0.0])
				if f[0] > 0:
					_buzz(f[0], f[1])
			K.ENEMY_KILLED:
				_buzz(10, 0.3)
			K.ICE_SHATTERED:
				_buzz(18, 0.4)
			K.TRAP_DESTROYED:
				_buzz(20, 0.45)
			K.TRAP_TRIGGERED:
				_train(2, 70, 110, 0.85)
			K.CRIT:
				_buzz(25, 0.6)
			K.EXPLOSION:
				_buzz(40, 0.75)
			K.PLAYER_HURT:
				_buzz(90, 1.0, true)
			K.BOSS_CONTACT:
				_buzz(140, 1.0, true)
			K.PICKUP, K.PERK_TAKEN:
				_zzz()
			K.LEVEL_UP:
				_train(3, 40, 60, 0.6)
			K.BOSS_STARTED:
				_train(2, 120, 160, 0.9)
			K.BOSS_DEFEATED:
				_train(4, 60, 90, 1.0)
			K.GAME_OVER:
				_buzz(300, 1.0, true)


func _process(_dt: float) -> void:
	if _pattern.is_empty():
		return
	var now := Time.get_ticks_msec()
	while not _pattern.is_empty() and _pattern[0][0] <= now:
		var p: Array = _pattern.pop_front()
		Input.vibrate_handheld(p[1], p[2])
		_last_ms = now
		_last_amp = p[2]


## Rate-limited single buzz; `force` (damage) always cuts in.
func _buzz(ms: int, amp: float, force := false) -> void:
	var now := Time.get_ticks_msec()
	if not force and now - _last_ms < MIN_GAP_MS and amp <= _last_amp:
		return
	Input.vibrate_handheld(ms, amp)
	_last_ms = now
	_last_amp = amp


## The buff "zzz": five quick light pulses.
func _zzz() -> void:
	_train(5, 18, 32, 0.35)


func _train(count: int, ms: int, every_ms: int, amp: float) -> void:
	var now := Time.get_ticks_msec()
	for i in count:
		_pattern.append([now + i * every_ms, ms, amp])
