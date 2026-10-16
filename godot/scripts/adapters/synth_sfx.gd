extends "res://scripts/ports/sfx.gd"
## Synthesised game sounds, rendered once at start-up into short WAV clips and played through a pool of players.
## One sound per weapon, softer "warm" hits and kills (sine pops instead of square-wave beeps), a buzzing "zzz"
## for buffs (Corne 17:30: "homey... associate with the weapon and what you're doing"). Per-frame caps stop a
## minigun stacking 12 voices. Volume = master bus.

const Events = preload("res://scripts/sim/events.gd")
const K = Events.Kind

const HANDLED := [K.FIRED, K.ENEMY_HIT, K.ENEMY_KILLED, K.PLAYER_HURT, K.ICE_HIT, K.ICE_SHATTERED, K.PICKUP,
	K.BOSS_STARTED, K.BOSS_HIT, K.BOSS_CONTACT, K.BOSS_DEFEATED, K.GAME_OVER, K.LEVEL_UP, K.PERK_TAKEN, K.EXPLOSION, K.CRIT,
	K.TRAP_HIT, K.TRAP_DESTROYED, K.TRAP_TRIGGERED, K.UPGRADE_LOST, K.BOSS_SUMMONED, K.BOSS_SHOT, K.CHAIN_ARC]

const RATE := 22050
const VOICES := 14
const PER_FRAME := {"hit": 2, "kill": 2, "hurt": 1, "ice_crack": 1, "ice_shatter": 1, "pickup": 1, "buff": 1,
	"level": 1, "boss": 1, "game_over": 1, "explode": 2, "crit": 1, "trap": 1, "trap_break": 1}

var muted := false
var _clips := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_ms := {}  ## sound name -> last time it started (ms)
var PROTECTED := {}  ## clips a new sound must not cut off (filled in _ready)
## Minimum ms between two starts of the same sound; shot_* default 40. Values are ours, by ear.
const MIN_GAP_MS := {"hit": 35, "kill": 45, "ice_crack": 60, "crit": 70, "explode": 80, "trap": 200, "trap_break": 80, "zap": 60}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	# Weapons: each its own voice.
	_clips["shot_pistol"] = _mix(_sweep(900.0, 500.0, 0.06, 0.28, "sine"), _noise(0.03, 0.12))
	_clips["shot_smg"] = _mix(_sweep(1300.0, 800.0, 0.035, 0.2, "sine"), _noise(0.02, 0.08))
	_clips["shot_minigun"] = _mix(_sweep(1600.0, 1100.0, 0.025, 0.12, "sine"), _noise(0.015, 0.06))
	_clips["shot_shotgun"] = _mix(_noise(0.16, 0.45), _sweep(220.0, 90.0, 0.14, 0.35, "sine"))
	_clips["shot_laser"] = _sweep(2200.0, 500.0, 0.12, 0.22, "sine")
	_clips["shot_rocket"] = _mix(_noise(0.28, 0.3), _sweep(140.0, 70.0, 0.28, 0.35, "triangle"))
	_clips["shot_railgun"] = _mix(_sweep(300.0, 2400.0, 0.12, 0.25, "saw"), _sweep(2400.0, 180.0, 0.2, 0.35, "sine"))
	_clips["shot_flamethrower"] = _noise(0.09, 0.12)
	_clips["shot_grenade"] = _mix(_sweep(260.0, 140.0, 0.09, 0.4, "sine"), _noise(0.04, 0.15))
	# Feedback: warm, round, short.
	_clips["shot_lightning"] = _mix(_buzz_zzz(0.09, 0.22), _sweep(1800.0, 900.0, 0.07, 0.15, "saw"))
	_clips["zap"] = _mix(_buzz_zzz(0.06, 0.16), _noise(0.04, 0.1))
	_clips["hit"] = _mix(_sweep(240.0, 150.0, 0.06, 0.3, "sine"), _noise(0.03, 0.1))
	_clips["kill"] = _tone([523.0, 784.0], 0.05, 0.28, "sine")
	_clips["hurt"] = _mix(_sweep(160.0, 70.0, 0.2, 0.55, "triangle"), _noise(0.08, 0.2))
	_clips["ice_crack"] = _mix(_tone([2000.0], 0.06, 0.18, "sine"), _noise(0.06, 0.12))
	_clips["ice_shatter"] = _tone([2600.0, 1950.0, 1300.0], 0.07, 0.25, "sine")
	_clips["pickup"] = _tone([523.0, 659.0, 784.0, 1047.0], 0.07, 0.3, "sine")
	_clips["buff"] = _buzz_zzz(0.32, 0.3)
	_clips["level"] = _tone([392.0, 523.0, 659.0, 784.0, 1047.0], 0.08, 0.32, "triangle")
	_clips["boss"] = _tone([80.0, 160.0], 0.4, 0.5, "triangle")
	_clips["game_over"] = _tone([440.0, 392.0, 349.0, 294.0], 0.15, 0.4, "triangle")
	_clips["explode"] = _mix(_sweep(90.0, 40.0, 0.4, 0.6, "sine"), _noise(0.32, 0.45))
	_clips["crit"] = _mix(_sweep(2600.0, 700.0, 0.07, 0.3, "saw"), _noise(0.05, 0.2))
	_clips["trap"] = _mix(_sweep(420.0, 110.0, 0.35, 0.45, "saw"), _sweep(300.0, 80.0, 0.35, 0.25, "square"))
	_clips["trap_break"] = _mix(_sweep(500.0, 120.0, 0.12, 0.3, "square"), _noise(0.1, 0.25))
	for long_clip in ["explode", "level", "boss", "game_over", "trap"]:
		PROTECTED[_clips[long_clip]] = true
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)


func set_muted(value: bool) -> void:
	muted = value


## 0..1 effects volume on the SFX bus (Settings slider); 0 = silent.
func set_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("SFX")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.001)))


func handle(events: Array) -> void:
	if muted:
		return
	var played := {}
	for ev in events:
		var name := ""
		match ev["kind"]:
			K.FIRED:
				name = "shot_" + String(ev["weapon"])
			K.ENEMY_HIT, K.BOSS_HIT:
				name = "hit"
			K.ENEMY_KILLED, K.BOSS_DEFEATED:
				name = "kill"
			K.PLAYER_HURT, K.BOSS_CONTACT:
				name = "hurt"
			K.ICE_HIT, K.UPGRADE_LOST:
				name = "ice_crack"
			K.ICE_SHATTERED:
				name = "ice_shatter"
			K.PICKUP:
				name = "buff" if ev.get("reward_kind", "") in ["frenzy", "speed", "armor", "heal", "maxhp"] else "pickup"
			K.PERK_TAKEN:
				name = "buff"
			K.LEVEL_UP:
				name = "level"
			K.TRAP_HIT:
				name = "hit"
			K.TRAP_DESTROYED:
				name = "trap_break"
			K.TRAP_TRIGGERED:
				name = "trap"
			K.CRIT:
				name = "crit"
			K.EXPLOSION:
				name = "explode"
			K.CHAIN_ARC:
				name = "zap"
			K.BOSS_STARTED, K.BOSS_SUMMONED:
				name = "boss"
			K.BOSS_SHOT:
				name = "shot_rocket"
			K.GAME_OVER:
				name = "game_over"
		if name == "" or not _clips.has(name):
			continue
		if played.get(name, 0) >= PER_FRAME.get(name, 1):
			continue
		# Per-frame caps alone allowed ~240 hit sounds a second at 120 fps (Fable review #9): a minimum gap per sound.
		var now := Time.get_ticks_msec()
		var gap: int = MIN_GAP_MS.get(name, 40 if name.begins_with("shot_") else 0)
		if gap > 0 and now - int(_last_ms.get(name, -100000)) < gap:
			continue
		_last_ms[name] = now
		played[name] = played.get(name, 0) + 1
		var p := _voice()
		if p == null:
			continue
		p.stream = _clips[name]
		p.play()


## A free voice if there is one; otherwise the oldest that is not playing a long, important sound (explosion,
## level-up, boss, game over) - those used to be cut off after ~0.1 s by a flood of hit sounds.
func _voice() -> AudioStreamPlayer:
	for i in _players.size():
		var p := _players[(_next + i) % _players.size()]
		if not p.playing:
			_next = (_next + i + 1) % _players.size()
			return p
	for i in _players.size():
		var p := _players[(_next + i) % _players.size()]
		if not PROTECTED.has(p.stream):
			_next = (_next + i + 1) % _players.size()
			return p
	return null


# ---------- synthesis ----------

func _tone(freqs: Array, note_seconds: float, volume: float, wave: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for f in freqs:
		var n := int(note_seconds * RATE)
		var phase := 0.0
		for i in n:
			phase = fmod(phase + f / RATE, 1.0)
			samples.append(_wave(wave, phase) * volume * _envelope(i, n))
	return _wav(samples)


## Pitch glides from f0 to f1 over the note (zaps, thumps, cracks).
func _sweep(f0: float, f1: float, seconds: float, volume: float, wave: String) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var samples := PackedFloat32Array()
	var phase := 0.0
	for i in n:
		var f := lerpf(f0, f1, float(i) / n)
		phase = fmod(phase + f / RATE, 1.0)
		samples.append(_wave(wave, phase) * volume * _envelope(i, n))
	return _wav(samples)


## The buff "zzz": a buzzy square wave, wobbling in volume 28 times a second.
func _buzz_zzz(seconds: float, volume: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var samples := PackedFloat32Array()
	var phase := 0.0
	for i in n:
		phase = fmod(phase + 180.0 / RATE, 1.0)
		var wobble := 0.6 + 0.4 * sin(TAU * 28.0 * i / RATE)
		samples.append(_wave("square", phase) * volume * wobble * _envelope(i, n) * 0.6)
	return _wav(samples)


func _noise(seconds: float, volume: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var samples := PackedFloat32Array()
	for i in n:
		samples.append(_rng.randf_range(-1.0, 1.0) * volume * _envelope(i, n))
	return _wav(samples)


static func _wave(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if phase < 0.5 else -1.0
		"saw":
			return 2.0 * phase - 1.0
		"triangle":
			return 4.0 * absf(phase - 0.5) - 1.0
	return sin(TAU * phase)


func _mix(a: AudioStreamWAV, b: AudioStreamWAV) -> AudioStreamWAV:
	var da := a.data
	var db := b.data
	var out := PackedByteArray()
	out.resize(maxi(da.size(), db.size()))
	for i in range(0, out.size(), 2):
		var va := da.decode_s16(i) if i < da.size() else 0
		var vb := db.decode_s16(i) if i < db.size() else 0
		out.encode_s16(i, clampi(va + vb, -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = out
	return w


## 5 ms attack, then a curved decay to silence at the end of the note (no clicks).
static func _envelope(i: int, n: int) -> float:
	var attack := int(0.005 * RATE)
	if i < attack:
		return float(i) / attack
	var t := float(i - attack) / maxi(1, n - attack)
	return pow(1.0 - t, 2.0)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w
