extends "res://tests/test_case.gd"

const DataTable = preload("res://scripts/data/data_table.gd")

const GOOD := "#schema 1\nid\tdamage\trate\tpierce\tname\nstring\tint\tfloat\tbool\tstring\npistol\t1\t3.0\t0\tPistol\n# comment between rows\nrail\t15\t0.8\ttrue\tRail Gun\n"


func _parse(text: String, required := PackedStringArray(["id"])) -> DataTable.Result:
	return DataTable.parse(text, "t.tsv", 1, required)


func _has_error(r: DataTable.Result, fragment: String) -> bool:
	for e in r.errors:
		if e.contains(fragment):
			return true
	return false


func test_good_table_parses_every_type() -> void:
	var r := _parse(GOOD)
	ok(r.ok(), "errors: %s" % [r.errors])
	eq(r.rows.size(), 2)
	eq(r.rows[0]["damage"], 1)
	eq(r.rows[0]["rate"], 3.0)
	eq(r.rows[0]["pierce"], false)
	eq(r.rows[1]["pierce"], true)
	eq(r.rows[1]["name"], "Rail Gun")
	eq(r.by_id()["rail"]["damage"], 15)


func test_windows_line_endings_parse() -> void:
	var r := _parse(GOOD.replace("\n", "\r\n"))
	ok(r.ok(), "CRLF errors: %s" % [r.errors])
	eq(r.rows.size(), 2)
	eq(r.rows[1]["name"], "Rail Gun", "trailing \\r must not stick to last cell")


func test_missing_schema_line_is_an_error() -> void:
	var r := _parse(GOOD.substr(GOOD.find("\n") + 1))
	ok(_has_error(r, "#schema"), "got %s" % [r.errors])
	eq(r.rows.size(), 0)


func test_schema_mismatch_is_an_error() -> void:
	var r := DataTable.parse(GOOD, "t.tsv", 2, PackedStringArray())
	ok(_has_error(r, "schema 1, expected 2"), "got %s" % [r.errors])


func test_schema_not_a_number() -> void:
	ok(_has_error(_parse(GOOD.replace("#schema 1", "#schema one")), "not an int"), "")


func test_missing_required_column() -> void:
	var r := _parse(GOOD, PackedStringArray(["id", "splash"]))
	ok(_has_error(r, "missing required column 'splash'"), "got %s" % [r.errors])


func test_unknown_type_is_an_error() -> void:
	ok(_has_error(_parse(GOOD.replace("\tfloat\t", "\tdouble\t")), "unknown type 'double'"), "")


func test_type_row_shorter_than_header() -> void:
	ok(_has_error(_parse(GOOD.replace("string\tint\tfloat\tbool\tstring", "string\tint\tfloat\tbool")), "4 types for 5 columns"), "")


func test_short_row_is_an_error_not_a_zero() -> void:
	var r := _parse(GOOD.replace("pistol\t1\t3.0\t0\tPistol", "pistol\t1\t3.0\t0"))
	ok(_has_error(r, "4 cells, expected 5"), "got %s" % [r.errors])
	eq(r.rows.size(), 1, "bad row dropped, good row kept")
	ok(not r.ok(), "result must not be ok")


func test_long_row_is_an_error() -> void:
	ok(_has_error(_parse(GOOD.replace("Pistol", "Pistol\textra")), "6 cells, expected 5"), "")


func test_empty_cell_is_an_error() -> void:
	ok(_has_error(_parse(GOOD.replace("pistol\t1\t", "pistol\t\t")), "empty cell"), "")


func test_bad_numbers_and_bools() -> void:
	ok(_has_error(_parse(GOOD.replace("pistol\t1\t", "pistol\t1x\t")), "'1x' is not an int"), "int")
	ok(_has_error(_parse(GOOD.replace("3.0", "3.0.1")), "not a float"), "float")
	ok(_has_error(_parse(GOOD.replace("\t0\tPistol", "\tyes\tPistol")), "not a bool"), "bool")
	ok(_has_error(_parse(GOOD.replace("pistol\t1\t", "pistol\t 1\t")), "not an int"), "leading space is not silently trimmed")


func test_float_column_accepts_integer_text() -> void:
	var r := _parse(GOOD.replace("3.0", "3"))
	ok(r.ok(), "%s" % [r.errors])
	eq(r.rows[0]["rate"], 3.0)


func test_duplicate_id_is_an_error() -> void:
	var r := _parse(GOOD.replace("rail\t15", "pistol\t15"))
	ok(_has_error(r, "duplicate id 'pistol'"), "got %s" % [r.errors])
	eq(r.rows.size(), 1, "duplicate not appended")


func test_empty_file_and_header_only() -> void:
	ok(_has_error(_parse(""), "empty file"), "empty")
	ok(_has_error(_parse("#schema 1\nid\tdamage\n"), "no header and type rows"), "header only")


func test_missing_file_is_an_error() -> void:
	var r := DataTable.load_file("res://data/does_not_exist.tsv", 1, PackedStringArray())
	ok(_has_error(r, "cannot open"), "got %s" % [r.errors])
