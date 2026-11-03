extends Control

const Appearance = preload("res://passenger_appearance.gd")

var profile: Dictionary = {}:
	set(value):
		profile = value
		queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var angle: float = TAU * i / 40.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(320, 280))
	draw_rect(Rect2(0, 0, 320, 280), Color(0.24, 0.29, 0.29))
	draw_rect(Rect2(12, 12, 296, 256), Color(0.32, 0.39, 0.38))
	draw_rect(Rect2(25, 25, 270, 160), Color(0.38, 0.44, 0.42))
	if profile.is_empty():
		return
	var appearance := Appearance.describe(profile)
	var skin: Color = profile.skin
	var hair: Color = profile.hair
	var coat: Color = profile.coat
	var ink := Color(0.10, 0.12, 0.12)
	# Palette, hair silhouette and glasses match the station passenger.
	_ellipse(Vector2(160, 290), Vector2(115, 85), coat.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(72, 280), Vector2(96, 222), Vector2(132, 204), Vector2(160, 243), Vector2(188, 204), Vector2(225, 222), Vector2(248, 280)]), coat)
	draw_rect(Rect2(139, 184, 42, 48), skin.darkened(0.12))
	draw_colored_polygon(PackedVector2Array([Vector2(131, 207), Vector2(160, 233), Vector2(148, 260), Vector2(116, 221)]), appearance.shirt)
	draw_colored_polygon(PackedVector2Array([Vector2(189, 207), Vector2(160, 233), Vector2(172, 260), Vector2(204, 221)]), appearance.shirt)
	_ellipse(Vector2(100, 130), Vector2(12, 22), skin.darkened(0.06))
	_ellipse(Vector2(220, 130), Vector2(12, 22), skin.darkened(0.06))
	_ellipse(Vector2(160, 129), Vector2(60 * float(appearance.face_width), 79), skin)
	_ellipse(Vector2(160, 64), Vector2(66, 35), hair)
	draw_colored_polygon(PackedVector2Array([Vector2(97, 68), Vector2(110, 119), Vector2(124, 78), Vector2(171, 89), Vector2(203, 69), Vector2(220, 115), Vector2(223, 61)]), hair)
	if int(appearance.hair_style) == 1:
		_ellipse(Vector2(133, 61), Vector2(42, 28), hair)
	elif int(appearance.hair_style) == 2:
		_ellipse(Vector2(218, 127), Vector2(18, 61), hair)
		_ellipse(Vector2(102, 127), Vector2(16, 61), hair)
	elif int(appearance.hair_style) == 3:
		_ellipse(Vector2(219, 65), Vector2(22, 25), hair)
	for x in [136.0, 184.0]:
		_ellipse(Vector2(x, 127), Vector2(12, 7), Color(0.94, 0.91, 0.81))
		_ellipse(Vector2(x + 1, 127), Vector2(4, 5), ink)
		draw_line(Vector2(x - 11, 112), Vector2(x + 10, 110), hair, 4, true)
	draw_line(Vector2(161, 133), Vector2(155, 155), skin.darkened(0.22), 3, true)
	draw_line(Vector2(155, 155), Vector2(166, 156), skin.darkened(0.22), 2, true)
	draw_line(Vector2(142, 177), Vector2(177, 177), Color(0.4, 0.20, 0.17), 3, true)
	draw_line(Vector2(150, 181), Vector2(170, 181), skin.darkened(0.14), 2, true)
	if appearance.glasses:
		for x in [136.0, 184.0]:
			draw_rect(Rect2(x - 19, 115, 38, 24), ink, false, 3)
		draw_line(Vector2(155, 125), Vector2(165, 125), ink, 3)
