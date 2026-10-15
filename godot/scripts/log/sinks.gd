extends RefCounted
## Log sinks. Each exposes write(line); hand the object itself to Logger.add_sink(sink).


class Stdout:
	extends RefCounted

	func write(line: String) -> void:
		print(line)


class Memory:
	extends RefCounted
	var lines: PackedStringArray = []

	func write(line: String) -> void:
		lines.append(line)

	func find(fragment: String) -> PackedStringArray:
		var out := PackedStringArray()
		for line in lines:
			if line.contains(fragment):
				out.append(line)
		return out


class File:
	extends RefCounted
	var path := ""
	var _file: FileAccess

	func _init(file_path: String) -> void:
		path = file_path
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
		_file = FileAccess.open(file_path, FileAccess.WRITE)
		if _file == null:
			push_error("log file sink: cannot open %s (error %d)" % [file_path, FileAccess.get_open_error()])

	func is_open() -> bool:
		return _file != null

	func write(line: String) -> void:
		if _file != null:
			_file.store_line(line)

	func close() -> void:
		if _file != null:
			_file.flush()
			_file.close()
			_file = null
