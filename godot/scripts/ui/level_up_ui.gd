extends CanvasLayer
## Level-up screen: three big cards, tap one. The sim is paused for the choice (it waits for a pick), so this
## only has to show the choices and report the index tapped. Keys 1/2/3 also pick (PC).

signal picked(index: int)

const Rules = preload("res://scripts/sim/rules.gd")
const UiKit = preload("res://scripts/ui/ui_kit.gd")

var _rules: Rules
var _root: Control
var _title: Label
var _row: HBoxContainer
var _shown_for := PackedStringArray()


func build(rules: Rules) -> void:
	layer = 6
	_rules = rules
	_root = ColorRect.new()
	(_root as ColorRect).color = Color(0, 0, 0, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 24)
	centre.add_child(col)
	_title = UiKit.label("LEVEL UP!", 56, Color("#FBBF24"), true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 24)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)


## Shows the sim's open choice (level-up perks or boss loot); hides when there is none or `open` is false.
## Safe to call every frame: rebuilds only when the choices change.
func show_choices(sim: Object, open := true) -> void:
	var choices: PackedStringArray = sim.choices if open else PackedStringArray()
	if choices == _shown_for:
		return
	_shown_for = choices.duplicate()
	_root.visible = not choices.is_empty()
	for c in _row.get_children():
		c.queue_free()
	if choices.is_empty():
		return
	var loot: bool = sim.choice_kind == "loot"
	_title.text = "BOSS LOOT - PICK ONE" if loot else "LEVEL %d - PICK ONE" % sim.level
	for i in choices.size():
		var row: Dictionary = sim.choice_card(choices[i])
		var card := Button.new()
		card.custom_minimum_size = Vector2(300, 220)
		card.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#1F2937")
		sb.border_color = Color("#FBBF24")
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(24)
		for state in ["normal", "hover", "pressed"]:
			var s2: StyleBoxFlat = sb.duplicate()
			if state == "hover":
				s2.bg_color = Color("#374151")
			elif state == "pressed":
				s2.bg_color = Color("#4B5563")
			card.add_theme_stylebox_override(state, s2)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 10)
		card.add_child(col)
		var name := UiKit.label(String(row["name"]).to_upper(), 30, Color("#FBBF24"), true)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name)
		var desc := UiKit.label(row["desc"], 22, Color.WHITE)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(260, 0)
		col.add_child(desc)
		var stack_text := UiKit.label("%s   [%d]" % [row["footer"], i + 1], 18, Color(1, 1, 1, 0.6))
		stack_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack_text.custom_minimum_size = Vector2(260, 0)
		stack_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(stack_text)
		card.pressed.connect(func(): picked.emit(i))
		_row.add_child(card)


func is_open() -> bool:
	return _root.visible

