extends "res://scripts/ports/sfx.gd"
## The Babylon build's procedural sounds (SoundSystem.ts), rendered once at start-up into short WAV clips
## and played through a small pool of players. Per-frame caps stop a minigun from stacking 20 voices.
##
##   shoot       1200 Hz sine, 40 ms              hit        noise, 60 ms
##   kill        440/660/880 square arpeggio       hurt       180 Hz saw, 150 ms
##   ice_crack   2000 Hz sine + noise, 80 ms       shatter    3000/2000/1000 sine arpeggio
##   pickup      523/659/784/1047 sine arpeggio    boss       80/160 triangle, 400 ms each
##   game_over   440/392/349/294 triangle arpeggio

const Events = preload("res://scripts/sim/events.gd")
const K = Events.Kind

const HANDLED := [K.FIRED, K.ENEMY_HIT, K.ENEMY_KILLED, K.PLAYER_HURT, K.ICE_HIT, K.ICE_SHATTERED, K.PICKUP,
	K.BOSS_STARTED, K.BOSS_HIT, K.BOSS_CONTACT, K.BOSS_DEFEATED, K.GAME_OVER, K.LEVEL_UP, K.PERK_TAKEN]

const RATE := 22050
const VOICES := 12
## Most of one sound per frame; extra requests in the same frame are dropped.
const PER_FRAME := {"shoot": 1, "hit": 2, "kill": 2, "hurt": 1, "ice_crack": 1, "ice_shatter": 1, "pickup": 1, "boss": 1, "game_over": 1}

var muted := false
var _clips := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 99
	_clips["shoot"] = _tone([1200.0], 0.04, 0.25, "sine")
	_clips["hit"] = _noise(0.06, 0.2)
	_clips["kill"] = _tone([440.0, 660.0, 880.0], 0.04, 0.3, "square")
	_clips["hurt"] = _tone([180.0], 0.15, 0.4, "saw")
	_clips["ice_crack"] = _mix(_tone([2000.0], 0.08, 0.25, "sine"), _noise(0.08, 0.15))
	_clips["ice_shatter"] = _tone([3000.0, 2000.0, 1000.0], 0.1, 0.3, "sine")
	_clips["pickup"] = _tone([523.0, 659.0, 784.0, 1047.0], 0.08, 0.35, "sine")
	_clips["boss"] = _tone([80.0, 160.0], 0.4, 0.5, "triangle")
	_clips["game_over"] = _tone([440.0, 392.0, 349.0, 294.0], 0.15, 0.4, "triangle")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func set_muted(value: bool) -> void:
	muted = value


func handle(events: Array) -> void:
	if muted:
		return
	var played := {}
	for ev in events:
		var name := ""
		match ev["kind"]:
			K.FIRED:
				name = "shoot"
			K.ENEMY_HIT, K.BOSS_HIT:
				name = "hit"
			K.ENEMY_KILLED, K.BOSS_DEFEATED:
				name = "kill"
			K.PLAYER_HURT, K.BOSS_CONTACT:
				name = "hurt"
			K.ICE_HIT:
				name = "ice_crack"
			K.ICE_SHATTERED:
				name = "ice_shatter"
			K.PICKUP, K.LEVEL_UP, K.PERK_TAKEN:
				name = "pickup"
			K.BOSS_STARTED:
				name = "boss"
			K.GAME_OVER:
				name = "game_over"
		if name == "" or played.get(name, 0) >= PER_FRAME[name]:
			continue
		played[name] = played.get(name, 0) + 1
		var p := _players[_next]
		_next = (_next + 1) % _players.size()
		p.stream = _clips[name]
		p.play()


# ---------- synthesis ----------

func _tone(freqs: Array, note_seconds: float, volume: float, wave: String) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for f in freqs:
		var n := int(note_seconds * RATE)
		for i in n:
			var t := float(i) / RATE
			var phase := fmod(t * f, 1.0)
			var v := 0.0
			match wave:
				"sine":
					v = sin(TAU * phase)
				"square":
					v = 1.0 if phase < 0.5 else -1.0
				"saw":
					v = 2.0 * phase - 1.0
				"triangle":
					v = 4.0 * absf(phase - 0.5) - 1.0
			samples.append(v * volume * _envelope(i, n))
	return _wav(samples)


func _noise(seconds: float, volume: float) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var samples := PackedFloat32Array()
	for i in n:
		samples.append(_rng.randf_range(-1.0, 1.0) * volume * _envelope(i, n))
	return _wav(samples)


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


## 5 ms attack, exponential-ish decay to silence at the end of the note (no clicks).
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
