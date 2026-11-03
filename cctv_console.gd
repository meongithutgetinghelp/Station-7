extends "res://field_panel.gd"

var feeds: Array = []
var selected: int = 0
var _image: TextureRect
var _target_rotation := Vector3.ZERO
var _origin_rotation := Vector3.ZERO
var _camera_buttons: Array[Button] = []
var _status: Label
var _rec: Label
var _feedback: Label
var _switch_cover: ColorRect
var _switch_tween: Tween
var _elapsed: float = 0
var _previous_disable_3d := false
const CAMERA_NAMES = ["HALL", "CONCOURSE", "PLATFORM", "STAIR ENTRANCE", "KIOSK", "WEST HALL"]

func _ready() -> void:
	layer = 30
	add_to_group("world_modal")
	add_to_group("cctv_monitor")
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_switch_cover = ColorRect.new()
	_switch_cover.color = Color.BLACK
	_switch_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_switch_cover)
	_root = Control.new()
	_root.size = Vector2(1280, 720)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var border := Panel.new()
	border.position = Vector2(18, 18)
	border.size = Vector2(1244, 684)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color.TRANSPARENT
	outline.border_color = Color(0.78, 0.86, 0.79, 0.45)
	outline.set_border_width_all(2)
	border.add_theme_stylebox_override("panel", outline)
	_root.add_child(border)
	heading = _text("", Vector2(38, 35), 30)
	_status = _text("", Vector2(38, 78), 18)
	_rec = _text("● REC", Vector2(1135, 38), 22)
	_rec.modulate = Color(0.94, 0.28, 0.24)
	_text("SECURITY MONITOR", Vector2(900, 335), 24)
	_text("Click a camera on the station map", Vector2(900, 369), 17)
	var map := Panel.new()
	map.name = "CameraMap"
	map.position = Vector2(900, 400)
	map.size = Vector2(355, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.03, 0.88)
	style.border_color = Color(0.7, 0.77, 0.7)
	style.set_border_width_all(1)
	map.add_theme_stylebox_override("panel", style)
	_root.add_child(map)
	for room in [Rect2(20, 15, 285, 42), Rect2(85, 70, 145, 50), Rect2(115, 127, 88, 55), Rect2(135, 193, 48, 45), Rect2(22, 145, 75, 42), Rect2(22, 91, 65, 35)]:
		var area := Panel.new()
		area.position = room.position
		area.size = room.size
		var room_style := StyleBoxFlat.new()
		room_style.bg_color = Color(0.11, 0.14, 0.12)
		room_style.border_color = Color(0.45, 0.5, 0.46)
		room_style.set_border_width_all(2)
		area.add_theme_stylebox_override("panel", room_style)
		map.add_child(area)
	for points in [[Vector2(157, 57), Vector2(157, 70)], [Vector2(157, 120), Vector2(157, 127)], [Vector2(159, 182), Vector2(159, 193)], [Vector2(97, 166), Vector2(115, 166)]]:
		var line := Line2D.new()
		line.points = PackedVector2Array(points)
		line.width = 3
		line.default_color = Color(0.5, 0.56, 0.51)
		map.add_child(line)
	var positions := [Vector2(127, 140), Vector2(124, 80), Vector2(135, 22), Vector2(128, 200), Vector2(27, 151), Vector2(24, 94)]
	for i in range(6):
		var button := Button.new()
		button.name = "CameraButton%d" % (i + 1)
		button.text = "CAM %02d" % (i + 1)
		button.position = positions[i]
		button.size = Vector2(68, 30)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_feed.bind(i))
		map.add_child(button)
		_camera_buttons.append(button)
	var you := Label.new()
	you.text = "● YOU"
	you.position = Vector2(250, 85)
	you.modulate = Color(0.65, 0.96, 0.65)
	map.add_child(you)
	_text("1–6 switch camera   •   Right-drag / arrows pan", Vector2(38, 598), 18)
	_feedback = _text("", Vector2(38, 508), 18)
	var evidence := Button.new()
	evidence.text = "REVIEW / IDENTIFY INTRUDER"
	evidence.position = Vector2(38, 545)
	evidence.size = Vector2(300, 38)
	evidence.pressed.connect(_review_evidence)
	_root.add_child(evidence)
	var mark := Button.new()
	mark.text = "REPORT SUSPICIOUS ACTIVITY"
	mark.position = Vector2(38, 635)
	mark.size = Vector2(340, 42)
	mark.pressed.connect(mark_suspicious)
	_root.add_child(mark)
	close_button = Button.new()
	close_button.text = "▼  LOWER MONITOR  [TAB]"
	close_button.position = Vector2(430, 665)
	close_button.size = Vector2(400, 38)
	close_button.pressed.connect(close_panel)
	_root.add_child(close_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

func _text(value: String, point: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.9, 0.96, 0.9))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(label)
	return label

func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	_image.position = Vector2.ZERO
	_image.size = screen
	_switch_cover.size = screen
	var factor := minf(screen.x / 1280, screen.y / 720)
	_root.scale = Vector2.ONE * factor
	_root.position = (screen - Vector2(1280, 720) * factor) * 0.5

func open_panel() -> void:
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	feeds = jobs._camera_screens
	if feeds.is_empty(): return
	if not is_open:
		_previous_disable_3d = get_viewport().disable_3d
	super.open_panel()
	# Opaque full-screen monitor covers the world; only its SubViewport needs rendering.
	get_viewport().disable_3d = true
	select_feed(selected)

func select_feed(index: int) -> void:
	if feeds.is_empty(): return
	for entry in feeds:
		entry.viewport.size = Vector2i(256, 144)
		entry.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	selected = clampi(index, 0, feeds.size() - 1)
	_image.texture = feeds[selected].viewport.get_texture()
	feeds[selected].viewport.size = Vector2i(1024, 576)
	feeds[selected].viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera: Camera3D = feeds[selected].camera
	_origin_rotation = camera.get_meta("home_rotation", camera.rotation)
	_target_rotation = camera.rotation
	feeds[selected].refresh_in = 0.0
	heading.text = "CAM %02d  /  %s" % [selected + 1, CAMERA_NAMES[selected]]
	for i in range(_camera_buttons.size()):
		_camera_buttons[i].disabled = i >= feeds.size()
		_camera_buttons[i].modulate = Color(0.5, 1, 0.58) if i == selected else Color(0.78, 0.81, 0.78)
	if _switch_tween and _switch_tween.is_running(): _switch_tween.kill()
	_switch_cover.modulate.a = 1
	_switch_tween = create_tween()
	_switch_tween.tween_property(_switch_cover, "modulate:a", 0.0, 0.18)

func _input(event: InputEvent) -> void:
	super._input(event)
	if not is_open: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode <= KEY_6:
		select_feed(int(event.keycode) - int(KEY_1))
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		pan(-event.relative.x * 0.003, -event.relative.y * 0.003)

func pan(yaw: float, pitch: float) -> void:
	_target_rotation.y = clampf(_target_rotation.y + yaw, _origin_rotation.y - 1.5, _origin_rotation.y + 1.5)
	_target_rotation.x = clampf(_target_rotation.x + pitch, deg_to_rad(-75), deg_to_rad(15))

func _process(delta: float) -> void:
	if not is_open or feeds.is_empty(): return
	_elapsed += delta
	_rec.visible = GameManager.powered and not feeds[selected].get("signal_lost", false) and fmod(_elapsed, 1.2) < 0.8
	_status.text = "LIVE  •  " + GameManager.clock_text() if GameManager.powered else "SIGNAL LOST  /  STATION POWER OFFLINE"
	_image.modulate = Color(0.83, 0.96, 0.86) if GameManager.powered else Color.BLACK
	if feeds[selected].get("signal_lost", false) and GameManager.powered:
		_status.text = "SIGNAL LOST / CAM 04 LINE RESET AT SECURITY"
		_image.modulate = Color.BLACK
	if not GameManager.powered or feeds[selected].get("signal_lost", false):
		feeds[selected].viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# StationJobs schedules only the selected feed at a bounded refresh rate.
	pan((float(Input.is_physical_key_pressed(KEY_LEFT)) - float(Input.is_physical_key_pressed(KEY_RIGHT))) * delta, (float(Input.is_physical_key_pressed(KEY_UP)) - float(Input.is_physical_key_pressed(KEY_DOWN))) * delta)
	var camera: Camera3D = feeds[selected].camera
	camera.rotation.x = lerp_angle(camera.rotation.x, _target_rotation.x, 1 - exp(-delta * 10))
	camera.rotation.y = lerp_angle(camera.rotation.y, _target_rotation.y, 1 - exp(-delta * 10))

func mark_suspicious() -> void:
	if Coop.is_client():
		Coop.request_action("cctv", {"feed": selected, "rotation": feeds[selected].camera.rotation})
		return
	if not GameManager.powered or (not feeds.is_empty() and feeds[selected].get("signal_lost", false)):
		_feedback.text = "CAMERA OFFLINE  /  RESTORE POWER FIRST"
		return
	if feeds.is_empty(): return
	var camera: Camera3D = feeds[selected].camera
	var pacing := get_tree().get_first_node_in_group("horror_pacing")
	if pacing:
		var recorded: String = pacing.report_sighting(selected, camera)
		if not recorded.is_empty():
			_feedback.text = recorded
			return
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if not actor.profile.get("anomaly", false) or camera.is_position_behind(actor.global_position): continue
		var point: Vector2 = camera.unproject_position(actor.global_position + Vector3.UP)
		if Rect2(Vector2.ZERO, Vector2(feeds[selected].viewport.size)).has_point(point) and _line_clear(camera.global_position, actor.global_position + Vector3.UP):
			if GameManager.reward_once("cctv/" + str(actor.profile.uid), 5):
				_feedback.text = "ANOMALY RECORDED IN INCIDENT LOG"
				GameManager.notice_posted.emit("Camera anomaly recorded in the incident log.")
			else: _feedback.text = "THIS INCIDENT HAS ALREADY BEEN RECORDED"
			return
	_feedback.text = "NO NEW VERIFIABLE ANOMALY IN THIS VIEW"
	GameManager.notice_posted.emit("No new verifiable anomaly in this view.")

func _review_evidence() -> void:
	if Coop.is_client():
		Coop.request_action("identify")
		return
	get_tree().get_first_node_in_group("station_jobs")._identify()
	if GameManager.entity_identified: _feedback.text = "IDENTITY CONFIRMED  /  USE SUSTAINED FLASHLIGHT TO COUNTER"

func _line_clear(from: Vector3, to: Vector3) -> bool:
	if from.distance_to(to) > 30: return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = preload("res://collision_layers.gd").SOLID
	var excluded: Array[RID] = []
	var world := get_viewport().get_world_3d()
	for layer in range(6):
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty(): return true
		var transparent := false
		for mesh in hit.collider.find_children("*", "MeshInstance3D", true, false):
			var material: Material = mesh.material_override
			if material is StandardMaterial3D and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: transparent = true
		if not transparent: return false
		excluded.append(hit.rid)
		query.exclude = excluded
	return false

func close_panel() -> void:
	if is_open: get_viewport().disable_3d = _previous_disable_3d
	for entry in feeds:
		if is_instance_valid(entry.viewport):
			entry.viewport.size = Vector2i(256, 144)
			entry.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	super.close_panel()


func _exit_tree() -> void:
	if is_open: get_viewport().disable_3d = _previous_disable_3d
