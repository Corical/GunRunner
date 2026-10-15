extends RefCounted
## Records a run so it can be replayed exactly: the sim is deterministic, so seed + every input change +
## every setting change that affects the sim = the whole game. A few KB per minute.
##
## File (JSON lines, schema 1), user://runs/run-<seed>.jsonl:
##   {"type":"header","schema":1,"seed":N,"data":<fingerprint of data/*.tsv>,"spawn_interval":S}
##   {"type":"in","t":T,"move":M} or {"type":"in","t":T,"target_x":X}   input from step T+1 on
##   {"type":"set","t":T,"spawn_interval":S}                            applied before step T+1
##   {"type":"chk","t":T,"hash":H}                                       every 600 steps, for verification
##   {"type":"end","t":T,"hash":H,"score":..,"distance":..,"kills":..}   on game over / quit
## Floats are written at full precision so a replay steers exactly as the player did.

const SCHEMA := 1
const CHECK_EVERY := 600

var path := ""
var _file: FileAccess
var _last_input := {}
var _closed := false


func _init(file_path: String, seed_value: int, data_fingerprint: int, spawn_interval: float) -> void:
	path = file_path
	DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
	_file = FileAccess.open(file_path, FileAccess.WRITE)
	if _file == null:
		push_error("run recorder: cannot open %s (error %d)" % [file_path, FileAccess.get_open_error()])
		return
	_write({"type": "header", "schema": SCHEMA, "seed": seed_value, "data": data_fingerprint, "spawn_interval": spawn_interval})


## Debug start (--weapon=): the run began with this weapon instead of the pistol. Replay applies it first.
func start_weapon(id: String) -> void:
	_write({"type": "start_weapon", "weapon": id})


## Debug start (--tower=): a tower placed at x 0 before the first step. Replay applies it first.
func start_tower(id: String) -> void:
	_write({"type": "start_tower", "tower": id})


## Call with the input about to be given to step T+1 (T = sim.tick before the step).
func input(tick: int, inp: Dictionary) -> void:
	if inp == _last_input:
		return
	_last_input = inp.duplicate()
	var line := {"type": "in", "t": tick}
	line.merge(inp)
	_write(line)


func setting(tick: int, spawn_interval: float) -> void:
	_write({"type": "set", "t": tick, "spawn_interval": spawn_interval})


## Call after each step.
func after_step(sim: Object) -> void:
	if sim.tick % CHECK_EVERY == 0:
		_write({"type": "chk", "t": sim.tick, "hash": sim.state_hash()})


func finish(sim: Object) -> void:
	if _closed or _file == null:
		return
	_write({"type": "end", "t": sim.tick, "hash": sim.state_hash(), "score": sim.score, "distance": sim.distance, "kills": sim.kills})
	_file.close()
	_closed = true


func flush() -> void:
	if _file != null and not _closed:
		_file.flush()


func _write(d: Dictionary) -> void:
	if _file != null and not _closed:
		_file.store_line(JSON.stringify(d, "", false, true))


## Fingerprint of the game data: a replay against different balance numbers would not reproduce the run.
static func data_fingerprint(data_dir := "res://data") -> int:
	var parts := PackedStringArray()
	var files := Array(DirAccess.get_files_at(data_dir)).filter(func(f: String) -> bool: return f.ends_with(".tsv"))
	files.sort()
	for f in files:
		parts.append(f + "\n" + FileAccess.get_file_as_string(data_dir.path_join(f)).replace("\r", ""))
	return hash("\n".join(parts))
