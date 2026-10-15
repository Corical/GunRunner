extends CanvasLayer
## In-game HUD: score, distance, weapon, combo, boss bar, HP bar with armour. Same layout as the Babylon
## build (index.html): score top-left, weapon top-right, HP bottom-centre, boss bar top-centre.
## Reads sim state each frame; holds no game state of its own.

const Sim = preload("res://scripts/sim/sim.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _score: Label
var _distance: Label
var _weapon: Label
var _combo: Label
var _boss_box: Control
var _boss_name: Label
var _boss_fill: ColorRect
var _boss_bar_width := 400.0
var _hp_text: Label
var _hp_fill: ColorRect
var _hp_bar_width := 250.0
var _buffs: Label
var _stand_in: Label
var _speed: Label


func build(stand_in_art: bool) -> void:
	layer = 1
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-left: score, then distance (+ speed when not 1x). Menus put "Enemy Guide" below this block.
	var top_left := VBoxContainer.new()
	top_left.add_theme_constant_override("separation", 4)
	root.add_child(top_left)
	var score_pill := UiKit.pill(Color(0, 0, 0, 0.6))
	score_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	top_left.add_child(score_pill)
	_score = UiKit.label("0", 26, Color.WHITE, true)
	score_pill.add_child(_score)
	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 12)
	top_left.add_child(info_row)
	_distance = UiKit.label("0m", 16, Color(1, 1, 1, 0.75))
	info_row.add_child(_distance)
	# Shown whenever the game is not at normal speed, so a saved speed can never be silently fast.
	_speed = UiKit.label("", 16, Color("#FBBF24"), true)
	info_row.add_child(_speed)
	UiKit.pin(top_left, Control.PRESET_TOP_LEFT, 16)

	# Top-right: weapon. Menus put [Pause][Settings] below it.
	var weapon_pill := UiKit.pill(Color(0, 0, 0, 0.6))
	root.add_child(weapon_pill)
	_weapon = UiKit.label("PISTOL", 20, Color("#FBBF24"), true)
	weapon_pill.add_child(_weapon)
	UiKit.pin(weapon_pill, Control.PRESET_TOP_RIGHT, 16)

	# Boss bar sits above the HP bar, not top-centre: the far end of the road at the top of the screen is
	# where the boss and enemies appear, and Babylon's top-centre bar covered them.
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = UiKit.label("BOSS", 18, Color("#FCA5A5"), true)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_name)
	var boss_bar := UiKit.bar(Vector2(_boss_bar_width, 18), Color("#DC2626"))
	_boss_box.add_child(boss_bar[0])
	_boss_fill = boss_bar[1]
	UiKit.pin(_boss_box, Control.PRESET_CENTER_BOTTOM, 20, -96)

	_combo = UiKit.label("x99 COMBO", 34, Color("#FBBF24"), true)
	_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo.add_theme_constant_override("outline_size", 6)
	_combo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(_combo)
	UiKit.pin(_combo, Control.PRESET_CENTER_TOP, 16, 80)
	_combo.text = ""

	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	_buffs = UiKit.label("", 14, Color("#FDE68A"), true)
	_buffs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_buffs)
	_hp_text = UiKit.label("HP 5/5", 16, Color.WHITE, true)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_hp_text)
	var hp_bar := UiKit.bar(Vector2(_hp_bar_width, 16), Color("#22C55E"))
	bottom.add_child(hp_bar[0])
	_hp_fill = hp_bar[1]
	UiKit.pin(bottom, Control.PRESET_CENTER_BOTTOM, 20)

	_stand_in = UiKit.label("STAND-IN ART", 12, Color(1, 1, 1, 0.45))
	_stand_in.visible = stand_in_art
	root.add_child(_stand_in)
	UiKit.pin(_stand_in, Control.PRESET_BOTTOM_LEFT, 16)


func update(s: Sim, speed := 1.0) -> void:
	_score.text = UiKit.thousands(s.score)
	_distance.text = "%dm" % int(s.distance)
	_speed.text = "SPEED %.1fx" % speed if absf(speed - 1.0) > 0.01 else ""
	_weapon.text = String(s.rules.weapons[s.player.weapon_id]["name"]).to_upper()
	_combo.text = "x%d COMBO" % s.combo if s.combo >= 3 else ""
	var p := s.player
	var ratio := clampf(float(p.hp) / p.max_hp, 0.0, 1.0)
	_hp_fill.size.x = (_hp_bar_width - 4.0) * ratio  # 2 px border each side
	_hp_fill.color = Color("#22C55E") if ratio > 0.6 else (Color("#FBBF24") if ratio > 0.3 else Color("#EF4444"))
	_hp_text.text = "HP %d/%d   ARMOUR %d" % [p.hp, p.max_hp, p.armor] if p.armor > 0 else "HP %d/%d" % [p.hp, p.max_hp]
	var buffs := PackedStringArray()
	if p.frenzy_timer > 0.0:
		buffs.append("FRENZY %ds" % ceili(p.frenzy_timer))
	if p.speed_timer > 0.0:
		buffs.append("FIRE RATE %ds" % ceili(p.speed_timer))
	_buffs.text = "   ".join(buffs)
	_boss_box.visible = s.boss.active
	if s.boss.active:
		_boss_name.text = "BOSS WAVE %d" % s.boss.wave
		_boss_fill.size.x = (_boss_bar_width - 4.0) * float(s.boss.hp) / s.boss.max_hp
