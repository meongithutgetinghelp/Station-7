extends Node3D
## Optional discoveries: a stable nightly schedule keeps saves and co-op in agreement.
## Notes stay readable for every player; they never replace required evidence.

const Interaction = preload("res://interactable.gd")
const TEXTURES := [
	preload("res://assets/entity/letter/entity-letter.png"),
	preload("res://assets/entity/letter/note-1.png"),
	preload("res://assets/entity/letter/note-2.png"),
	preload("res://assets/entity/letter/note-3.png"),
	preload("res://assets/entity/letter/note-4.png"),
	preload("res://assets/entity/letter/note-5.png"),
	preload("res://assets/entity/letter/note-6.png"),
	preload("res://assets/entity/letter/note-7.png"),
	preload("res://assets/entity/letter/note-8.png"),
	preload("res://assets/entity/letter/note-9.png"),
]
# Resting on bench ends or counter space, clear of passenger seat centres and basins.
# Each tuple is [texture index, world position, paper yaw in degrees]. No booth props.
const NIGHTS := [
	[[0, Vector3(-12.97, 0.918, 13.92), -12.0]],
	[[1, Vector3(12.03, 0.918, -10.58), 18.0]],
	[[2, Vector3(8.03, 0.918, 6.42), -24.0], [3, Vector3(24.05, 1.162, 4.10), 8.0]],
	[[4, Vector3(-19.35, 0.846, -10.25), 80.0]],
	[[5, Vector3(15.03, 0.918, 13.92), 14.0], [6, Vector3(30.90, 1.262, -5.72), -8.0]],
	[[7, Vector3(5.53, 0.918, -18.90), -19.0]],
	[[8, Vector3(-9.97, 0.918, -4.38), 11.0], [9, Vector3(-3.97, 0.918, 13.92), -16.0]],
]

var reader: CanvasLayer
var current_night := 0


func set_night(number: int) -> void:
	var selected := clampi(number, 1, NIGHTS.size())
	# Jobs are also restored during co-op snapshots. Never interrupt a reader or
	# duplicate the props when restoring the same night.
	if current_night == selected: return
	reader.close_panel()
	current_night = selected
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for entry in NIGHTS[selected - 1]:
		_build_note(int(entry[0]), entry[1], float(entry[2]))


func _build_note(id: int, point: Vector3, yaw: float) -> void:
	var texture: Texture2D = TEXTURES[id]
	var letter := StaticBody3D.new()
	letter.name = "HandwrittenNote_%02d" % id
	letter.add_to_group("handwritten_note")
	letter.set_meta("note_id", id)
	letter.position = point
	letter.rotation_degrees.y = yaw
	letter.collision_layer = 8
	letter.collision_mask = 0
	add_child(letter)
	var target := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.34, 0.035, 0.44)
	target.shape = shape
	letter.add_child(target)
	var artwork := MeshInstance3D.new()
	artwork.name = "LetterArtwork"
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(0.44 * texture.get_width() / float(texture.get_height()), 0.44)
	artwork.mesh = sheet
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	artwork.material_override = material
	letter.add_child(artwork)
	Interaction.attach(letter, _read_note.bind(id, texture), func() -> String: return "[E] Read handwritten note")


func _read_note(id: int, texture: Texture2D) -> void:
	if Coop.active: Coop.request_action("pacing_note", id)
	else:
		var pacing := get_tree().get_first_node_in_group("horror_pacing")
		if pacing: pacing.remember("note/%d" % id)
	reader.read_texture(texture)
