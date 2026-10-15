extends RefCounted
## Base for test files. Methods named test_* are run by run_tests.gd, each on a fresh instance.

var failures: PackedStringArray = []
var current := ""
## Engine/script errors this test deliberately causes (push_error on a bad file). The runner fails the test if the
## count differs either way, so it also proves the error is really reported.
var expected_errors := 0


func eq(actual: Variant, expected: Variant, note := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s %s" % [current, var_to_str(expected), var_to_str(actual), note])


func ok(condition: bool, note: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current, note])


func fail(note: String) -> void:
	failures.append("%s: %s" % [current, note])
