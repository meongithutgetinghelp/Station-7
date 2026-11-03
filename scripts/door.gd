class_name InteractiveDoor
extends Node3D

const InteractionComponent = preload("res://scripts/interactable.gd")
const MechanicalAudio = preload("res://scripts/mechanical_audio.gd")
const Layers = preload("res://scripts/collision_layers.gd")

## Interactive animated swinging door for Station 7.
## Place this node at the HINGE position of the door.
## is_east_facing = false → door leaf extends along +X (for N/S walls)
## is_east_facing = true  → door leaf extends along +Z (for E/W walls)

@export var door_name: String = "Door"
@export var door_width: float = 1.14
@export var door_height: float = 2.34
@export var door_thickness: float = 0.08
@export var open_angle_deg: float = 90.0
@export var swing_speed: float = 0.4
@export var is_open: bool = false
@export var is_east_facing: bool = false
## Mirror the leaf so it extends the opposite way from the hinge (for double doors).
@export var hinge_flip: bool = false
## Clear glass leaf in a slim steel frame with a push bar, instead of the wooden door.
@export var glass_style: bool = false
## Painted steel service door with protective plates and electrical warnings.
@export var steel_style: bool = false
## Steel CCTV/security leaf with a reinforced observation window.
@export var security_style: bool = false
@export var locked: bool = false
@export var requires_power: bool = false
var powered: bool = true
var jammed: bool = false
var _blocked: bool = false

var interact_prompt: String = "[E] Open door"
var done: bool = false   # always re-interactable

var _anim_body: AnimatableBody3D
var _tween: Tween
var _open_sound: AudioStreamWAV
var _close_sound: AudioStreamWAV

signal door_toggled(opened: bool)


func _ready() -> void:
	add_to_group("save_participant")
	_build_door()
	InteractionComponent.attach(self, interact, _get_prompt)


func _build_door() -> void:
	# The AnimatableBody3D is the thing that rotates.
	# Hinge is at this node's origin; door leaf extends away from it.
	_anim_body = AnimatableBody3D.new()
	_anim_body.name = "DoorBody"
	_anim_body.sync_to_physics = false
	_anim_body.collision_layer = Layers.MOVING_DOORS
	_anim_body.collision_mask  = Layers.ACTORS

	# ── Door material ──────────────────────────────────────────────────────────
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.20, 0.14)   # dark transit wood
	mat.roughness    = 0.55
	# NO transparency flag — solid by default

	# ── Handle material ────────────────────────────────────────────────────────
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.85, 0.75, 0.35)
	handle_mat.metallic     = 0.8
	handle_mat.roughness    = 0.25

	if security_style:
		_build_security_leaf()
	elif steel_style:
		_build_steel_leaf()
	elif glass_style:
		_build_glass_leaf()
	elif not is_east_facing:
		# Door leaf along +X
		var m: float = -1.0 if hinge_flip else 1.0
		var size := Vector3(door_width, door_height, door_thickness)
		var offset := Vector3(door_width * 0.5 * m, door_height * 0.5, 0.0)
		_add_door_mesh(size, offset, mat)
		_add_collision(size, offset)
		# Handle
		for hz in [-0.04, 0.04]:
			_add_handle(Vector3(0.12, 0.025, 0.03),
				Vector3((door_width - 0.12) * m, 1.05, hz), handle_mat)
	else:
		# Door leaf along +Z
		var size := Vector3(door_thickness, door_height, door_width)
		var offset := Vector3(0.0, door_height * 0.5, door_width * 0.5)
		_add_door_mesh(size, offset, mat)
		_add_collision(size, offset)
		# Handle
		for hx in [-0.04, 0.04]:
			_add_handle(Vector3(0.03, 0.025, 0.12),
				Vector3(hx, 1.05, door_width - 0.12), handle_mat)

	add_child(_anim_body)

	# Tag so player raycast can reach the controller
	_anim_body.add_to_group("interactive_doors")
	_anim_body.set_meta("door_controller", self)

	# Soft positional latch and body sounds, cached for this door.
	_open_sound = MechanicalAudio.door_action(true, steel_style or security_style)
	_close_sound = MechanicalAudio.door_action(false, steel_style or security_style)
	var snd := AudioStreamPlayer3D.new()
	snd.name         = "DoorSound"
	snd.bus = "SFX"
	snd.volume_db    = -9.0
	snd.unit_size    = 2.5
	snd.max_distance = 12.0
	add_child(snd)


# ── Glass door leaf ───────────────────────────────────────────────────────────

func _leaf_size(u: float, y: float, t: float) -> Vector3:
	return Vector3(u, y, t) if not is_east_facing else Vector3(t, y, u)


func _leaf_off(u: float, y: float, t: float = 0.0) -> Vector3:
	return Vector3(u, y, t) if not is_east_facing else Vector3(t, y, u)


func _add_box_mesh(size: Vector3, offset: Vector3, mat: StandardMaterial3D, casts_shadow: bool = true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = offset
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_anim_body.add_child(mi)


func _build_glass_leaf() -> void:
	var m: float = -1.0 if hinge_flip else 1.0
	var w: float = door_width
	var h: float = door_height
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.65, 0.85, 1.0, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.2
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.2, 0.22, 0.26)
	frame.metallic = 0.6
	frame.roughness = 0.35
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.8, 0.82, 0.86)
	steel.metallic = 0.9
	steel.roughness = 0.25

	_add_collision(_leaf_size(w, h, door_thickness), _leaf_off(w * 0.5 * m, h * 0.5))
	# Inset the pane into the surrounding frame rather than exposing its edges.
	_add_box_mesh(_leaf_size(w - 0.12, h - 0.22, 0.025), _leaf_off(w * 0.5 * m, h * 0.5 + 0.03), glass, false)
	# frame: bottom rail, top rail, hinge stile, latch stile
	_add_box_mesh(_leaf_size(w - 0.12, 0.14, 0.06), _leaf_off(w * 0.5 * m, 0.07), frame)
	_add_box_mesh(_leaf_size(w - 0.12, 0.08, 0.06), _leaf_off(w * 0.5 * m, h - 0.04), frame)
	_add_box_mesh(_leaf_size(0.06, h, 0.06), _leaf_off(0.03 * m, h * 0.5), frame)
	_add_box_mesh(_leaf_size(0.06, h, 0.06), _leaf_off((w - 0.03) * m, h * 0.5), frame)
	# push bar on both sides
	for t in [-0.07, 0.07]:
		_add_box_mesh(_leaf_size(w - 0.5, 0.04, 0.04), _leaf_off(w * 0.5 * m, 1.0, t), steel)
		for su in [0.25, w - 0.25]:
			_add_box_mesh(_leaf_size(0.04, 0.04, 0.07), _leaf_off(su * m, 1.0, t * 0.5), steel)


func _build_steel_leaf() -> void:
	var m: float = -1.0 if hinge_flip else 1.0
	var w: float = door_width
	var h: float = door_height
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.76, 0.82, 0.79)
	paint.metallic = 0.2 # Painted steel, rather than a polished metal surface.
	paint.roughness = 0.48
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.61, 0.62)
	steel.metallic = 0.85
	steel.roughness = 0.32
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.13, 0.14)
	dark.metallic = 0.65
	dark.roughness = 0.4
	var warning := StandardMaterial3D.new()
	warning.albedo_color = Color(1.0, 0.76, 0.12)
	warning.roughness = 0.6
	_add_door_mesh(_leaf_size(w, h, door_thickness), _leaf_off(w * 0.5 * m, h * 0.5), paint)
	_add_collision(_leaf_size(w, h, door_thickness), _leaf_off(w * 0.5 * m, h * 0.5))
	for side in [-1.0, 1.0]:
		var t: float = side * (door_thickness * 0.5 + 0.008)
		# Stainless kick plate and a recessed louvred ventilation grille.
		_add_box_mesh(_leaf_size(w - 0.06, 0.25, 0.012), _leaf_off(w * 0.5 * m, 0.15, t), steel)
		_add_box_mesh(_leaf_size(w * 0.64, 0.3, 0.012), _leaf_off(w * 0.5 * m, 0.64, t), dark)
		for row in range(5):
			_add_box_mesh(_leaf_size(w * 0.6, 0.025, 0.025), _leaf_off(w * 0.5 * m, 0.53 + row * 0.055, t + side * 0.012), steel)
		# Lever latch, escutcheon, lock and overhead closer housing.
		_add_box_mesh(_leaf_size(0.09, 0.23, 0.018), _leaf_off((w - 0.13) * m, 1.03, t), steel)
		_add_box_mesh(_leaf_size(0.18, 0.035, 0.04), _leaf_off((w - 0.2) * m, 1.06, t + side * 0.035), dark)
		_add_box_mesh(_leaf_size(0.025, 0.04, 0.025), _leaf_off((w - 0.13) * m, 0.97, t + side * 0.015), dark)
		_add_box_mesh(_leaf_size(0.28, 0.09, 0.06), _leaf_off(0.22 * m, h - 0.12, t), steel)
		# Non-emissive warning plate remains readable by flashlight before repair.
		_add_box_mesh(_leaf_size(w * 0.74, 0.4, 0.015), _leaf_off(w * 0.5 * m, 1.65, t), warning)
		var sign := Label3D.new()
		sign.name = "ElectricalWarning_" + ("Front" if side > 0.0 else "Back")
		sign.text = "DANGER\nELECTRICAL ROOM\nAUTHORIZED STAFF ONLY"
		sign.font_size = 28
		sign.pixel_size = 0.0018
		sign.modulate = Color(0.04, 0.05, 0.05)
		sign.outline_size = 0
		sign.no_depth_test = false
		sign.shaded = true
		sign.position = _leaf_off(w * 0.5 * m, 1.65, t + side * 0.012)
		sign.rotation_degrees.y = (90.0 if side > 0.0 else -90.0) if is_east_facing else (0.0 if side > 0.0 else 180.0)
		_anim_body.add_child(sign)
	# Three visible hinge blocks on the steel leaf's hinge edge.
	for y in [0.25, h * 0.5, h - 0.25]:
		_add_box_mesh(_leaf_size(0.055, 0.13, door_thickness + 0.035), _leaf_off(0.025 * m, y), steel)


func _build_security_leaf() -> void:
	var m := -1.0 if hinge_flip else 1.0
	var w := door_width
	var h := door_height
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.20, 0.27, 0.27)
	paint.metallic = 0.3
	paint.roughness = 0.72
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.46, 0.51, 0.50)
	steel.metallic = 0.75
	steel.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.055, 0.075, 0.075)
	dark.roughness = 0.8
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.25, 0.38, 0.33, 0.32)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.25
	var aperture_width := w * 0.43
	var aperture_height := 0.47
	var window_y := 1.76
	var bottom := window_y - aperture_height * 0.5
	var top := window_y + aperture_height * 0.5
	var stile := (w - aperture_width) * 0.5
	# Four panels leave an actual aperture, not a pane pasted onto a solid leaf.
	_add_box_mesh(_leaf_size(w, bottom, door_thickness), _leaf_off(w * 0.5 * m, bottom * 0.5), paint)
	_add_box_mesh(_leaf_size(w, h - top, door_thickness), _leaf_off(w * 0.5 * m, (h + top) * 0.5), paint)
	for u in [stile * 0.5, w - stile * 0.5]:
		_add_box_mesh(_leaf_size(stile, aperture_height, door_thickness), _leaf_off(u * m, window_y), paint)
	_add_collision(_leaf_size(w, h, door_thickness), _leaf_off(w * 0.5 * m, h * 0.5))
	_add_box_mesh(_leaf_size(aperture_width, aperture_height, 0.018), _leaf_off(w * 0.5 * m, window_y), glass, false)
	_anim_body.get_child(-1).name = "SecurityWindow"
	for side in [-1.0, 1.0]:
		var t: float = side * (door_thickness * 0.5 + 0.008)
		for y in [bottom, top]:
			_add_box_mesh(_leaf_size(aperture_width + 0.045, 0.026, 0.025), _leaf_off(w * 0.5 * m, y, t), steel)
		for u in [stile, w - stile]:
			_add_box_mesh(_leaf_size(0.026, aperture_height, 0.025), _leaf_off(u * m, window_y, t), steel)
		for i in range(1, 6):
			_add_box_mesh(_leaf_size(0.004, aperture_height - 0.03, 0.004), _leaf_off((stile + aperture_width * i / 6.0) * m, window_y, side * 0.016), steel, false)
		for i in range(1, 5):
			_add_box_mesh(_leaf_size(aperture_width - 0.03, 0.004, 0.004), _leaf_off(w * 0.5 * m, bottom + aperture_height * i / 5.0, side * 0.016), steel, false)
		_add_box_mesh(_leaf_size(w - 0.09, 0.30, 0.015), _leaf_off(w * 0.5 * m, 0.18, t), steel)
		_add_box_mesh(_leaf_size(0.10, 0.25, 0.018), _leaf_off((w - 0.14) * m, 1.02, t), steel)
		_add_box_mesh(_leaf_size(0.20, 0.035, 0.045), _leaf_off((w - 0.22) * m, 1.06, t + side * 0.035), dark)
		_add_box_mesh(_leaf_size(0.035, 0.045, 0.025), _leaf_off((w - 0.14) * m, 0.96, t + side * 0.018), dark)
		_add_box_mesh(_leaf_size(0.32, 0.08, 0.065), _leaf_off(0.23 * m, h - 0.14, t), steel)
		_add_box_mesh(_leaf_size(w * 0.76, 0.27, 0.014), _leaf_off(w * 0.5 * m, 1.31, t), dark)
		var sign := Label3D.new()
		sign.name = "SecuritySign_" + ("Front" if side > 0 else "Back")
		sign.text = "CCTV / SECURITY\nSTAFF ONLY"
		sign.font = preload("res://ui/fonts/SpecialElite.ttf")
		sign.font_size = 32
		sign.pixel_size = 0.0016
		sign.modulate = Color(0.86, 0.87, 0.77)
		sign.outline_size = 0
		sign.shaded = true
		sign.position = _leaf_off(w * 0.5 * m, 1.31, t + side * 0.012)
		sign.rotation_degrees.y = (90.0 if side > 0 else -90.0) if is_east_facing else (0.0 if side > 0 else 180.0)
		_anim_body.add_child(sign)
		for u in [0.10, w - 0.10]:
			for y in [0.08, 0.28]:
				_add_box_mesh(_leaf_size(0.015, 0.015, 0.008), _leaf_off(u * m, y, t + side * 0.012), dark)
	for y in [0.25, h * 0.5, h - 0.25]:
		_add_box_mesh(_leaf_size(0.055, 0.14, door_thickness + 0.035), _leaf_off(0.025 * m, y), steel)


func _add_door_mesh(size: Vector3, offset: Vector3, mat: StandardMaterial3D) -> void:
	var mi  := MeshInstance3D.new()
	mi.name = "DoorMesh"
	var bm  := BoxMesh.new()
	bm.size = size          # size set on the resource BEFORE assigning
	mi.mesh = bm
	mi.material_override = mat
	mi.position = offset
	_anim_body.add_child(mi)


func _add_collision(size: Vector3, offset: Vector3) -> void:
	var cs  := CollisionShape3D.new()
	cs.name = "DoorCollision"
	var bs  := BoxShape3D.new()
	bs.size = size          # size set on the resource BEFORE assigning
	cs.shape    = bs
	cs.position = offset
	_anim_body.add_child(cs)


func _add_handle(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi  := MeshInstance3D.new()
	var bm  := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_anim_body.add_child(mi)


# ── Public API ────────────────────────────────────────────────────────────────

func interact() -> void:
	if jammed:
		set_jammed(false)
		get_node("/root/GameManager").complete_objective("fix_door")
		return
	if locked:
		if get_node("/root/GameManager").has_item("maintenance_key"):
			locked = false
		else:
			get_node("/root/GameManager").notice_posted.emit("A maintenance key is required. Check Security.")
			return
	if requires_power and not powered:
		return
	toggle_door()


func _get_prompt() -> String:
	if jammed: return "[Hold E] Unjam door"
	if locked: return "[E] Unlock with maintenance key"
	if requires_power and not powered: return "Door offline — restore power"
	return interact_prompt + (" (blocked)" if _blocked else "")


func set_jammed(value: bool) -> void:
	jammed = value
	var interaction := get_node_or_null("Interaction")
	if interaction: interaction.hold_seconds = 2.0 if jammed else 0.0


func toggle_door() -> void:
	set_open(not is_open)


func set_open(open_state: bool) -> void:
	if open_state == is_open:
		return
	if jammed or locked or (requires_power and not powered):
		return
	_blocked = false
	if not open_state and _closing_is_blocked():
		_blocked = true
		return
	is_open       = open_state
	interact_prompt = "[E] Close door" if is_open else "[E] Open door"

	# Opens AWAY from whoever is standing there (push the door, never get hit by it).
	var target_angle: float = deg_to_rad(open_angle_deg) * _push_sign() if is_open else 0.0

	if _tween and _tween.is_running():
		_tween.kill()

	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_anim_body, "rotation:y", target_angle, swing_speed)

	if is_open:
		_play_door_sound(true)
	else:
		# The latch lands when the leaf reaches the frame. Interrupted closes
		# lose this callback when their tween is killed.
		_tween.tween_callback(_play_door_sound.bind(false))

	door_toggled.emit(is_open)


func _closing_is_blocked() -> bool:
	var collider := _anim_body.get_node("DoorCollision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.collision_mask = Layers.ACTORS
	for i in range(1, 7):
		var angle: float = lerpf(_anim_body.rotation.y, 0, float(i) / 6)
		query.transform = global_transform * Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * Transform3D(Basis.IDENTITY, collider.position)
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return true
	return false


func save_state() -> Dictionary:
	return {"open": is_open, "angle": _anim_body.rotation.y, "locked": locked, "jammed": jammed}


func load_state(data: Dictionary) -> void:
	if _tween and _tween.is_running(): _tween.kill()
	is_open = bool(data.get("open", false))
	locked = bool(data.get("locked", false))
	set_jammed(bool(data.get("jammed", false)))
	_anim_body.rotation.y = float(data.get("angle", 0)) if is_open else 0.0
	interact_prompt = "[E] Close door" if is_open else "[E] Open door"


func _push_sign() -> float:
	## Rotation sign that swings the leaf away from the player. Sign of rotation
	## that carries the leaf to the +normal side of the wall (+Z for north/south
	## walls, +X for east/west walls) depends on the hinge layout; then we pick
	## the side opposite to where the player stands.
	var toward_plus: float = (1.0 if is_east_facing else -1.0) * (-1.0 if hinge_flip else 1.0)
	var want: float = 1.0
	var who := get_node("/root/Coop").interacting_player() as Node3D
	if who:
		var local_pos: Vector3 = to_local(who.global_position)
		var side: float = local_pos.x if is_east_facing else local_pos.z
		want = -1.0 if side >= 0.0 else 1.0
	return toward_plus * want


func _play_door_sound(opening: bool) -> void:
	get_tree().call_group("entity_hearing", "hear_noise", global_position, 9.0)
	var snd := get_node_or_null("DoorSound") as AudioStreamPlayer3D
	if snd:
		snd.stream = _open_sound if opening else _close_sound
		snd.play()
