extends "res://tests/test_case.gd"
## No track ships without a clean licence and a full credit; every mood has a run track; files exist.

const MusicPlayer = preload("res://scripts/audio/music_player.gd")


func _player() -> Node:
	var p: Node = MusicPlayer.new()
	p._ready()
	return p


func test_music_table_loads_clean() -> void:
	var p := _player()
	eq(p.errors, PackedStringArray())
	ok(p.tracks.size() >= 1, "at least one track")
	p.free()


func test_every_track_is_licensed_and_credited() -> void:
	var p := _player()
	for t in p.tracks:
		ok(MusicPlayer.ALLOWED_LICENCES.has(t["licence"]), "%s: licence '%s' not allowed (CC0 / CC-BY only)" % [t["id"], t["licence"]])
		ok(String(t["artist"]).strip_edges() != "", "%s: no artist to credit" % t["id"])
		ok(String(t["source_url"]).begins_with("https://"), "%s: no source link" % t["id"])
		ok(ResourceLoader.exists(t["file"]), "%s: file %s missing" % [t["id"], t["file"]])
		ok(t["role"] in ["run", "boss"], "%s: role '%s'" % [t["id"], t["role"]])
	p.free()


func test_every_mood_has_a_run_track_and_off_comes_first() -> void:
	var p := _player()
	var moods: PackedStringArray = p.moods()
	eq(moods[0], "Off")
	for m in moods:
		if m == "Off":
			continue
		var has_run := false
		for t in p.tracks:
			if t["mood"] == m and t["role"] == "run":
				has_run = true
		ok(has_run, "mood %s has no run track" % m)
	p.free()


func test_boss_track_used_only_when_the_mood_has_one() -> void:
	var p := _player()
	p._mood = "Retro"
	p._boss = true
	var expected := ""
	for t in p.tracks:
		if t["mood"] == "Retro" and t["role"] == "run" and expected == "":
			expected = t["file"]
	for t in p.tracks:
		if t["mood"] == "Retro" and t["role"] == "boss":
			expected = t["file"]
	eq(p._pick(), expected, "boss track if Retro has one, else its run track")
	p._mood = "Off"
	eq(p._pick(), "", "Off is silent")
	p.free()
