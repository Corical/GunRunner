extends RefCounted
## Reads data/*.tsv and builds sim Rules. The only place game data touches the file system.

const DataTable = preload("res://scripts/data/data_table.gd")
const Rules = preload("res://scripts/sim/rules.gd")

const SCHEMA := 1
const DATA_DIR := "res://data"


## Raw parsed rows per table name; errors collected in `errors`.
static func load_tables(errors: PackedStringArray, data_dir := DATA_DIR) -> Dictionary:
	var tables := {}
	for name in Rules.TABLES:
		var result := DataTable.load_file(data_dir.path_join(name + ".tsv"), SCHEMA, PackedStringArray(Rules.TABLES[name]))
		errors.append_array(result.errors)
		tables[name] = result.rows
	return tables


static func load_rules(data_dir := DATA_DIR) -> Rules:
	var errors := PackedStringArray()
	var tables := load_tables(errors, data_dir)
	if not errors.is_empty():
		var failed := Rules.new()
		failed.errors = errors
		return failed
	return Rules.from_tables(tables)
