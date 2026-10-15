extends "res://tests/test_case.gd"

const GLog = preload("res://scripts/log/logger.gd")
const Sinks = preload("res://scripts/log/sinks.gd")


func _logger() -> Array:
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	var mem := Sinks.Memory.new()
	logger.add_sink(mem)
	return [logger, mem]


func test_line_format_keeps_field_order_and_tick() -> void:
	var pair := _logger()
	pair[0].tick = 42
	pair[0].info("spawn", "wave", {"band": 2, "placed": 3, "skipped_pool": 0})
	eq(pair[1].lines[0], "42 INFO spawn wave band=2 placed=3 skipped_pool=0")


func test_values_formatted_unambiguously() -> void:
	var pair := _logger()
	pair[0].debug("a", "b", {"f": 1.23456, "s": "two words", "e": "", "plain": "x"})
	eq(pair[1].lines[0], "-1 DEBUG a b f=1.235 s=\"two words\" e=\"\" plain=x")


func test_min_level_filters_output_but_still_counts() -> void:
	var pair := _logger()
	pair[0].min_level = GLog.Level.WARN
	pair[0].debug("a", "hidden")
	pair[0].info("a", "hidden")
	pair[0].warn("a", "shown")
	eq(pair[1].lines.size(), 1)
	eq(pair[0].counts[GLog.Level.DEBUG], 1, "filtered lines still counted")
	eq(pair[0].counts[GLog.Level.WARN], 1)


func test_every_sink_gets_every_line() -> void:
	var logger := GLog.new()
	logger.mirror_errors_to_engine = false
	var a := Sinks.Memory.new()
	var b := Sinks.Memory.new()
	logger.add_sink(a)
	logger.add_sink(b)
	logger.error("pool", "exhausted", {"pool": "enemy"})
	eq(a.lines, b.lines)
	eq(a.lines.size(), 1)
	eq(logger.counts[GLog.Level.ERROR], 1)


## Regression: game.gd passed Sinks.Stdout.new().write; the Callable did not keep the sink alive
## and every line hit a null instance. The logger must own its sinks.
func test_sink_with_no_other_reference_stays_alive() -> void:
	var logger := GLog.new()
	logger.add_sink(Sinks.Memory.new())
	logger.info("a", "b")
	var mem: Sinks.Memory = logger._sinks[0]
	eq(mem.lines.size(), 1, "orphan sink still received the line")


func test_file_sink_writes_and_closes() -> void:
	var path := "user://test-logs/logger-test.log"
	var sink := Sinks.File.new(path)
	ok(sink.is_open(), "file sink opened")
	var logger := GLog.new()
	logger.add_sink(sink)
	logger.info("run", "start", {"seed": 7})
	logger.info("run", "end", {"ticks": 0})
	sink.close()
	var text := FileAccess.get_file_as_string(path)
	eq(text.split("\n", false).size(), 2, "two lines on disk: %s" % text)
	ok(text.contains("run start seed=7"), "content on disk")
