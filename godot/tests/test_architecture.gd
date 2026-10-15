extends "res://tests/test_case.gd"
## The sim must stay pure: no scene tree, no global randomness, no clocks, no OS, no printing, no files.
## Comments are stripped before scanning. The scanner is itself tested against known-bad samples.

const SIM_DIR := "res://scripts/sim"

const FORBIDDEN := {
	"extends Node": "(?m)^\\s*extends\\s+(Node|Node2D|Node3D|Control|CanvasItem)\\b",
	"global randomness": "(?<![\\w.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(",
	"Time": "(?<![\\w.])Time\\.",
	"OS": "(?<![\\w.])OS\\.",
	"Engine": "(?<![\\w.])Engine\\.",
	"print": "(?<![\\w.])(print|prints|printt|print_rich|printerr)\\s*\\(",
	"files": "(?<![\\w.])(FileAccess|DirAccess)\\b",
	"scene tree": "\\bget_tree\\s*\\(",
}


static func violations(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	var code := PackedStringArray()
	for line in source.split("\n"):
		var hash_at := line.find("#")
		code.append(line.substr(0, hash_at) if hash_at >= 0 else line)
	var text := "\n".join(code)
	for name in FORBIDDEN:
		var re := RegEx.create_from_string(FORBIDDEN[name])
		for m in re.search_all(text):
			out.append("%s: '%s'" % [name, m.get_string().strip_edges()])
	return out


func test_scanner_catches_known_bad_code() -> void:
	var bad := {
		"extends Node3D\n": "extends Node",
		"var x = randf()\n": "global randomness",
		"randomize()\n": "global randomness",
		"var t = Time.get_ticks_msec()\n": "Time",
		"if OS.has_feature(\"x\"): pass\n": "OS",
		"print(\"hi\")\n": "print",
		"var f = FileAccess.open(p, 1)\n": "files",
		"get_tree().quit()\n": "scene tree",
	}
	for code in bad:
		var found := violations(code)
		ok(found.size() == 1 and found[0].begins_with(bad[code]), "%s -> %s" % [code.strip_edges(), found])


func test_scanner_allows_legitimate_code() -> void:
	var fine := "extends RefCounted\nvar _rng := RandomNumberGenerator.new()\nfunc f(): return _rng.randf()\n# randf() and print() in a comment are fine\nvar log_print_count := 0\n"
	eq(violations(fine), PackedStringArray())


## A script with a parse error prints "SCRIPT ERROR" here, which check.bat fails on; load() also returns null.
func test_every_script_parses() -> void:
	var count := 0
	for dir in ["res://scripts", "res://scripts/sim", "res://scripts/data", "res://scripts/log", "res://tests"]:
		for f in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			count += 1
			ok(load(dir.path_join(f)) != null, "%s does not load" % dir.path_join(f))
	ok(count >= 20, "found %d scripts" % count)


func test_sim_folder_is_pure() -> void:
	var files := Array(DirAccess.get_files_at(SIM_DIR)).filter(func(f: String) -> bool: return f.ends_with(".gd"))
	ok(files.size() >= 1, "sim folder must contain scripts (empty folder would pass vacuously)")
	for f in files:
		var path: String = SIM_DIR.path_join(f)
		for v in violations(FileAccess.get_file_as_string(path)):
			fail("%s: %s" % [path, v])
