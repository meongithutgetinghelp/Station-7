extends CanvasLayer

const StationStyle = preload("res://ui/station_skin.gd")

var is_open: bool = false
var heading: Label
var body: VBoxContainer
var _root: Control
var close_button: Button
var _return_focus: Control


func _ready() -> void:
	layer = 25
	add_to_group("world_modal")
	StationStyle.backdrop(self)
	_root = Control.new()
	_root.theme = StationStyle.theme()
	_root.size = Vector2(900, 720)
	add_child(_root)
	var panel := PanelContainer.new()
	panel.position = Vector2(100, 55)
	panel.custom_minimum_size = Vector2(700, 590)
	var style := StationStyle.surface()
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	panel.add_child(column)
	heading = Label.new()
	heading.add_theme_color_override("font_color", StationStyle.AMBER)
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	close_button = Button.new()
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.text = "Return / Tab"
	close_button.pressed.connect(close_panel)
	column.add_child(close_button)
	StationStyle.animate_button(close_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var factor: float = minf(1.15, minf(screen.x / 900, screen.y / 720))
	_root.scale = Vector2.ONE * factor
	_root.position = (screen - Vector2(900, 720) * factor) * 0.5


func paragraph(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 620
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	body.add_child(label)
	return label


func clear_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()


func open_panel() -> void:
	# In co-op the shared world is not paused. Ordinary shortcuts must not
	# replace the death/shift report and strand its retry controls.
	if GameManager.state in [GameManager.NightState.DEAD, GameManager.NightState.SHIFT_OVER] and get_tree().get_first_node_in_group("station_jobs") and not is_in_group("shift_report"):
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	get_tree().call_group("world_modal", "close_panel")
	is_open = true
	visible = true
	StationStyle.reveal(_root)
	close_button.grab_focus()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.in_booth_inspection = true
		player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if is_instance_valid(_return_focus): _return_focus.grab_focus()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.in_booth_inspection = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		close_panel()
		get_viewport().set_input_as_handled()
