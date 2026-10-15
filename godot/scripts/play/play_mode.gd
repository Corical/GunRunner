extends Node
## The windowed game: menus, a sim driven by the frame clock, and the views that draw it.
## Flags (after --): --seed=N  --bot (the batch bot steers)  --autostart (skip the start screen)
## Keys follow the Babylon build: Enter/Space start, Space pauses and resumes, Enter restarts, ↑/↓ speed.

const GLog = preload("res://scripts/log/logger.gd")
const Rules = preload("res://scripts/sim/rules.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Events = preload("res://scripts/sim/events.gd")
const FrameClock = preload("res://scripts/sim/frame_clock.gd")
const PrimitiveCatalog = preload("res://scripts/adapters/primitive_catalog.gd")
const HumanControls = preload("res://scripts/adapters/human_controls.gd")
const BotControls = preload("res://scripts/adapters/bot_controls.gd")
const ConfigSettings = preload("res://scripts/adapters/config_settings.gd")
const WorldView = preload("res://scripts/view/world_view.gd")
const Actors = preload("res://scripts/view/actors.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Menus = preload("res://scripts/ui/menus.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")
const Juice = preload("res://scripts/view/juice.gd")
const SynthSfx = preload("res://scripts/adapters/synth_sfx.gd")
const DeviceHaptics = preload("res://scripts/adapters/device_haptics.gd")
const MusicPlayer = preload("res://scripts/audio/music_player.gd")
const RunRecorder = preload("res://scripts/stats/run_recorder.gd")
const LevelUpUi = preload("res://scripts/ui/level_up_ui.gd")

enum State { MENU, PLAYING, PAUSED, OVER }

var state := State.MENU

var _rules: Rules
var _logger: GLog
var _sim: Sim
var _clock := FrameClock.new()
var _controls: Object
var _settings_store: Object
var _settings := {}
var _world: Node3D
var _actors: Node3D
var _hud: CanvasLayer
var _menus: CanvasLayer
var _juice: Node3D
var _sfx: Node
var _haptics: Node
var _music: Node
var _frame_events: Array = []
var _recorder: RunRecorder
var _level_ui: CanvasLayer
var _pending_pick := -1  ## card tapped this frame; sent once with the next step's input
var _data_fingerprint := 0
var _seed_base := 0
var _games := 0
var _debug_weapon := ""  ## --weapon=grenade: start runs with this weapon (testing weapon feel); recorded in the header
var _debug_tower := ""  ## --tower=fire: a tower on the road at the start (testing status visuals); recorded
var _demo_fx := false  ## --demo-fx: 50% crits and the damage flash held on, to screenshot the effects

# Telemetry: one line per second of frame time, GPU time and sim steps (find what makes it slow).
var _tm_frames := 0
var _tm_steps := 0
var _tm_elapsed := 0.0
var _tm_gpu_ms := 0.0
var _tm_frame_ms: Array[float] = []
var _all_frame_ms: Array[float] = []
var _run_seconds := 0.0
var _wall := 0.0
# --shots=1,8,20 --shots-dir=C:/x : save the window as PNG at those seconds (cheap check without Movie Maker).
var _shot_times: Array[float] = []
var _shots_dir := ""


func start(rules: Rules, logger: GLog, args: Dictionary) -> void:
	_rules = rules
	_logger = logger
	_data_fingerprint = RunRecorder.data_fingerprint()
	_seed_base = int(args.get("seed", Time.get_unix_time_from_system()))
	_debug_weapon = str(args.get("weapon", ""))
	_debug_tower = str(args.get("tower", ""))
	_demo_fx = args.has("demo-fx")
	_controls = BotControls.new() if args.has("bot") else HumanControls.new()
	_settings_store = ConfigSettings.new()
	_settings = _settings_store.load_settings()
	_clock.set_speed(_settings["speed"])
	if args.has("speed"):
		# Measurement runs: override for this run only, the saved settings file is left alone.
		_clock.set_speed(float(args["speed"]))

	var catalog := PrimitiveCatalog.new(rules)
	_world = WorldView.new()
	add_child(_world)
	var view_options := {
		"shadows": args.has("shadows"), "glow": args.has("glow"),
		"fog": not args.has("no-fog"), "trees": not args.has("no-trees"),
	}
	_world.build(rules.t("road_width"), 12345, view_options)
	_run_seconds = float(args.get("run-seconds", 0))
	if args.has("shots"):
		for t in str(args["shots"]).split(","):
			_shot_times.append(float(t))
		_shots_dir = str(args.get("shots-dir", "user://shots"))
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_logger.info("perf", "setup", {
		"gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"window": str(DisplayServer.window_get_size()), "vsync": DisplayServer.window_get_vsync_mode(),
		"shadows": view_options["shadows"], "glow": view_options["glow"], "fog": view_options["fog"], "trees": view_options["trees"],
	})

	_sim = _new_sim()
	_actors = Actors.new()
	add_child(_actors)
	_actors.setup(catalog, _sim)
	_logger.info("perf", "prewarm", {"ms": _actors.prewarm_ms, "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
	_juice = Juice.new()
	add_child(_juice)
	_juice.setup(rules, _world.camera)
	_actors.juice = _juice
	_sfx = SynthSfx.new()
	add_child(_sfx)
	_sfx.set_muted(args.has("mute"))
	_sfx.set_volume(float(_settings.get("volume", 0.8)))
	_haptics = DeviceHaptics.new()
	add_child(_haptics)
	_haptics.set_enabled(bool(_settings.get("haptics", true)))
	_ensure_bus("SFX")
	_ensure_bus("Music")
	_sfx.set_volume(float(_settings.get("volume", 0.8)))
	_music = MusicPlayer.new()
	add_child(_music)
	if not _music.errors.is_empty():
		_logger.error("music", "data_invalid", {"errors": "; ".join(_music.errors)})
	_music.set_volume(float(_settings.get("music_volume", 0.6)))
	_music.set_mood(str(_settings.get("music", "Off")))

	_hud = Hud.new()
	add_child(_hud)
	_hud.build(catalog.is_stand_in())
	_hud.update(_sim, _clock.speed)
	_hud.hurt_flash_enabled = bool(_settings.get("hurt_flash", true))

	_menus = Menus.new()
	add_child(_menus)
	_menus.build(rules, _settings)
	_menus.start_pressed.connect(_start_game)
	_menus.restart_pressed.connect(_start_game)
	_menus.resume_pressed.connect(_resume)
	_menus.pause_pressed.connect(_pause)
	_menus.settings_changed.connect(_on_settings)
	_menus.set_music_options(_music.moods(), _music.tracks)
	_level_ui = LevelUpUi.new()
	add_child(_level_ui)
	_level_ui.build(rules)
	_level_ui.picked.connect(func(i: int): _pending_pick = i)

	_logger.info("play", "ready", {
		"controls": _controls.name(), "saved_speed": _settings["speed"], "speed": _clock.speed,
		"spawn_interval": _settings["spawn_interval"], "settings_file": ProjectSettings.globalize_path(_settings_store.path),
	})
	if args.has("open-settings"):  # debug: screenshot the Settings panel
		_menus._toggle(_menus._settings_panel)
	if args.has("autostart"):
		_start_game()


## Separate volume for effects and music: each gets its own bus feeding Master.
static func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _new_sim() -> Sim:
	var s := Sim.new(_rules, _seed_base + _games, _logger)
	if _settings.get("spawn_interval", 0.0) > 0.0:
		s.enemies.set_manual_interval(_settings["spawn_interval"])
	return s


func _start_game() -> void:
	if _recorder != null and _sim != null:
		_recorder.finish(_sim)  # restart mid-run: close the previous recording properly
	_sim = _new_sim()
	var run_seed := _seed_base + _games
	_recorder = RunRecorder.new("user://runs/run-%d.jsonl" % run_seed, run_seed, _data_fingerprint, float(_settings.get("spawn_interval", 0.0)))
	if _debug_weapon != "" and _rules.weapons.has(_debug_weapon):
		_sim.player.set_weapon(_debug_weapon)
		_recorder.start_weapon(_debug_weapon)
	if _debug_tower != "" and _rules.towers.has(_debug_tower):
		_sim.towers.deploy(_debug_tower, 0.0, func(_k, _f): pass)
		_recorder.start_tower(_debug_tower)
	if _demo_fx:  # debug screenshots only; not recorded, so a replay of this run will not match
		_sim.player.mods["crit_chance"] = 0.5
	_logger.info("play", "recording", {"path": ProjectSettings.globalize_path(_recorder.path)})
	_games += 1
	_clock.reset()
	_actors.bind(_sim)
	_juice.reset()
	_music.set_boss(false)
	_menus.show_playing()
	get_viewport().gui_release_focus()
	state = State.PLAYING
	_logger.info("play", "game_start", {"seed": _seed_base + _games - 1, "game": _games})


func _pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	_clock.paused = true
	_menus.show_pause()
	_logger.info("play", "paused", {"tick": _sim.tick})


func _resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	_clock.paused = false
	_menus.show_playing()
	get_viewport().gui_release_focus()


func _game_over() -> void:
	state = State.OVER
	if _recorder != null:
		_recorder.finish(_sim)
	_menus.show_game_over(UiKit.thousands(_sim.score), int(_sim.distance), _sim.kills)


func _on_settings(settings: Dictionary, source: String) -> void:
	_logger.info("settings", "changed", {
		"source": source, "speed": settings["speed"], "spawn_interval": settings["spawn_interval"],
		"was_speed": _settings.get("speed", 1.0), "state": State.keys()[state],
	})
	_settings = settings
	_clock.set_speed(settings["speed"])
	if _sim != null:
		_sim.enemies.set_manual_interval(settings["spawn_interval"])
		if _recorder != null and state != State.OVER:
			_recorder.setting(_sim.tick, settings["spawn_interval"])
	_settings_store.save_settings(settings)
	_sfx.set_volume(float(settings.get("volume", 0.8)))
	_haptics.set_enabled(bool(settings.get("haptics", true)))
	_music.set_mood(str(settings.get("music", "Off")))
	_music.set_volume(float(settings.get("music_volume", 0.6)))
	_hud.hurt_flash_enabled = bool(settings.get("hurt_flash", true))


func _process(delta: float) -> void:
	_telemetry(delta)
	if state == State.PLAYING:
		var steps := _clock.advance(delta)
		_tm_steps += steps
		for i in steps:
			var raw: Dictionary = _controls.read(_sim)
			if _pending_pick >= 0 and not _sim.choices.is_empty():
				raw["pick"] = _pending_pick
				_pending_pick = -1
			var inp: Dictionary = Sim.quantize_input(raw, not _sim.choices.is_empty())
			_recorder.input(_sim.tick, inp)
			_sim.step(inp)
			_recorder.after_step(_sim)
			_frame_events.append_array(_sim.events)
			for ev in _sim.events:
				if ev["kind"] == Events.Kind.PLAYER_HURT:
					_hud.flash_hurt(0.6)
				elif ev["kind"] == Events.Kind.BOSS_CONTACT:
					_hud.flash_hurt(1.0)
				if ev["kind"] == Events.Kind.BOSS_STARTED:
					_music.set_boss(true)
				elif ev["kind"] == Events.Kind.BOSS_DEFEATED:
					_music.set_boss(false)
				if ev["kind"] == Events.Kind.GAME_OVER:
					_game_over()
			if _sim.over:
				break
	var view_dt := delta if state == State.PLAYING else 0.0
	_juice.handle(_frame_events)
	_sfx.handle(_frame_events)
	_haptics.handle(_frame_events)
	_frame_events.clear()
	# A level-up card stops the sim, so interpolating would make everything jitter behind it (Fable #10).
	var alpha := _clock.alpha() if state == State.PLAYING and _sim.choices.is_empty() else 1.0
	_world.scroll(_sim.distance - (1.0 - alpha) * _rules.t("game_speed") * FrameClock.STEP)
	_actors.sync(alpha, view_dt)
	_actors.flash(_juice.flash_requests, view_dt)
	_world.follow(-lerpf(_sim.player.prev_x, _sim.player.x, alpha), view_dt)
	# Game over keeps the last shake/fade running so the death reads; only a pause freezes effects.
	_juice.update(delta if state != State.PAUSED else 0.0, _world.camera_base)
	_hud.update(_sim, _clock.speed)
	_hud.tick(delta)
	if _demo_fx:
		_hud.flash_hurt(0.6)
	_level_ui.show_choices(_sim.choices if state == State.PLAYING else PackedStringArray(), _sim.level, _sim.player.perk_stacks)


## Android sends the app to the background (home button, call) or closes it without a game over: finish the
## recording so the run is still complete and verifiable.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		if _recorder != null and _sim != null:
			_recorder.flush()
			if what != NOTIFICATION_APPLICATION_PAUSED:
				_recorder.finish(_sim)
		if what == NOTIFICATION_APPLICATION_PAUSED and state == State.PLAYING:
			_pause()


func _telemetry(delta: float) -> void:
	_wall += delta
	_tm_frames += 1
	_tm_elapsed += delta
	_tm_frame_ms.append(delta * 1000.0)
	_all_frame_ms.append(delta * 1000.0)
	_tm_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	if _tm_elapsed >= 1.0:
		_tm_frame_ms.sort()
		_logger.info("perf", "second", {
			"fps": _tm_frames / _tm_elapsed, "frame_avg_ms": _tm_elapsed * 1000.0 / _tm_frames,
			"frame_max_ms": _tm_frame_ms[-1], "gpu_avg_ms": _tm_gpu_ms / _tm_frames,
			"cpu_render_ms": RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			"steps": _tm_steps, "tick": _sim.tick if _sim != null else 0, "dropped": _clock.dropped_steps,
			"models_built": _actors.models_built, "build_ms": _actors.build_usec / 1000.0, "fx_skipped": _juice.skipped,
			"objects": Performance.get_monitor(Performance.OBJECT_COUNT), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		})
		_actors.models_built = 0
		_actors.build_usec = 0
		var dc: Dictionary = _actors.drawn_counts()
		if dc["active"] != dc["drawn"]:
			_logger.warn("view", "enemies_not_drawn", dc)
		# Write the log out every second: on Android the app is killed, not closed, and the buffer was lost.
		_logger.flush()
		if _recorder != null:
			_recorder.flush()
		_tm_frames = 0
		_tm_steps = 0
		_tm_elapsed = 0.0
		_tm_gpu_ms = 0.0
		_tm_frame_ms.clear()
	if not _shot_times.is_empty() and _wall >= _shot_times[0]:
		var t: float = _shot_times.pop_front()
		var path := _shots_dir.path_join("shot-%05.1fs.png" % t)
		var err := get_viewport().get_texture().get_image().save_png(path)
		_logger.info("shots", "saved", {"path": path, "error": err, "tick": _sim.tick if _sim != null else 0,
			"player_x": _sim.player.x if _sim != null else 0.0})
	if _run_seconds > 0.0 and _wall >= _run_seconds:
		_report_and_quit()


## Same measures as .local/baseline-babylon.md, first 10 frames dropped.
func _report_and_quit() -> void:
	_run_seconds = 0.0
	var f := _all_frame_ms.slice(10)
	f.sort()
	var total := 0.0
	for x in f:
		total += x
	var worst := f.slice(int(f.size() * 0.99))
	var worst_total := 0.0
	for x in worst:
		worst_total += x
	_logger.info("perf", "summary", {
		"frames": f.size(), "avg_ms": total / f.size(), "p50_ms": f[f.size() / 2], "p99_ms": f[int(f.size() * 0.99)],
		"worst1pct_avg_ms": worst_total / worst.size(), "max_ms": f[-1],
		"over_33ms": f.filter(func(x): return x > 33.4).size(), "tick": _sim.tick, "dropped": _clock.dropped_steps,
	})
	get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		if state == State.PLAYING:
			_controls.on_pointer(event, _sim, get_viewport().get_visible_rect().size.x)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_on_confirm()
		KEY_SPACE:
			if state == State.PLAYING:
				_pause()
			else:
				_on_confirm()
		KEY_ESCAPE:
			_pause()
		KEY_1, KEY_2, KEY_3:
			if state == State.PLAYING and not _sim.choices.is_empty():
				_pending_pick = key.physical_keycode - KEY_1
		KEY_M:
			_sfx.set_muted(not _sfx.muted)
			_logger.info("settings", "mute", {"muted": _sfx.muted})
		KEY_UP:
			_menus.change_speed(0.1, "key_up")
		KEY_DOWN:
			_menus.change_speed(-0.1, "key_down")
		_:
			return
	get_viewport().set_input_as_handled()


func _on_confirm() -> void:
	match state:
		State.MENU, State.OVER:
			_start_game()
		State.PAUSED:
			_resume()
