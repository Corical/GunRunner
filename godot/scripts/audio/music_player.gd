extends Node
## Background music: plays the chosen mood's run track on a loop on the "Music" bus, switches to the mood's
## boss track during boss fights (if it has one), and fades between tracks. Mood "Off" = silence.
## Tracks and credits come from data/music.tsv (read once).

const DataTable = preload("res://scripts/data/data_table.gd")

const FADE_SECONDS := 0.8
const ALLOWED_LICENCES := ["CC0", "CC-BY 3.0", "CC-BY 4.0"]

var tracks: Array[Dictionary] = []
var errors: PackedStringArray = []

var _mood := "Off"
var _boss := false
var _current := ""   ## file playing now
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _fade := 1.0     ## 0..1 progress of the cross-fade from _b (old) to _a (new)


func _ready() -> void:
	var result := DataTable.load_file("res://data/music.tsv", 1,
		PackedStringArray(["id", "mood", "role", "title", "artist", "licence", "source_url", "file"]))
	errors = result.errors
	tracks = result.rows
	for p in [_new_player(), _new_player()]:
		add_child(p)
	_a = get_child(0)
	_b = get_child(1)


## Moods in table order, for the Settings choice ("Off" first).
func moods() -> PackedStringArray:
	var out := PackedStringArray(["Off"])
	for t in tracks:
		if not out.has(t["mood"]):
			out.append(t["mood"])
	return out


const Events = preload("res://scripts/sim/events.gd")
const HANDLED := [Events.Kind.BOSS_STARTED, Events.Kind.BOSS_DEFEATED]


## Presenter entry point: boss music on and off.
func handle(events: Array) -> void:
	for ev in events:
		if ev["kind"] == Events.Kind.BOSS_STARTED:
			set_boss(true)
		elif ev["kind"] == Events.Kind.BOSS_DEFEATED:
			set_boss(false)


func set_mood(mood: String) -> void:
	_mood = mood
	_refresh()


func set_boss(on: bool) -> void:
	if on != _boss:
		_boss = on
		_refresh()


## 0..1 on the Music bus; 0 = silent.
func set_volume(v: float) -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.001)))


func _process(dt: float) -> void:
	if _fade >= 1.0:
		return
	_fade = minf(1.0, _fade + dt / FADE_SECONDS)
	_a.volume_db = linear_to_db(maxf(_fade, 0.001))
	_b.volume_db = linear_to_db(maxf(1.0 - _fade, 0.001))
	if _fade >= 1.0:
		_b.stop()


func _refresh() -> void:
	var file := _pick()
	if file == _current:
		return
	_current = file
	var old := _a
	_a = _b
	_b = old
	_fade = 0.0
	if file == "":
		_a.stop()
		return
	var stream = load(file)
	if stream == null:
		push_warning("music: cannot load %s" % file)
		_current = ""  # try again on the next change instead of staying silent
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true  # without this an MP3 track plays once and the run goes silent
	_a.stream = stream
	_a.volume_db = -80.0
	_a.play()


func _pick() -> String:
	if _mood == "Off":
		return ""
	var run := ""
	for t in tracks:
		if t["mood"] != _mood:
			continue
		if _boss and t["role"] == "boss":
			return t["file"]
		if t["role"] == "run" and run == "":
			run = t["file"]
	return run


static func _new_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	return p
