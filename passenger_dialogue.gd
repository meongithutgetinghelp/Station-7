extends "res://field_panel.gd"
## Subtitles and responses over the live scene, inspired by the supplied reference.
var director: Node
var target_uid := ""
var event_token := 0
var event_kind := ""
var speaker := ""
var step := 0
var subtitle: RichTextLabel
var responses: VBoxContainer

func _ready() -> void:
	layer = 25
	add_to_group("world_modal")
	_root = Control.new()
	_root.size = Vector2(900, 720)
	_root.theme = StationStyle.theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	subtitle = RichTextLabel.new()
	subtitle.position = Vector2(80, 494)
	subtitle.size = Vector2(740, 95)
	subtitle.bbcode_enabled = true
	subtitle.scroll_active = false
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Times New Roman", "serif"])
	subtitle.add_theme_font_override("normal_font", font)
	subtitle.add_theme_font_size_override("normal_font_size", 25)
	subtitle.add_theme_color_override("font_shadow_color", Color.BLACK)
	subtitle.add_theme_constant_override("shadow_offset_x", 2)
	subtitle.add_theme_constant_override("shadow_offset_y", 2)
	_root.add_child(subtitle)
	responses = VBoxContainer.new()
	responses.position = Vector2(130, 590)
	responses.size = Vector2(640, 110)
	_root.add_child(responses)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false

func talk(uid: String, token: int, kind: String, name_text: String) -> void:
	target_uid = uid
	event_token = token
	event_kind = kind
	speaker = name_text
	step = 0
	_show_step()
	open_panel()

func _show_step() -> void:
	for child in responses.get_children():
		responses.remove_child(child)
		child.queue_free()
	var line: String
	var choices: Array[String]
	if event_kind == "lost_property":
		match step:
			0:
				line = "Excuse me. I can't find my bag. I had it when I came in."
				choices = ["Where did you last have it?", "I'll come back in a moment."]
			1:
				line = "I put it down when I sat here. A small brown bag... I thought someone had taken it."
				choices = ["Check beside your seat, underneath the bench.", "Give me a moment."]
			_:
				line = "Oh! There it is. It slipped underneath. Thank you. I was starting to panic."
				choices = ["Keep it with you. Your train is still coming."]
	else:
		match step:
			0:
				line = "Could you help me? I don't feel safe waiting here on my own."
				choices = ["What's wrong?", "I'll come back in a moment."]
			1:
				line = "Someone keeps watching me from the end of the platform. Could you walk me somewhere with staff?"
				choices = ["Follow me to the ticket booth or Security.", "Stay here. I'll come back."]
			_:
				line = "Thank you. I'll stay close. Please don't leave me behind."
				choices = ["Let's go."]
	subtitle.clear()
	subtitle.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.push_color(Color("e5b64e"))
	subtitle.add_text(speaker + ": ")
	subtitle.pop()
	subtitle.push_color(Color("f4f1e7"))
	subtitle.add_text(line)
	subtitle.pop()
	subtitle.pop()
	for index in range(choices.size()):
		var button := Button.new()
		button.text = choices[index]
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_font_override("font", subtitle.get_theme_font("normal_font"))
		button.add_theme_color_override("font_shadow_color", Color.BLACK)
		button.add_theme_constant_override("shadow_offset_x", 2)
		button.add_theme_constant_override("shadow_offset_y", 2)
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color.TRANSPARENT
		focus.border_width_bottom = 1
		focus.border_color = Color("e5b64e")
		button.add_theme_stylebox_override("focus", focus)
		button.pressed.connect(_choose.bind(index))
		responses.add_child(button)
	close_button = responses.get_child(0)
	if is_open: close_button.grab_focus()

func _choose(index: int) -> void:
	if index > 0:
		close_panel()
		return
	if step < 2:
		step += 1
		_show_step()
	else:
		if Coop.active:
			Coop.request_action("passenger_dialogue", {"uid": target_uid, "token": event_token})
		else:
			director.finish_dialogue(target_uid, event_token, 1)
		close_panel()
