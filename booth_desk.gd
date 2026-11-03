extends Node3D
## Physical, first-person inspection. Document handling is local; verdicts use the director.
const Registry = preload("res://identity_registry.gd")
const Interaction = preload("res://interactable.gd")
const SCREEN_LAYER := 1 << 16
var director: Node
var ui: CanvasLayer
var documents: Dictionary = {}
var held_kind := ""
var held: MeshInstance3D
var sliding := false
var stamping := false
var _returning := false
var _stamp_tween: Tween
var _stamp_models: Array[Node3D] = []
var _stamp_starts: Array[Vector3] = []
var shown_uid := ""
var _profile: Dictionary = {}
var _station: Node3D
var _slide_tweens: Array[Tween] = []
var _hold_tween: Tween
var _slide_epoch := 0
var _screen: SubViewport
var _feed: SubViewport
var _record: Label
var _status: Label
var _feedback: Label
var _feed_image: TextureRect
const MONITOR_INTERVAL := 1.0 / 15.0
var _monitor_elapsed := MONITOR_INTERVAL
var _equipment_was_visible := true
var _equipment_hidden := false
var computer_active := false
var _computer_returning := false
var _computer_tween: Tween
var _computer_rest := Transform3D.IDENTITY
var _computer_fov := 70.0
var _stamp_camera_tween: Tween
var _stamp_camera_rest := Transform3D.IDENTITY
var _stamp_view_active := false
var _stamp_view_returning := false

func _ready() -> void:
	add_to_group("booth_desk")
	_station = get_parent()
	director = _station.get_node("PassengerService")
	ui = director.ui
	# The old catch-all console would intercept rays to the separate papers.
	_station.get_node("TB_InspectionConsole").collision_layer = 0
	_build_monitor()
	_build_stamps()
	Interaction.attach(_station.get_node("TB_Keyboard"), verify_record, _computer_prompt)
	director.passenger_ready.connect(present_documents)
	director.decision_recorded.connect(_decision_recorded)
	GameManager.night_started.connect(func(_night: int) -> void: clear_documents())
	GameManager.shift_finished.connect(clear_documents)
	GameManager.player_died.connect(clear_documents)
	GameManager.checkpoint_loading.connect(clear_documents)

func _staff_can_handle() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return not GameManager.loading and player != null and player.global_position.x < -7.125 and player.global_position.z > 1 and player.global_position.z < 7 and GameManager.signed_in and GameManager.state in [GameManager.NightState.WORKING, GameManager.NightState.BLACKOUT]

func _process(delta: float) -> void:
	var profile: Dictionary = director.current_profile()
	if not sliding and not stamping:
		if not profile.is_empty() and str(profile.uid) != shown_uid:
			present_documents(profile)
		elif profile.is_empty() and not shown_uid.is_empty():
			return_documents()
	if held_kind != "" and (not ui.is_open or not _staff_can_handle()): put_down()
	var player := get_tree().get_first_node_in_group("player")
	var nearby: bool = player != null and player.global_position.distance_to(Vector3(-8, 1.4, 5)) < 5
	var screen_visible: bool = nearby and not get_viewport().disable_3d and player.camera.is_position_in_frustum(get_node("BoothComputerScreen").global_position)
	_monitor_elapsed += delta
	_screen.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not screen_visible or _monitor_elapsed < MONITOR_INTERVAL: return
	_monitor_elapsed = 0
	_screen.render_target_update_mode = SubViewport.UPDATE_ONCE
	_feed.render_target_update_mode = SubViewport.UPDATE_ONCE if GameManager.powered else SubViewport.UPDATE_DISABLED
	_feed_image.visible = GameManager.powered
	_status.text = "STATION 7 / STAFF WORKSTATION\n" + preload("res://passenger_cases.gd").service_date(GameManager.night) + " / " + preload("res://passenger_cases.gd").DESTINATION
	if not GameManager.powered: _status.text = "POWER OFF — APPROVAL UNAVAILABLE"
	_feedback.text = ui._feedback.text + ("\n\n[Tab / Esc] Return to desk" if computer_active else "\n\n[E] Pick up papers · Use Computer\n[R] Put paper down · [Tab] Leave desk")

func _input(event: InputEvent) -> void:
	if computer_active and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_E,KEY_TAB,KEY_ESCAPE]:
		exit_computer()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused or not ui.is_open or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and not held_kind.is_empty():
		put_down()
		get_viewport().set_input_as_handled()

func _viewport(size_px: Vector2i) -> SubViewport:
	var view := SubViewport.new()
	view.size = size_px
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	return view

func _text(parent: Node, text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", preload("res://ui/fonts/SpecialElite.ttf"))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _quad(texture: Texture2D, dimensions: Vector2, layer: int = 1) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = dimensions
	visual.mesh = quad
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.no_depth_test = layer == 4
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = material
	visual.layers = layer
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual

func _document_texture(kind: String, profile: Dictionary) -> SubViewport:
	var view := _viewport(Vector2i(720, 480))
	var paper := ColorRect.new()
	paper.color = Color("ded3ad") if kind == "ticket" else Color("cfdbcb")
	paper.size = Vector2(720, 480)
	view.add_child(paper)
	var ink := Color("202b29")
	_text(view, "STATION 7 / RAIL TICKET" if kind == "ticket" else "PASSPORT / IDENTITY", Rect2(24, 18, 672, 44), 34, ink)
	if kind == "ticket":
		var text := "No. %s\nNAME  %s\nID  %s\nGENDER  %s%s\nDATE  %s\n%s / %s\nISSUE STAMP: %s" % [profile.ticket_number, profile.ticket_name, profile.ticket_id_number, str(profile.get("ticket_gender", "—")), " / VIP" if profile.get("vip", false) else "", profile.date, profile.line, profile.destination, "STATION 7" if profile.stamped else "—"]
		_text(view, text, Rect2(24, 90, 672, 365), 29, ink)
	else:
		var portrait := preload("res://passenger_portrait.gd").new()
		portrait.profile = profile
		portrait.position = Vector2(25, 95)
		portrait.size = Vector2(190, 255)
		view.add_child(portrait)
		_text(view, "HOLDER\n%s\n\nGENDER  %s\nID NUMBER\n%s" % [profile.id_name, str(profile.get("gender", "—")), profile.id_number], Rect2(245, 90, 450, 345), 31, ink)
	return view

func present_documents(profile: Dictionary) -> void:
	if profile.is_empty() or sliding or str(profile.uid) == shown_uid: return
	if not shown_uid.is_empty():
		return_documents()
		return
	shown_uid = str(profile.uid)
	_profile = profile.duplicate(true)
	_record.text = "CIVIL REGISTRY\n\nUse the screen or keyboard to verify the passport number and ticket ownership.\n\nCompare the person at the window with the live camera."
	ui._show_passenger(profile)
	sliding = true
	_slide_epoch += 1
	var epoch := _slide_epoch
	for kind in ["ticket", "passport"]:
		var view := _document_texture(kind, profile)
		var body := StaticBody3D.new()
		body.name = "Presented_" + kind
		body.collision_layer = 0
		body.collision_mask = 0
		body.add_to_group("booth_desk_local")
		add_child(body)
		var z: float = 3.86 if kind == "ticket" else 4.14
		body.position = Vector3(-6.76, 1.438, z)
		var visual := _quad(view.get_texture(), Vector2(0.25, 0.167))
		visual.rotation = Vector3(-PI * 0.5, -PI * 0.5, 0)
		body.add_child(visual)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.30, 0.035, 0.22)
		collision.shape = shape
		body.add_child(collision)
		var rest := Vector3(-7.68, 1.235, z)
		documents[kind] = {"body": body, "visual": visual, "viewport": view, "rest": rest}
		Interaction.attach(body, pick_up.bind(kind), func() -> String: return "[E] Pick up " + kind if not sliding and _staff_can_handle() else "")
		var tween := create_tween()
		_slide_tweens.append(tween)
		tween.tween_interval(0.12 if kind == "passport" else 0.0)
		tween.tween_property(body, "position", Vector3(-7.24, 1.438, z), 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(body, "position", rest, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if kind == "passport":
			tween.tween_callback(func() -> void:
				if epoch != _slide_epoch: return
				sliding = false
				for entry in documents.values(): entry.body.collision_layer = 8)

func pick_up(kind: String) -> void:
	exit_computer(true)
	if sliding or stamping or not documents.has(kind) or not _staff_can_handle(): return
	if not ui.is_open: ui.open_desk()
	put_down()
	var player := get_tree().get_first_node_in_group("player")
	if player.camera.has_node("Equipment"):
		var equipment: Node3D = player.camera.get_node("Equipment")
		_equipment_was_visible = equipment.visible
		_equipment_hidden = true
		equipment.hide()
	held_kind = kind
	var entry: Dictionary = documents[kind]
	entry.visual.hide()
	held = _quad(entry.viewport.get_texture(), Vector2(0.59, 0.393), 4)
	player.camera.add_child(held)
	var document_hands := preload("res://first_person_hands.gd").new(true)
	held.add_child(document_hands)
	document_hands.set_pose("reach", true)
	held.position = Vector3(-0.13, -0.55, -0.72)
	held.rotation_degrees.z = 4
	_hold_tween = create_tween()
	_hold_tween.tween_property(held, "position", Vector3(-0.13, -0.19, -0.72), 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hold_tween.tween_callback(func() -> void:
		if is_instance_valid(document_hands): document_hands.set_pose("document"))

func put_down() -> void:
	if _hold_tween and _hold_tween.is_valid(): _hold_tween.kill()
	if is_instance_valid(held):
		held.get_parent().remove_child(held)
		held.queue_free()
	held = null
	if documents.has(held_kind): documents[held_kind].visual.show()
	held_kind = ""
	if _equipment_hidden:
		var player := get_tree().get_first_node_in_group("player")
		if player and player.camera.has_node("Equipment"): player.camera.get_node("Equipment").visible = _equipment_was_visible
		_equipment_hidden = false

func _decision_recorded(result: Dictionary) -> void:
	if str(result.get("uid", "")) != shown_uid: return
	_ink_ticket(bool(result.get("approved", false)))
	if not stamping: return_documents()

func return_documents() -> void:
	if shown_uid.is_empty() or _returning: return
	_returning = true
	put_down()
	for tween in _slide_tweens:
		if tween.is_valid(): tween.kill()
	_slide_tweens.clear()
	sliding = true
	_slide_epoch += 1
	var epoch := _slide_epoch
	for kind in documents:
		var entry: Dictionary = documents[kind]
		entry.body.collision_layer = 0
		var tween := create_tween()
		_slide_tweens.append(tween)
		tween.tween_interval(0.10 if kind == "passport" else 0.0)
		tween.tween_property(entry.body, "position", Vector3(-7.24, 1.438, entry.rest.z), 0.28)
		tween.tween_property(entry.body, "position", Vector3(-6.76, 1.438, entry.rest.z), 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if kind == "passport": tween.tween_callback(func() -> void:
			if epoch == _slide_epoch: clear_documents())

func clear_documents() -> void:
	exit_computer(true)
	cancel_stamp()
	_returning = false
	_slide_epoch += 1
	put_down()
	for tween in _slide_tweens:
		if tween.is_valid(): tween.kill()
	_slide_tweens.clear()
	for entry in documents.values():
		entry.body.queue_free()
		entry.viewport.queue_free()
	documents.clear()
	shown_uid = ""
	_profile.clear()
	sliding = false
	if is_instance_valid(_record): _record.text = "CIVIL REGISTRY\nWaiting for passenger documents."

func verify_record() -> void:
	if not _staff_can_handle(): return
	use_computer()
	if not GameManager.powered or _profile.is_empty(): return
	if director.current_profile().get("uid", "") != shown_uid: return
	var equipment := _equipment()
	_record.text = "CIVIL REGISTRY\n" + str(_profile.id_number) + "\n\n" + str(Registry.investigate(_profile).text)

func _build_monitor() -> void:
	var monitor := _station.get_node("TB_Monitor")
	monitor.position += Vector3(0.15, 0.10, 0.12)
	_station.get_node("TB_Monitor_Stand").position += Vector3(0.15, 0, 0.12)
	var pivot: Vector3 = monitor.position
	var angle := deg_to_rad(-38)
	for name_text in ["TB_Monitor", "TB_Monitor_Stand", "TB_Keyboard"]:
		var part: Node3D = _station.get_node(name_text)
		part.position = pivot + Basis(Vector3.UP, angle) * (part.position - pivot)
		part.rotation.y += angle
	monitor.get_child(0).mesh.size = Vector3(0.06, 0.62, 0.86)
	monitor.get_child(1).shape.size = Vector3(0.06, 0.62, 0.86)
	var stand := _station.get_node("TB_Monitor_Stand")
	stand.get_child(0).mesh.size = Vector3(0.12, 0.18, 0.12)
	stand.get_child(1).shape.size = Vector3(0.12, 0.18, 0.12)
	stand.position.y = 1.29
	_screen = _viewport(Vector2i(800, 540))
	var background := ColorRect.new()
	background.size = Vector2(800, 540)
	background.color = Color("102521")
	_screen.add_child(background)
	_status = _text(_screen, "", Rect2(18, 12, 764, 80), 29, Color("c5dbb7"))
	_feed = SubViewport.new()
	_feed.size = Vector2i(320, 220)
	_feed.world_3d = get_world_3d()
	_feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_feed.positional_shadow_atlas_size = 0
	add_child(_feed)
	var camera := Camera3D.new()
	_feed.add_child(camera)
	camera.position = Vector3(-6.65, 2.15, 4)
	camera.look_at(Vector3(-5.85, 1.3, 4))
	camera.cull_mask = 1
	camera.current = true
	_feed_image = TextureRect.new()
	_feed_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_feed_image.texture = _feed.get_texture()
	_feed_image.position = Vector2(18, 110)
	_feed_image.size = Vector2(330, 225)
	_screen.add_child(_feed_image)
	_record = _text(_screen, "CIVIL REGISTRY\nWaiting for passenger documents.", Rect2(370, 110, 412, 250), 24, Color("d1dfcd"))
	_feedback = _text(_screen, "", Rect2(18, 368, 764, 165), 24, Color("e3dbb7"))
	var surface := _quad(_screen.get_texture(), Vector2(0.78, 0.54), SCREEN_LAYER)
	surface.name = "BoothComputerScreen"
	add_child(surface)
	surface.rotation.y = -PI * 0.5 + angle
	surface.position = monitor.position + surface.basis.z * 0.038
	var target := StaticBody3D.new()
	target.name = "BoothScreenInteraction"
	target.transform = surface.transform
	target.collision_layer = 8
	target.collision_mask = 0
	target.add_to_group("booth_desk_local")
	target.add_to_group("booth_computer_screen")
	add_child(target)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.78, 0.54, 0.016)
	shape.shape = box
	target.add_child(shape)
	Interaction.attach(target, verify_record, _computer_prompt)

func _build_stamps() -> void:
	# Move the decorative phone to the rear worktop; use the existing stamp side of the desk.
	_station.get_node("TB_PhoneBase").position = Vector3(-13.1, 1.295, 6.35)
	_station.get_node("TB_PhoneHandset").position = Vector3(-13.1, 1.36, 6.35)
	for approved in [true, false]:
		var color := Color("315c45") if approved else Color("803329")
		var prefix := "TB_ApproveStamp" if approved else "TB_Stamp"
		var point := Vector3(-7.73, 1.25, 3.0 if approved else 3.36)
		if approved:
			var paint := StandardMaterial3D.new()
			paint.albedo_color = color
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color("6a4930")
			_station._booth_prop(prefix + "Pad", Vector3(0.18, 0.025, 0.25), point + Vector3(-0.05, -0.023, 0), paint)
			_station._booth_prop(prefix + "Base", Vector3(0.10, 0.025, 0.15), point, paint)
			_station._booth_prop(prefix + "Handle", Vector3(0.06, 0.10, 0.06), point + Vector3(0, 0.062, 0), wood)
		var target := StaticBody3D.new()
		target.name = "BoothStampApprove" if approved else "BoothStampDeny"
		target.position = point
		target.collision_layer = 8
		target.collision_mask = 0
		target.add_to_group("booth_desk_local")
		_station.add_child(target)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.20, 0.20, 0.23)
		shape.shape = box
		shape.position.y = 0.045
		target.add_child(shape)
		var model := Node3D.new()
		model.name = "StampMotion"
		target.add_child(model)
		for suffix in ["Base", "Handle"]:
			_station.get_node(prefix + suffix).reparent(model, true)
		_stamp_models.append(model)
		_stamp_starts.append(model.global_position)
		Interaction.attach(target, stamp_ticket.bind(approved), func() -> String:
			return "[E] Stamp ticket " + ("APPROVED" if approved else "DENIED") if _staff_can_handle() and not sliding and not stamping else "")

func stamp_ticket(approved: bool) -> void:
	exit_computer(true)
	if not _staff_can_handle() or sliding or stamping or not documents.has("ticket"): return
	if director.current_profile().get("uid", "") != shown_uid: return
	if approved and not GameManager.powered:
		GameManager.notice_posted.emit("Approval waits for power to the gate readers.")
		return
	put_down()
	stamping = true
	var uid := shown_uid
	var model: Node3D = _stamp_models[0 if approved else 1]
	var equipment := _equipment()
	if equipment: equipment.play_hand_action("stamp", model, documents.ticket.body, 0.90)
	var start: Vector3 = model.global_position
	var paper: Vector3 = documents.ticket.body.global_position
	_lean_to_stamp(start,paper)
	_stamp_tween = create_tween()
	_stamp_tween.tween_property(model, "global_position", start + Vector3.UP * 0.18, 0.12)
	_stamp_tween.tween_property(model, "global_position", paper + Vector3.UP * 0.18, 0.20).set_trans(Tween.TRANS_SINE)
	_stamp_tween.tween_property(model, "global_position", paper + Vector3.UP * 0.014, 0.08)
	_stamp_tween.tween_callback(func() -> void:
		if shown_uid == uid and director.current_profile().get("uid", "") == uid and _staff_can_handle():
			ui._submit(approved))
	_stamp_tween.tween_property(model, "global_position", paper + Vector3.UP * 0.18, 0.12)
	_stamp_tween.tween_property(model, "global_position", start, 0.24).set_trans(Tween.TRANS_SINE)
	_stamp_tween.tween_callback(func() -> void:
		stamping = false
		_restore_stamp_view()
		if director.current_profile().get("uid", "") != shown_uid: return_documents())

func cancel_stamp() -> void:
	_restore_stamp_view(true)
	var equipment := _equipment()
	if equipment: equipment.cancel_hand_action()
	if _stamp_tween and _stamp_tween.is_valid(): _stamp_tween.kill()
	for index in range(_stamp_models.size()):
		if is_instance_valid(_stamp_models[index]): _stamp_models[index].global_position = _stamp_starts[index]
	stamping = false

func _ink_ticket(approved: bool) -> void:
	if not documents.has("ticket"): return
	var view: SubViewport = documents.ticket.viewport
	if view.has_node("VerdictStamp"): return
	var mark := PanelContainer.new()
	mark.name = "VerdictStamp"
	mark.position = Vector2(450, 378)
	mark.size = Vector2(245, 65)
	mark.rotation = -0.10
	var ink := Color("285e3c") if approved else Color("8b3026")
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = ink
	style.set_border_width_all(3)
	mark.add_theme_stylebox_override("panel", style)
	view.add_child(mark)
	var label := Label.new()
	label.text = "APPROVED" if approved else "DENIED"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", preload("res://ui/fonts/SpecialElite.ttf"))
	label.add_theme_font_size_override("font_size", 33)
	label.add_theme_color_override("font_color", ink)
	mark.add_child(label)
	view.render_target_update_mode = SubViewport.UPDATE_ONCE


func _equipment() -> Node3D:
	var player := get_tree().get_first_node_in_group("player")
	return player.camera.get_node_or_null("Equipment") if player else null


func use_computer() -> void:
	if computer_active or not _staff_can_handle() or stamping: return
	_restore_stamp_view(true)
	if not ui.is_open: ui.open_desk()
	if _computer_returning: exit_computer(true)
	put_down()
	var player := get_tree().get_first_node_in_group("player")
	var camera: Camera3D = player.camera
	if _computer_tween and _computer_tween.is_valid(): _computer_tween.kill()
	_computer_rest = camera.transform
	_computer_fov = camera.fov
	computer_active = true
	player.set_meta("computer_focus",true)
	var screen: Node3D = get_node("BoothComputerScreen")
	var position: Vector3 = screen.global_position + screen.global_basis.z * 0.72 - Vector3.UP * 0.07
	var target := Transform3D(Basis.IDENTITY,position).looking_at(screen.global_position,Vector3.UP)
	_computer_tween = create_tween().set_parallel(true)
	_computer_tween.tween_property(camera,"global_transform",target,0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_computer_tween.tween_property(camera,"fov",50.0,0.28)
	var equipment := _equipment()
	if equipment: equipment.play_hand_action("keyboard",_station.get_node("TB_Keyboard"),null,3600)

func exit_computer(immediate: bool = false) -> void:
	if not computer_active and not _computer_returning: return
	computer_active = false
	_computer_returning = not immediate
	if _computer_tween and _computer_tween.is_valid(): _computer_tween.kill()
	var player := get_tree().get_first_node_in_group("player")
	if not player: return
	player.set_meta("computer_focus",false)
	if immediate:
		player.camera.transform = _computer_rest
		player.camera.fov = _computer_fov
	else:
		_computer_tween = create_tween().set_parallel(true)
		_computer_tween.tween_property(player.camera,"transform",_computer_rest,0.24).set_trans(Tween.TRANS_SINE)
		_computer_tween.tween_property(player.camera,"fov",_computer_fov,0.24)
		_computer_tween.finished.connect(func() -> void: _computer_returning = false)
	var equipment := _equipment()
	if equipment: equipment.cancel_hand_action()
	player.set_flashlight(player.is_flashlight_on,false)


func _computer_prompt() -> String:
	if not _staff_can_handle(): return ""
	return "[Tab] Return to desk" if computer_active else "[E] Use Computer"


func _lean_to_stamp(start: Vector3, paper: Vector3) -> void:
	if _stamp_view_returning: _restore_stamp_view(true)
	if not ui.is_open: ui.open_desk()
	var player := get_tree().get_first_node_in_group("player")
	_stamp_camera_rest = player.camera.transform
	_stamp_view_active = true
	player.set_meta("desk_action_focus",true)
	var focus := start.lerp(paper,0.65)
	var outside: Vector3 = player.camera.global_position-focus
	outside.y = 0
	outside = outside.normalized()
	var at: Vector3 = focus+outside*0.55+Vector3.UP*0.48
	var target := Transform3D(Basis.IDENTITY,at).looking_at(paper+Vector3.UP*0.10,Vector3.UP)
	_stamp_camera_tween = create_tween()
	_stamp_camera_tween.tween_property(player.camera,"global_transform",target,0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _restore_stamp_view(immediate: bool = false) -> void:
	if not _stamp_view_active and not _stamp_view_returning: return
	_stamp_view_active = false
	_stamp_view_returning = not immediate
	if _stamp_camera_tween and _stamp_camera_tween.is_valid(): _stamp_camera_tween.kill()
	var player := get_tree().get_first_node_in_group("player")
	if not player: return
	player.set_meta("desk_action_focus",false)
	if immediate: player.camera.transform = _stamp_camera_rest
	else:
		_stamp_camera_tween = create_tween()
		_stamp_camera_tween.tween_property(player.camera,"transform",_stamp_camera_rest,0.22).set_trans(Tween.TRANS_SINE)
		_stamp_camera_tween.finished.connect(func() -> void: _stamp_view_returning = false)
