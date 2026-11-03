extends CanvasLayer

const Cases = preload("res://passenger_cases.gd")
const Document = preload("res://inspection_document.gd")
const Portrait = preload("res://passenger_portrait.gd")

var director: Node
var is_open: bool = false
var decision_locked: bool = false
var _canvas: Control
var _portrait: Control
var _dialogue: Label
var _name: Label
var _clock: Label
var _feedback: Label
var _progress: Label
var _approve: Button
var _deny: Button
var _next: Button
var _papers: Control
var _stamp: Label
var _camera_status: Label


func _ready() -> void:
	layer = 20
	add_to_group("ticket_inspection_ui")
	add_to_group("world_modal")
	var background := ColorRect.new()
	background.color = Color(0.025, 0.035, 0.035)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_canvas = Control.new()
	_canvas.size = Vector2(1280, 800)
	add_child(_canvas)
	_panel(Rect2(0, 0, 1280, 425), Color(0.17, 0.23, 0.23), Color(0.09, 0.13, 0.13), 0)
	_panel(Rect2(0, 425, 1280, 375), Color(0.27, 0.23, 0.18), Color(0.09, 0.12, 0.11), 5)
	_panel(Rect2(324, 26, 632, 314), Color(0.11, 0.16, 0.17), Color(0.06, 0.09, 0.1), 8)
	_portrait = Portrait.new()
	_portrait.position = Vector2(440, 40)
	_portrait.size = Vector2(400, 280)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_portrait)
	_name = _label("", Rect2(345, 305, 590, 32), 20, Color(0.92, 0.89, 0.77))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel(Rect2(225, 350, 830, 65), Color(0.07, 0.10, 0.10), Color(0.4, 0.47, 0.42), 2)
	_dialogue = _label("", Rect2(245, 363, 790, 48), 21, Color(0.94, 0.92, 0.83))
	_label("STATION 7\nTICKET OFFICE", Rect2(30, 45, 255, 90), 28, Color(0.91, 0.88, 0.74))
	_label("NIGHT %d / DESK 01\nCompare both documents.\nYour decision controls entry." % GameManager.night, Rect2(30, 180, 255, 120), 20, Color(0.71, 0.78, 0.71))
	_clock = _label("", Rect2(995, 55, 260, 90), 26, Color(0.92, 0.86, 0.62))
	_progress = _label("", Rect2(995, 180, 260, 100), 20, Color(0.81, 0.87, 0.79))
	_camera_status = _label("", Rect2(995, 285, 260, 50), 17, Color(0.74, 0.86, 0.77))
	_panel(Rect2(22, 448, 208, 304), Color(0.83, 0.80, 0.66), Color(0.11, 0.16, 0.14), 4)
	_label("NIGHT %d RULES" % GameManager.night, Rect2(38, 465, 176, 30), 20, Color(0.14, 0.19, 0.16))
	_label("1. Names, IDs and\ngender must match.\n\n2. Valid today:\n" + Cases.service_date(GameManager.night) + "\n\n3. " + Cases.LINE + "\n" + Cases.DESTINATION + "\n\n4. Issue stamp present.\n\n5. Person appears\non the camera.", Rect2(38, 505, 176, 240), 14, Color(0.16, 0.18, 0.15))
	_papers = Control.new()
	_papers.size = Vector2(1280, 800)
	_papers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_papers)
	_approve = _button("APPROVE ENTRY", Rect2(1035, 458, 220, 54), Color(0.22, 0.43, 0.31), func() -> void: _submit(true))
	_deny = _button("DENY ENTRY", Rect2(1035, 526, 220, 54), Color(0.53, 0.25, 0.22), func() -> void: _submit(false))
	_feedback = _label("", Rect2(1035, 596, 220, 100), 16, Color(0.94, 0.90, 0.77))
	_next = _button("NEXT PASSENGER", Rect2(1035, 704, 220, 38), Color(0.29, 0.37, 0.34), _next_passenger)
	_button("Leave desk [Tab]", Rect2(1035, 753, 220, 32), Color(0.20, 0.26, 0.25), close_desk)
	_button("Investigate civil ID", Rect2(25, 350, 190, 42), Color(0.20, 0.31, 0.29), _investigate)
	_stamp = _label("", Rect2(455, 737, 550, 35), 26, Color(0.86, 0.78, 0.6))
	_label("Drag documents to compare · Tab leave desk · Esc pause", Rect2(25, 775, 900, 22), 15, Color(0.81, 0.80, 0.69))
	get_viewport().size_changed.connect(_layout)
	GameManager.clock_changed.connect(_refresh_status)
	GameManager.power_changed.connect(_power_changed)
	_layout()
	visible = false


func _panel(rect: Rect2, color: Color, border: Color, thickness: int) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(thickness)
	panel.add_theme_stylebox_override("panel", style)
	_canvas.add_child(panel)
	return panel


func _label(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label


func _button(text: String, rect: Rect2, color: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.12) if state == "hover" else (color.darkened(0.4) if state == "disabled" else color)
		style.border_color = Color(0.08, 0.11, 0.1)
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	_canvas.add_child(button)
	return button


func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / 1280.0, viewport_size.y / 800.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (viewport_size - Vector2(1280, 800) * factor) * 0.5


func open_desk() -> void:
	var operator := get_tree().get_first_node_in_group("player")
	var desk := get_tree().get_first_node_in_group("booth_desk")
	if desk and operator and not operator.get_meta("seated_workstation", false):
		get_tree().get_first_node_in_group("station_services").sit_at_desk()
		return
	is_open = true
	visible = desk == null
	decision_locked = false
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.in_booth_inspection = true
		player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if desk else Input.MOUSE_MODE_VISIBLE
	var profile: Dictionary = director.current_profile()
	if not profile.is_empty():
		_show_passenger(profile)
	else:
		_show_waiting()
	_refresh_status()


func close_desk() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	var desk := get_tree().get_first_node_in_group("booth_desk")
	if desk:
		desk.exit_computer(true)
		desk.put_down()
		desk.cancel_stamp()
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.in_booth_inspection = false
	var services := get_tree().get_first_node_in_group("station_services")
	if services: services.stand_from_desk()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED


func close_panel() -> void:
	close_desk()


func _input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		var desk := get_tree().get_first_node_in_group("booth_desk")
		if desk and desk.computer_active: desk.exit_computer()
		else: close_desk()
		get_viewport().set_input_as_handled()


func passenger_arrived(profile: Dictionary) -> void:
	if not decision_locked:
		_show_passenger(profile)
	_refresh_status()


func _investigate() -> void:
	var services := get_tree().get_first_node_in_group("station_services")
	if services:
		close_desk()
		services.open_registry()
		services.investigate_current()


func _clear_papers() -> void:
	for child in _papers.get_children():
		_papers.remove_child(child)
		child.queue_free()


func _show_passenger(profile: Dictionary) -> void:
	decision_locked = false
	_clear_papers()
	_portrait.profile = profile
	_camera_status.text = "WINDOW CAMERA\n" + ("NO SUBJECT DETECTED" if profile.get("anomaly", false) else "SUBJECT PRESENT")
	_name.text = profile.name
	_dialogue.text = profile.greeting
	_feedback.text = "Compare the names, ID numbers, date and route before deciding."
	_stamp.text = ""
	var ticket := Document.new()
	ticket.title = "STATION 7 / RAIL TICKET"
	ticket.lines = PackedStringArray([
		"No. " + profile.ticket_number,
		"NAME  " + profile.ticket_name,
		"ID  " + profile.ticket_id_number,
		"GENDER  " + str(profile.get("ticket_gender", "—")) + (" / VIP" if profile.get("vip", false) else ""),
		"DATE  " + profile.date,
		profile.line + " / " + profile.destination,
		"ISSUE STAMP: " + ("STATION 7" if profile.stamped else "—"),
	])
	ticket.position = Vector2(270, 448)
	_papers.add_child(ticket)
	var identity := Document.new()
	identity.title = "IDENTITY CARD"
	identity.paper_color = Color(0.75, 0.84, 0.79)
	identity.portrait_profile = profile
	identity.lines = PackedStringArray(["HOLDER", profile.id_name, "GENDER  " + str(profile.get("gender", "—")), "ID NUMBER", profile.id_number])
	identity.position = Vector2(625, 448)
	_papers.add_child(identity)
	_refresh_status()


func _show_waiting() -> void:
	_clear_papers()
	_portrait.profile = {}
	_name.text = "SERVICE WINDOW"
	_dialogue.text = "All passengers processed. Thank you for your shift." if director.reviewed >= director.total_cases() else "Waiting for the next passenger to reach the window..."
	_feedback.text = "Correct decisions: %d / %d" % [director.correct, director.reviewed]
	_stamp.text = ""


func _submit(approve: bool) -> void:
	if decision_locked:
		return
	if Coop.active:
		Coop.request_action("ticket", {"uid": director.current_profile().get("uid", ""), "approve": approve})
		return
	var result: Dictionary = director.decide(approve)
	show_network_decision(result)


func show_network_decision(result: Dictionary) -> void:
	var approve: bool = bool(result.get("approved", false))
	if result.is_empty():
		_feedback.text = "Entry cannot be approved while the gate readers are offline." if not GameManager.powered else "Wait for the passenger at the window."
		return
	var desk := get_tree().get_first_node_in_group("booth_desk")
	if desk: desk._decision_recorded(result)
	decision_locked = true
	_stamp.text = "APPROVED" if approve else "DENIED"
	_stamp.modulate = Color(0.62, 0.87, 0.65) if approve else Color(0.95, 0.62, 0.54)
	var reasons := PackedStringArray(result.errors)
	if result.correct:
		_feedback.text = "CORRECT\n" + ("Documents match the rules." if approve else "\n".join(reasons))
	else:
		_feedback.text = "MISTAKE\n" + ("\n".join(reasons) if approve else "These documents were valid.")
	if GameManager.night == 1:
		GameManager.notice_posted.emit(_feedback.text)
	_dialogue.text = "Thank you. I'll go through the gate." if approve else "Understood. I'll return to the entrance."
	_refresh_status()


func _next_passenger() -> void:
	var profile: Dictionary = director.current_profile()
	if not profile.is_empty():
		_show_passenger(profile)


func _power_changed(_powered: bool) -> void:
	_refresh_status()


func _refresh_status() -> void:
	_clock.text = GameManager.clock_text() + "\n" + Cases.service_date(GameManager.night)
	_progress.text = "PROCESSED  %d / %d\nCORRECT  %d\nARRIVAL GROUPS %d / %d" % [director.reviewed, director.total_cases(), director.correct, director.round_number + 1, director.round_limit]
	_approve.disabled = decision_locked or not director.counter_ready or not GameManager.powered
	_deny.disabled = decision_locked or not director.counter_ready
	_next.disabled = not decision_locked or not director.counter_ready
	_next.text = "ALL CASES COMPLETE" if director.reviewed >= director.total_cases() else ("NEXT PASSENGER" if director.counter_ready else "WAITING FOR PASSENGER")
