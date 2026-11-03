extends PanelContainer

var title: String = ""
var lines: PackedStringArray
var paper_color: Color = Color(0.91, 0.86, 0.71)
var portrait_profile: Dictionary = {}
var desk_bounds := Rect2(245, 435, 770, 320)
var _dragging: bool = false
var _grab: Vector2


func _ready() -> void:
	custom_minimum_size = Vector2(300, 245)
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = paper_color
	style.border_color = paper_color.darkened(0.4)
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 9)
	add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", Color(0.1, 0.18, 0.18))
	heading.add_theme_font_size_override("font_size", 22)
	column.add_child(heading)
	var rule := ColorRect.new()
	rule.color = Color(0.22, 0.3, 0.27)
	rule.custom_minimum_size.y = 3
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	var text_column := column
	if not portrait_profile.is_empty():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(row)
		var portrait := preload("res://passenger_portrait.gd").new()
		portrait.profile = portrait_profile
		portrait.custom_minimum_size = Vector2(80, 100)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
		text_column = VBoxContainer.new()
		text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text_column)
	for text in lines:
		var line := Label.new()
		line.text = text
		line.add_theme_color_override("font_color", Color(0.13, 0.16, 0.14))
		line.add_theme_font_size_override("font_size", 17)
		text_column.add_child(line)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_grab = get_parent().get_local_mouse_position() - position
			get_parent().move_child(self, get_parent().get_child_count() - 1)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position = (get_parent().get_local_mouse_position() - _grab).clamp(desk_bounds.position, desk_bounds.end - size)
		accept_event()
