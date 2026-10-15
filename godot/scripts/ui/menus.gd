extends CanvasLayer
## Start, pause and game-over screens, the Settings panel and the Enemy Guide.
## The guide is written from data/*.tsv, so it can only say what the game really does (plan D3).

signal start_pressed
signal resume_pressed
signal restart_pressed
signal pause_pressed
signal settings_changed(settings: Dictionary, source: String)

const Rules = preload("res://scripts/sim/rules.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

const SPAWN_LABELS := [[1.0, "Insane"], [1.5, "Very High"], [2.0, "High"], [2.5, "Normal"], [3.0, "Low"], [99.0, "Very Low"]]

var _start: Control
var _pause: Control
var _over: Control
var _over_stats: Label
var _settings_panel: Control
var _guide_panel: Control
var _corner_buttons: Control
var _speed_slider: HSlider
var _speed_value: Label
var _spawn_slider: HSlider
var _spawn_value: Label
var _volume_slider: HSlider
var _volume_value: Label
var _haptics_toggle: CheckButton
var _settings := {}
var _quiet := false  ## true while building/loading, so setting slider values doesn't echo back


func build(rules: Rules, settings: Dictionary) -> void:
	layer = 5
	_settings = settings.duplicate()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_start = _screen(root, "GUN RUNNER", "Shoot the ice, grab the weapons, survive the bosses.", "LOCK & LOAD", "start_pressed",
		"Slide your finger to steer (or ← →)  ·  firing is automatic  ·  Pause top right")
	_pause = _screen(root, "PAUSED", "", "RESUME", "resume_pressed", "Space or Enter to resume")
	_over = _screen(root, "GAME OVER", "", "PLAY AGAIN", "restart_pressed", "Enter to play again")
	_over_stats = _over.get_node("Box/Content/Subtitle")

	_corner_buttons = Control.new()
	_corner_buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	_corner_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_corner_buttons)
	# Left, under the HUD's score block (pill ~52 px + distance row ~24 px).
	var guide_btn := UiKit.small_button("Enemy Guide")
	guide_btn.pressed.connect(func(): _toggle(_guide_panel))
	_corner_buttons.add_child(guide_btn)
	UiKit.pin(guide_btn, Control.PRESET_TOP_LEFT, 16, 88)
	# Right, under the HUD's weapon pill (~52 px).
	var right_row := HBoxContainer.new()
	right_row.add_theme_constant_override("separation", 8)
	_corner_buttons.add_child(right_row)
	var pause_btn := UiKit.small_button("Pause")
	pause_btn.pressed.connect(func(): pause_pressed.emit())
	right_row.add_child(pause_btn)
	var settings_btn := UiKit.small_button("Settings")
	settings_btn.pressed.connect(func(): _toggle(_settings_panel))
	right_row.add_child(settings_btn)
	UiKit.pin(right_row, Control.PRESET_TOP_RIGHT, 16, 64)

	_settings_panel = _build_settings(root)
	_guide_panel = _build_guide(root, rules)
	show_start()


func show_start() -> void:
	_only(_start)


func show_playing() -> void:
	_only(null)


func show_pause() -> void:
	_only(_pause)


func show_game_over(score: String, distance: int, kills: int) -> void:
	_over_stats.text = "Score %s   ·   Distance %dm   ·   Kills %d" % [score, distance, kills]
	_only(_over)


func is_showing_start() -> bool:
	return _start.visible


func panels_open() -> bool:
	return _settings_panel.visible or _guide_panel.visible


func _only(screen: Control) -> void:
	for s in [_start, _pause, _over]:
		s.visible = s == screen
	if screen != null:
		var btn := screen.find_child("Action", true, false) as Button
		if btn != null:
			btn.grab_focus.call_deferred()


func _screen(root: Control, title: String, subtitle: String, action: String, sig: String, hint: String) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.name = "Box"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(centre)
	var col := VBoxContainer.new()
	col.name = "Content"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	centre.add_child(col)
	var t := UiKit.label(title, 64, Color("#FBBF24"), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var sub := UiKit.label(subtitle, 22, Color.WHITE)
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var btn := UiKit.button(action)
	btn.name = "Action"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func(): emit_signal(sig))
	col.add_child(btn)
	var h := UiKit.label(hint, 15, Color(1, 1, 1, 0.6))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(h)
	return dim


func _toggle(panel: Control) -> void:
	var opening := not panel.visible
	_settings_panel.visible = false
	_guide_panel.visible = false
	panel.visible = opening


func _build_settings(root: Control) -> Control:
	var p := UiKit.panel(Color(0, 0, 0, 0.85))
	p.custom_minimum_size = Vector2(300, 0)
	p.visible = false
	root.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)

	var speed_row := _slider_row(col, "Game speed")
	_speed_value = speed_row[0]
	_speed_slider = speed_row[1]
	_speed_slider.min_value = 0.3
	_speed_slider.max_value = 3.0
	_speed_slider.step = 0.1
	_speed_slider.value_changed.connect(_on_speed)

	var spawn_row := _slider_row(col, "Enemy spawn rate")
	_spawn_value = spawn_row[0]
	_spawn_slider = spawn_row[1]
	_spawn_slider.min_value = 3
	_spawn_slider.max_value = 30
	_spawn_slider.step = 1
	_spawn_slider.value_changed.connect(_on_spawn)
	var auto := UiKit.small_button("Auto (gets harder as you go)")
	auto.pressed.connect(_on_auto)
	col.add_child(auto)

	var volume_row := _slider_row(col, "Volume")
	_volume_value = volume_row[0]
	_volume_slider = volume_row[1]
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value_changed.connect(func(v: float):
		_volume_value.text = "%d%%" % int(round(v * 100))
		if _quiet:
			return
		_settings["volume"] = v
		settings_changed.emit(_settings.duplicate(), "volume_slider"))

	_haptics_toggle = CheckButton.new()
	_haptics_toggle.text = "Vibration"
	_haptics_toggle.custom_minimum_size = Vector2(0, 44)
	_haptics_toggle.add_theme_font_size_override("font_size", 16)
	_haptics_toggle.focus_mode = Control.FOCUS_NONE
	_haptics_toggle.toggled.connect(func(on: bool):
		if _quiet:
			return
		_settings["haptics"] = on
		settings_changed.emit(_settings.duplicate(), "haptics_toggle"))
	col.add_child(_haptics_toggle)
	apply_settings(_settings)
	UiKit.pin(p, Control.PRESET_TOP_RIGHT, 16, 124)
	return p


func apply_settings(settings: Dictionary) -> void:
	_quiet = true
	_settings = settings.duplicate()
	_speed_slider.value = settings["speed"]
	_speed_value.text = "%.1fx" % settings["speed"]
	var interval: float = settings["spawn_interval"]
	_spawn_slider.value = interval * 10.0 if interval > 0.0 else 18.0
	_spawn_value.text = _spawn_label(interval)
	_volume_slider.value = settings.get("volume", 0.8)
	_volume_value.text = "%d%%" % int(round(_volume_slider.value * 100))
	_haptics_toggle.button_pressed = settings.get("haptics", true)
	_quiet = false


var _speed_source := "slider"


## Arrow keys. Goes through the slider so both stay in step; the source is recorded for the log.
func change_speed(delta: float, source: String) -> void:
	_speed_source = source
	_speed_slider.value = clampf(_speed_slider.value + delta, 0.3, 3.0)
	_speed_source = "slider"


func _on_speed(v: float) -> void:
	_speed_value.text = "%.1fx" % v
	if _quiet:
		return
	_settings["speed"] = v
	settings_changed.emit(_settings.duplicate(), _speed_source)


## Babylon mapping: slider 3..30 / 10 = seconds between waves (UIManager.ts).
func _on_spawn(v: float) -> void:
	if _quiet:
		return
	_settings["spawn_interval"] = v / 10.0
	_spawn_value.text = _spawn_label(v / 10.0)
	settings_changed.emit(_settings.duplicate(), "spawn_slider")


func _on_auto() -> void:
	_settings["spawn_interval"] = 0.0
	_spawn_value.text = _spawn_label(0.0)
	settings_changed.emit(_settings.duplicate(), "auto_button")


static func _spawn_label(interval: float) -> String:
	if interval <= 0.0:
		return "Auto"
	for pair in SPAWN_LABELS:
		if interval < pair[0]:
			return pair[1]
	return "Very Low"


func _slider_row(col: VBoxContainer, title: String) -> Array:
	var row := HBoxContainer.new()
	col.add_child(row)
	var name_label := UiKit.label(title, 16, Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := UiKit.label("", 16, Color("#FBBF24"), true)
	row.add_child(value)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(260, 32)
	# Mouse/touch only: a focused slider would also eat the arrow keys that steer the player.
	slider.focus_mode = Control.FOCUS_NONE
	col.add_child(slider)
	return [value, slider]


func _build_guide(root: Control, rules: Rules) -> Control:
	var p := UiKit.panel(Color(0, 0, 0, 0.88))
	p.visible = false
	root.add_child(p)
	# Fixed height that fits a 720-tall screen under the corner buttons; scrolls when the text is longer.
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = false
	text.scroll_active = true
	text.custom_minimum_size = Vector2(440, 400)
	text.add_theme_font_size_override("normal_font_size", 15)
	text.add_theme_font_size_override("bold_font_size", 15)
	text.text = guide_text(rules)
	p.add_child(text)
	UiKit.pin(p, Control.PRESET_TOP_LEFT, 16, 144)
	return p


## Built only from the data: names, hp, speed, lane switching and the weapon table. Nothing else is claimed.
static func guide_text(rules: Rules) -> String:
	var lines := PackedStringArray(["[b]ENEMIES[/b]"])
	for id in rules.enemy_ids:
		var e: Dictionary = rules.enemies[id]
		var traits := PackedStringArray(["%d HP" % e["hp"]])
		if e["speed"] >= 1.25:
			traits.append("fast")
		elif e["speed"] <= 0.75:
			traits.append("slow")
		if e["switches_lanes"]:
			traits.append("switches lanes")
		var weak := PackedStringArray()
		var strong := PackedStringArray()
		for wid in rules.weapons:
			var m := rules.multiplier(wid, id)
			if m > 1.0:
				weak.append(rules.weapons[wid]["name"])
			elif m < 1.0:
				strong.append(rules.weapons[wid]["name"])
		var line := "[color=%s]●[/color] [b]%s[/b] — %s" % [e["color"], e["name"], ", ".join(traits)]
		if not weak.is_empty():
			line += ". Weak to: " + ", ".join(weak)
		if not strong.is_empty():
			line += ". Resists: " + ", ".join(strong)
		lines.append(line)
	lines.append("")
	lines.append("[b]PICKUPS[/b]  (shoot the ice, then touch what's inside)")
	lines.append("+ Heal — restores %d HP" % rules.t("heal_amount"))
	lines.append("● Armour — +%d, absorbs damage first" % rules.t("armor_amount"))
	lines.append("◆ Max HP — +%d (up to %d)" % [rules.t("maxhp_amount"), rules.t("max_hp")])
	lines.append("★ Frenzy — %dx damage for %ds" % [rules.t("frenzy_damage_mult"), rules.t("frenzy_seconds")])
	lines.append("▲ Fire rate — x%.1f for %ds" % [rules.t("speed_buff_rate_mult"), rules.t("speed_buff_seconds")])
	lines.append("")
	lines.append("[b]TOWERS[/b]  (placed where you stand, last %ds)" % rules.towers.values()[0]["duration"])
	for id in rules.towers:
		var t: Dictionary = rules.towers[id]
		var what := ""
		if t["slow_multiplier"] < 1.0:
			what = "slows enemies to %d%% speed" % int(t["slow_multiplier"] * 100)
		elif t["damage_per_sec"] > 0.0:
			what = "burns enemies in range, %d damage per %ds" % [t["damage_per_sec"], rules.t("burn_tick")]
		elif t["poison_duration"] > 0.0:
			what = "poisons, 1 damage every %ds for %ds after leaving" % [rules.t("poison_tick"), t["poison_duration"]]
		lines.append("[color=%s]◆[/color] %s — %s" % [t["color"], t["name"], what])
	return "\n".join(lines)
