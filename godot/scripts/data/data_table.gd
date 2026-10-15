extends RefCounted
## Strict tab-separated table loader.
##
## Format:
##   #schema <n>          first non-empty line, required
##   name<TAB>name...     column names
##   type<TAB>type...     int | float | string | bool
##   value<TAB>value...   one row per entry; '#' lines are comments
##
## Every problem is an error, never a silent default: missing/extra cells, empty cells, bad numbers,
## unknown types, duplicate ids, missing required columns, wrong schema. Callers must refuse to run on errors.

const TYPES := ["int", "float", "string", "bool"]


class Result:
	extends RefCounted
	var source := ""
	var schema := -1
	var columns: PackedStringArray = []
	var rows: Array[Dictionary] = []
	var errors: PackedStringArray = []

	func ok() -> bool:
		return errors.is_empty()

	## Rows keyed by their "id" column (duplicates are already reported as errors).
	func by_id() -> Dictionary:
		var out := {}
		for row in rows:
			out[row["id"]] = row
		return out


static func load_file(path: String, expected_schema: int, required: PackedStringArray) -> Result:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var r := Result.new()
		r.source = path
		r.errors.append("%s: cannot open (error %d)" % [path, FileAccess.get_open_error()])
		return r
	return parse(file.get_as_text(), path, expected_schema, required)


static func parse(text: String, source: String, expected_schema: int, required: PackedStringArray) -> Result:
	var r := Result.new()
	r.source = source
	var types := PackedStringArray()
	var seen_ids := {}
	var line_no := 0
	for raw_line in text.split("\n"):
		line_no += 1
		var line := raw_line.strip_edges(false, true)
		if line == "":
			continue
		if r.schema == -1:
			if not line.begins_with("#schema "):
				r.errors.append("%s:%d: first line must be '#schema <n>'" % [source, line_no])
				return r
			var value := line.substr(8).strip_edges()
			if not value.is_valid_int():
				r.errors.append("%s:%d: schema '%s' is not an int" % [source, line_no, value])
				return r
			r.schema = value.to_int()
			if r.schema != expected_schema:
				r.errors.append("%s: schema %d, expected %d" % [source, r.schema, expected_schema])
				return r
			continue
		if line.begins_with("#"):
			continue
		var cells := line.split("\t")
		if r.columns.is_empty():
			r.columns = cells
			for name in required:
				if not r.columns.has(name):
					r.errors.append("%s: missing required column '%s'" % [source, name])
			continue
		if types.is_empty():
			types = cells
			if types.size() != r.columns.size():
				r.errors.append("%s:%d: %d types for %d columns" % [source, line_no, types.size(), r.columns.size()])
			for t in types:
				if not TYPES.has(t):
					r.errors.append("%s:%d: unknown type '%s'" % [source, line_no, t])
			if not r.errors.is_empty():
				return r
			continue
		if cells.size() != r.columns.size():
			r.errors.append("%s:%d: %d cells, expected %d" % [source, line_no, cells.size(), r.columns.size()])
			continue
		var row := {}
		var row_ok := true
		for i in r.columns.size():
			var parsed := _convert(cells[i], types[i])
			if parsed.has("error"):
				r.errors.append("%s:%d: column '%s': %s" % [source, line_no, r.columns[i], parsed["error"]])
				row_ok = false
			else:
				row[r.columns[i]] = parsed["value"]
		if not row_ok:
			continue
		if row.has("id"):
			if seen_ids.has(row["id"]):
				r.errors.append("%s:%d: duplicate id '%s' (first on line %d)" % [source, line_no, row["id"], seen_ids[row["id"]]])
				continue
			seen_ids[row["id"]] = line_no
		r.rows.append(row)
	if r.schema == -1:
		r.errors.append("%s: empty file" % source)
	elif types.is_empty():
		r.errors.append("%s: no header and type rows" % source)
	return r


static func _convert(raw: String, type: String) -> Dictionary:
	if raw == "":
		return {"error": "empty cell"}
	match type:
		"int":
			return {"value": raw.to_int()} if raw.is_valid_int() else {"error": "'%s' is not an int" % raw}
		"float":
			return {"value": raw.to_float()} if raw.is_valid_float() else {"error": "'%s' is not a float" % raw}
		"bool":
			match raw.to_lower():
				"1", "true":
					return {"value": true}
				"0", "false":
					return {"value": false}
			return {"error": "'%s' is not a bool (0/1/true/false)" % raw}
		_:
			return {"value": raw}
