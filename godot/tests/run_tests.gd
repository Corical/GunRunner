extends SceneTree
## Headless test runner:  godot --headless --path godot --script res://tests/run_tests.gd
## Runs every test_* method of every tests/test_*.gd on a fresh instance. Exit code 1 on any failure
## or when no tests are found. A runtime error inside a test prints "SCRIPT ERROR"; check.bat fails on that.


## Counts engine/script errors, so a test that dies on a runtime error (which aborts the test function
## without recording a failure) is reported as FAIL instead of passing silently.
class ErrorCounter:
	extends Logger
	var errors := 0
	var last := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		errors += 1
		last = "%s:%d %s %s %s" % [file, line, function, code, rationale]

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd"
	)
	files.sort()
	var run := 0
	var failed := 0
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		# load() returns a script object even when it failed to compile; can_instantiate() is false then.
		# Without this a broken test file was silently skipped and the run still reported "failed=0".
		if script == null or not script.can_instantiate():
			print("FAIL %s: does not load or compile" % file)
			failed += 1
			continue
		var names: Array[String] = []
		for m in script.get_script_method_list():
			if String(m["name"]).begins_with("test_"):
				names.append(m["name"])
		names.sort()
		for test_name in names:
			var instance: Object = script.new()
			instance.current = test_name
			var errors_before := counter.errors
			instance.call(test_name)
			if counter.errors > errors_before:
				instance.failures.append("%s: raised %d engine/script error(s), last: %s" % [test_name, counter.errors - errors_before, counter.last])
			run += 1
			if instance.failures.is_empty():
				print("ok   %s::%s" % [file, test_name])
			else:
				failed += 1
				for f in instance.failures:
					print("FAIL %s::%s" % [file, f])
	print("tests run=%d failed=%d" % [run, failed])
	if run == 0:
		print("FAIL no tests found")
		quit(1)
		return
	quit(1 if failed > 0 else 0)
