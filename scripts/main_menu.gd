extends Control

var _lobby: CanvasLayer
var _members: Label
var _address: LineEdit
var _port: SpinBox
var _host_button: Button
var _join_button: Button
var _ready_button: Button
var _start_button: Button
var _load_button: Button
var _leave_button: Button
var _menu_canvas: Control

const MENU_ART := {
	"Host Game": "res://ui/menu/host_game.png",
	"Join Game": "res://ui/menu/join_game.png",
	"Settings": "res://ui/menu/settings.png",
	"Credits": "res://ui/menu/credits.png",
	"Quit": "res://ui/menu/quit.png",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = not Coop.active
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var background := ColorRect.new()
	background.color = Color(0.018, 0.022, 0.021)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_menu_canvas = Control.new()
	_menu_canvas.name = "MenuArtwork"
	_menu_canvas.size = Vector2(1920, 1080)
	add_child(_menu_canvas)
	var backdrop := TextureRect.new()
	backdrop.texture = preload("res://ui/menu/title_reference.png")
	backdrop.size = Vector2(1920, 1080)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://ui/menu/title_backdrop.gdshader")
	backdrop.material = material
	_menu_canvas.add_child(backdrop)
	_build_drawing_area()
	var column := VBoxContainer.new()
	column.name = "MenuButtons"
	column.position = Vector2(56, 310)
	column.custom_minimum_size.x = 480
	column.add_theme_constant_override("separation", 24)
	_menu_canvas.add_child(column)
	_menu_button(column, "Host Game", func() -> void: _open_lobby(true))
	_menu_button(column, "Join Game", func() -> void: _open_lobby(false))
	_build_lobby()
	var settings := preload("res://scripts/pause_menu.gd").new()
	settings.is_main_menu = true
	add_child(settings)
	_menu_button(column, "Settings", func() -> void: settings.set_paused(true))
	var credits := preload("res://scripts/field_panel.gd").new()
	add_child(credits)
	credits.heading.text = "STATION 7 / CREDITS"
	credits.paragraph("Design and direction: Station 7\n\nMade with Godot Engine.\n\nCurrent characters, props and audio are prototype assets.\n\nThank you for playing.")
	_menu_button(column, "Credits", credits.open_panel)
	_menu_button(column, "Quit", func() -> void: get_tree().quit())
	get_viewport().size_changed.connect(_layout_artwork)
	_layout_artwork()
	# Also supports automated smoke checks of the exported station scene.
	if "--new-game" in OS.get_cmdline_user_args(): call_deferred("_new_game")


func _build_drawing_area() -> void:
	var area := Control.new()
	area.name = "RightDrawing"
	area.position = Vector2(880, 0)
	area.size = Vector2(1040, 1080)
	area.clip_contents = true
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_canvas.add_child(area)
	var fade := ShaderMaterial.new()
	fade.shader = preload("res://ui/menu/artwork_fade.gdshader")
	var shade := ColorRect.new()
	shade.color = Color(0.055, 0.065, 0.060)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.material = fade
	area.add_child(shade)
	var drawing := TextureRect.new()
	drawing.name = "Illustration"
	drawing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawing.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drawing.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawing.material = fade
	var artwork_path := "res://ui/menu/right_drawing.png"
	if ResourceLoader.exists(artwork_path): drawing.texture = load(artwork_path)
	drawing.visible = drawing.texture != null
	area.add_child(drawing)


func _layout_artwork() -> void:
	var screen := get_viewport_rect().size
	var factor := minf(screen.x / 1920.0, screen.y / 1080.0)
	_menu_canvas.scale = Vector2.ONE * factor
	_menu_canvas.position = (screen - Vector2(1920, 1080) * factor) * 0.5


func _menu_button(parent: Node, label: String, action: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.name = label.replace(" ", "")
	button.texture_normal = load(MENU_ART[label])
	var ink := ShaderMaterial.new()
	ink.shader = preload("res://ui/menu/white_ink.gdshader")
	button.material = ink
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = Vector2(480, 120)
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = label
	var refresh := func() -> void:
		button.self_modulate = Color(0.7, 0.7, 0.67) if button.button_pressed else (Color(1.0, 0.94, 0.79) if button.is_hovered() or button.has_focus() else Color.WHITE)
	button.mouse_entered.connect(refresh)
	button.mouse_exited.connect(refresh)
	button.focus_entered.connect(refresh)
	button.focus_exited.connect(refresh)
	button.button_down.connect(refresh)
	button.button_up.connect(refresh)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _new_game() -> void:
	if Coop.active: Coop.leave()
	get_tree().paused = false
	GameManager.new_campaign()
	get_tree().change_scene_to_file("res://scenes/station_builder.tscn")


func _continue_game() -> void:
	var saved := GameManager.read_checkpoint()
	if saved.is_empty():
		GameManager.notice_posted.emit("No readable checkpoint found. Start a new campaign.")
		return
	get_tree().paused = false
	GameManager.night = int(saved.core.night)
	GameManager.pending_load = true
	get_tree().change_scene_to_file("res://scenes/station_builder.tscn")


func _build_lobby() -> void:
	_lobby = preload("res://scripts/field_panel.gd").new()
	_lobby.name = "CoopLobby"
	add_child(_lobby)
	_lobby.heading.text = "STATION 7 / CO-OP — UP TO 4 STAFF"
	_lobby.paragraph("Host a new or saved campaign. Teammates join by LAN/direct IP.\nInternet connections require the host's UDP port to be reachable.\nThe lobby locks when a shift starts; the host owns the save.")
	_address = LineEdit.new()
	_address.placeholder_text = "Host IP address"
	_address.text = "127.0.0.1"
	_lobby.body.add_child(_address)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Coop.DEFAULT_PORT
	_port.prefix = "UDP port: "
	_lobby.body.add_child(_port)
	_host_button = _button(_lobby.body, "Create lobby", func() -> void: Coop.host(int(_port.value)))
	_join_button = _button(_lobby.body, "Connect to host", func() -> void: Coop.join(_address.text, int(_port.value)))
	_members = _lobby.paragraph("")
	_ready_button = _button(_lobby.body, "Ready / Not ready", func() -> void:
		var id := multiplayer.get_unique_id()
		if Coop.roster.has(id): Coop.set_ready(not Coop.roster[id].ready))
	_start_button = _button(_lobby.body, "Start new campaign", func() -> void: Coop.start_shift())
	_load_button = _button(_lobby.body, "Load host's saved campaign", func() -> void: Coop.start_shift(true))
	_leave_button = _button(_lobby.body, "Leave lobby", func() -> void: Coop.leave("Left lobby."))
	Coop.lobby_changed.connect(_refresh_lobby)
	Coop.status_changed.connect(func(_message: String) -> void: _refresh_lobby())
	_refresh_lobby()


func _open_lobby(hosting: bool) -> void:
	_host_button.visible = hosting
	_join_button.visible = not hosting
	_address.visible = not hosting
	_refresh_lobby()
	_lobby.open_panel()


func _refresh_lobby() -> void:
	if not is_instance_valid(_members): return
	var lines := PackedStringArray([Coop.status])
	var ids := Coop.roster.keys()
	ids.sort()
	for index in range(Coop.MAX_PLAYERS):
		if index >= ids.size(): lines.append("Slot %d — empty" % (index + 1))
		else:
			var id: int = ids[index]
			lines.append("Staff %d%s — %s" % [index + 1, " (host)" if id == 1 else "", "READY" if Coop.roster[id].ready else "not ready"])
	_members.text = "\n".join(lines)
	_host_button.disabled = Coop.active
	_join_button.disabled = Coop.active
	_port.editable = not Coop.active
	_address.editable = not Coop.active
	_ready_button.visible = Coop.active and not Coop.roster.is_empty()
	_start_button.visible = Coop.active and not Coop.is_client()
	_load_button.visible = _start_button.visible
	_start_button.disabled = not Coop.can_start()
	_load_button.disabled = not Coop.can_start() or GameManager.read_checkpoint().is_empty()
	_leave_button.visible = Coop.active
