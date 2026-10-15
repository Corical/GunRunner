extends RefCounted
## Structured log lines: "<tick> <LEVEL> <area> <event> key=value key=value".
## One instance per run, passed into every sim class constructor (never a global).
## Sinks are objects with write(line: String); see sinks.gd. The logger holds a strong reference to each
## (a bare Callable would not keep a RefCounted sink alive).

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]

var min_level: Level = Level.DEBUG
## ERROR lines are also raised with push_error. Tests that exercise error() turn this off,
## because check.bat treats any engine "ERROR:" line as a failure.
var mirror_errors_to_engine := true
## Set by the game loop before each sim step so every line carries the sim tick (-1 = outside the sim).
var tick := -1
var counts := {Level.DEBUG: 0, Level.INFO: 0, Level.WARN: 0, Level.ERROR: 0}

var _sinks: Array[Object] = []


func add_sink(sink: Object) -> void:
	assert(sink.has_method("write"), "log sink must have write(line)")
	_sinks.append(sink)


## Asks every sink that buffers (the file sink) to write out what it has.
func flush() -> void:
	for sink in _sinks:
		if sink.has_method("flush"):
			sink.flush()


func debug(area: String, event: String, fields := {}) -> void:
	_emit(Level.DEBUG, area, event, fields)


func info(area: String, event: String, fields := {}) -> void:
	_emit(Level.INFO, area, event, fields)


func warn(area: String, event: String, fields := {}) -> void:
	_emit(Level.WARN, area, event, fields)


## Also raised as an engine error, so check.bat and logcat see it.
func error(area: String, event: String, fields := {}) -> void:
	_emit(Level.ERROR, area, event, fields)


func format_line(level: Level, area: String, event: String, fields: Dictionary) -> String:
	var parts := PackedStringArray([str(tick), LEVEL_NAMES[level], area, event])
	for key in fields:
		parts.append("%s=%s" % [key, _format_value(fields[key])])
	return " ".join(parts)


func _emit(level: Level, area: String, event: String, fields: Dictionary) -> void:
	counts[level] += 1
	if level < min_level:
		return
	var line := format_line(level, area, event, fields)
	if _sinks.is_empty():
		print(line)
	for sink in _sinks:
		sink.write(line)
	if level == Level.ERROR and mirror_errors_to_engine:
		push_error(line)


static func _format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_FLOAT:
			return "%.3f" % value
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(value)
			return "\"%s\"" % s if s.contains(" ") or s == "" else s
		_:
			return str(value)
