class_name Player
extends CharacterBody3D

const InteractionComponent = preload("res://interactable.gd")
const MechanicalAudio = preload("res://mechanical_audio.gd")

## First-Person Player Controller with Flashlight, Head Bobbing, Sprint, Crouch, Dynamic FOV, and Stamina.
##
## Controls:
##   - WASD / Arrow Keys : Movement
##   - Mouse             : Look around
##   - Shift (Hold)      : Sprint (consumes Stamina)
##   - Space             : Jump
##   - Ctrl / C (Hold)   : Crouch
##   - F                 : Toggle Flashlight
##   - E                 : Interact (doors, electrical box, switches, ticket booth…)
##   - Escape            : Pause / Resume

# ─── EXPORT SETTINGS ──────────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.2
@export var jump_velocity: float = 4.5
@export var ground_acceleration: float = 12.0
@export var ground_deceleration: float = 14.0
@export var air_control_acceleration: float = 3.5
@export var step_height: float = 0.35

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 30.0
@export var stamina_regen_rate: float = 22.0
@export var stamina_regen_delay: float = 0.8
@export var stamina_exhaust_penalty: float = 1.2
@export var show_stamina_bar: bool = true

@export_group("Camera & Mouse Look")
@export var mouse_sensitivity: float = 0.0025
@export var invert_mouse_y: bool = false
@export_range(-90.0, 0.0, 0.1) var min_pitch: float = -88.0
@export_range(0.0, 90.0, 0.1) var max_pitch: float = 88.0
@export var base_fov: float = 70.0
@export var sprint_fov: float = 84.0
@export var fov_change_speed: float = 8.0

@export_group("Controls Preference")
@export var toggle_crouch: bool = false
@export var toggle_sprint: bool = false

@export_group("Head Bobbing")
@export var enable_head_bob: bool = true
@export var bob_frequency: float = 2.4
@export var bob_amplitude: float = 0.04
@export var bob_reset_speed: float = 10.0

@export_group("Crouch")
@export var stand_height: float = 1.72
@export var crouch_height: float = 1.1
@export var stand_camera_y: float = 1.60
@export var crouch_camera_y: float = 0.95
@export var crouch_transition_speed: float = 8.0

@export_group("Flashlight")
@export var flashlight_starts_on: bool = true
@export var flashlight_color: Color = Color(0.97, 0.96, 0.90)
@export var flashlight_energy: float = 2.8
@export var flashlight_range: float = 28.0
@export var flashlight_angle: float = 38.0
@export var flashlight_sway: bool = true
@export var flashlight_sway_amount: float = 0.05
@export var flashlight_sway_speed: float = 12.0
@export var flashlight_bounce_fill: bool = true

@export_group("Interaction")
@export var interact_reach: float = 2.5   # metres the E-key ray travels

@export_group("Nodes")
@export var head: Node3D
@export var camera: Camera3D
@export var flashlight: SpotLight3D
@export var flashlight_fill: OmniLight3D
@export var collision_shape: CollisionShape3D
@export var ceiling_check: RayCast3D
@export var click_player: AudioStreamPlayer

@export_group("HUD / UI")
@export var show_reticle: bool = true
@export var reticle_color: Color = Color(1.0, 1.0, 1.0, 0.5)

# ─── STATE VARIABLES ──────────────────────────────────────────────────────────
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var is_crouching: bool = false
var is_sprinting: bool = false
var is_flashlight_on: bool = false
var in_booth_inspection: bool = false

# Staff credentials — scanned at fare gates (see gate.gd).
var has_employee_id: bool = true
var employee_id: String = "STAFF-0717"

var current_stamina: float = 100.0
var is_exhausted: bool = false
var _stamina_delay_timer: float = 0.0
var _displayed_stamina: float = 100.0

var _stamina_container: Control
var _stamina_progress: ProgressBar
var _stamina_fill_style: StyleBoxFlat
var _stamina_bg_style: StyleBoxFlat
var _stamina_readout: Label

# Interaction prompt label (created in _setup_hud)
var _prompt_label: Label
var _interaction_target: InteractionComponent
var _hold_elapsed: float = 0.0
var _hold_consumed: bool = false

var _bob_timer: float = 0.0
var _camera_initial_pos: Vector3 = Vector3.ZERO
var _flashlight_initial_rot: Vector3 = Vector3.ZERO
var _current_capsule: CapsuleShape3D
var _flashlight_on_sound: AudioStream
var _flashlight_off_sound: AudioStream
var _step_sound: AudioStreamPlayer3D
var _step_timer: float = 0
var flashlight_charge: float = 100.0


# ─── LIFECYCLE ────────────────────────────────────────────────────────────────
func _ready() -> void:
	add_to_group("player")
	add_to_group("save_participant")
	collision_layer = preload("res://collision_layers.gd").ACTORS
	collision_mask = preload("res://collision_layers.gd").SOLID
	current_stamina = max_stamina
	_displayed_stamina = max_stamina

	_ensure_input_mappings()
	_ensure_nodes()
	_setup_hud()

	floor_stop_on_slope = false
	floor_constant_speed = false
	floor_snap_length = 0.1
	floor_max_angle = deg_to_rad(50.0)
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

	set_flashlight(flashlight_starts_on, false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if get_node("/root/Coop").active and (not get_node("/root/Coop").world_live or get_meta("local_menu", false)): return
	if in_booth_inspection and not _physical_desk_active():
		return
	if (get_meta("computer_focus",false) or get_meta("desk_action_focus",false)) and (event is InputEventMouseMotion or event.is_action_pressed("toggle_flashlight")): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		var manager := get_node("/root/GameManager")
		if manager.has_item("battery") and flashlight_charge < 100:
			if camera.has_node("Equipment"): camera.get_node("Equipment").use_item("battery")
			if get_node("/root/Coop").active: get_node("/root/Coop").request_action("battery")
			else:
				manager.inventory["battery"] -= 1
				flashlight_charge = 100
			manager.notice_posted.emit("Flashlight battery replaced.")
		get_viewport().set_input_as_handled()
		return
	# Click to reclaim cursor
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			var hit := _raycast_hit()
			if not hit.is_empty() and hit.collider.is_in_group("booth_computer_screen"):
				_try_interact()
				get_viewport().set_input_as_handled()
				return

	# ── E key: interact ───────────────────────────────────────────────────────
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
		return

	# ── F key: flashlight ─────────────────────────────────────────────────────
	if event.is_action_pressed("toggle_flashlight"):
		if camera.has_node("Equipment"): camera.get_node("Equipment").equip("flashlight")
		toggle_flashlight()
		get_viewport().set_input_as_handled()
		return

	# Crouch toggle mode
	if toggle_crouch and event.is_action_pressed("crouch"):
		if is_crouching:
			if ceiling_check and ceiling_check.is_colliding():
				pass
			else:
				is_crouching = false
		else:
			is_crouching = true
		get_viewport().set_input_as_handled()
		return

	# Sprint toggle mode
	if toggle_sprint and event.is_action_pressed("sprint"):
		if not is_exhausted and current_stamina > 0.0:
			is_sprinting = not is_sprinting
		get_viewport().set_input_as_handled()
		return

	# The computer owns the close-up camera until the player returns to the desk.
	# Mouse look
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var y_mult: float = -1.0 if invert_mouse_y else 1.0
		rotate_y(-event.relative.x * mouse_sensitivity)
		if head:
			head.rotation.x = clamp(
				head.rotation.x - event.relative.y * mouse_sensitivity * y_mult,
				deg_to_rad(min_pitch),
				deg_to_rad(max_pitch)
			)
		if flashlight and flashlight_sway and not _physical_desk_active():
			var sway_x: float = clamp(-event.relative.y * mouse_sensitivity * y_mult * flashlight_sway_amount * 10.0, -0.15, 0.15)
			var sway_y: float = clamp(-event.relative.x * mouse_sensitivity * flashlight_sway_amount * 10.0, -0.15, 0.15)
			flashlight.rotation.x += sway_x
			flashlight.rotation.y += sway_y


func _process(delta: float) -> void:
	if get_node("/root/Coop").active and (not get_node("/root/Coop").world_live or get_meta("local_menu", false)): return
	if is_flashlight_on:
		flashlight_charge = maxf(0, flashlight_charge - delta * 0.08)
		if flashlight_charge <= 0: set_flashlight(false, false)
	if in_booth_inspection:
		if _physical_desk_active():
			if flashlight: flashlight.rotation = _flashlight_initial_rot
			_update_interact_prompt(delta)
			return
		if _prompt_label:
			_prompt_label.text = ""
		return
	if flashlight and flashlight_sway:
		flashlight.rotation = flashlight.rotation.lerp(_flashlight_initial_rot, delta * flashlight_sway_speed)
	_update_head_bob(delta)
	_update_fov(delta)
	_update_stamina_hud(delta)
	_update_interact_prompt(delta)


func _physics_process(delta: float) -> void:
	if get_node("/root/Coop").active and (not get_node("/root/Coop").world_live or get_meta("local_menu", false)): return
	if in_booth_inspection:
		velocity.x = 0
		velocity.z = 0
		if get_meta("seated_workstation", false): return
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	if not is_on_floor():
		velocity.y -= gravity * delta

	if not toggle_crouch:
		var wants_crouch: bool = Input.is_action_pressed("crouch")
		if wants_crouch:
			is_crouching = true
		elif is_crouching:
			if ceiling_check and ceiling_check.is_colliding():
				is_crouching = true
			else:
				is_crouching = false

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = jump_velocity

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var wants_sprint: bool = false
	if not toggle_sprint:
		wants_sprint = Input.is_action_pressed("sprint")
	else:
		wants_sprint = is_sprinting

	var is_moving_forward: bool = input_dir.y < -0.1
	var can_sprint: bool = wants_sprint and not is_crouching and is_on_floor() and is_moving_forward and current_stamina > 0.0 and not is_exhausted

	if can_sprint:
		is_sprinting = true
		current_stamina = max(0.0, current_stamina - stamina_drain_rate * delta)
		_stamina_delay_timer = stamina_regen_delay
		if current_stamina <= 0.0:
			is_exhausted = true
			_stamina_delay_timer = stamina_regen_delay + stamina_exhaust_penalty
	else:
		is_sprinting = false
		if _stamina_delay_timer > 0.0:
			_stamina_delay_timer -= delta
		else:
			current_stamina = move_toward(current_stamina, max_stamina, stamina_regen_rate * delta)
			if is_exhausted and current_stamina >= max_stamina * 0.25:
				is_exhausted = false

	var target_speed: float = walk_speed
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed

	var accel: float = ground_acceleration if is_on_floor() else air_control_acceleration
	var decel: float = ground_deceleration if is_on_floor() else (air_control_acceleration * 0.5)

	if move_dir.length_squared() > 0.001:
		velocity.x = move_toward(velocity.x, move_dir.x * target_speed, accel * target_speed * delta)
		velocity.z = move_toward(velocity.z, move_dir.z * target_speed, accel * target_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * walk_speed * delta)
		velocity.z = move_toward(velocity.z, 0.0, decel * walk_speed * delta)

	_try_step_up(move_dir)
	move_and_slide()
	_update_crouch(delta)
	_step_timer -= delta
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.7 and _step_timer <= 0:
		_step_timer = 0.65 if is_crouching else (0.3 if is_sprinting else 0.46)
		_step_sound.volume_db = -24 if is_crouching else (-13 if is_sprinting else -18)
		_step_sound.play()
		if not get_node("/root/Coop").is_client():
			get_tree().call_group("entity_hearing", "hear_noise", global_position, 13.0 if is_sprinting else (2.0 if is_crouching else 6.0))


# ─── STEP-UP ──────────────────────────────────────────────────────────────────
func _try_step_up(move_dir: Vector3) -> void:
	if not is_on_floor() or move_dir.length_squared() < 0.001:
		return

	var space := get_world_3d().direct_space_state

	# Fire three short rays fanning forward at shin level.
	# If ANY hits a wall, attempt to step over it.
	var hit_wall := false
	var wall_x   := global_position.x
	var wall_z   := global_position.z

	for angle_deg in [0.0, -20.0, 20.0]:
		var rotated := move_dir.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var from := global_position + Vector3(0.0, 0.15, 0.0)
		var to   := from + rotated * 0.55
		var q    := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [self]
		var hit  := space.intersect_ray(q)
		if hit:
			hit_wall = true
			wall_x = hit.position.x
			wall_z = hit.position.z
			break

	if not hit_wall:
		return

	# Drop a ray from step_height above the wall hit, straight down.
	var probe_top  := Vector3(wall_x, global_position.y + step_height + 0.05, wall_z)
	var probe_bot  := probe_top + Vector3(0.0, -(step_height + 0.2), 0.0)
	var qd         := PhysicsRayQueryParameters3D.create(probe_top, probe_bot)
	qd.exclude      = [self]
	var down_hit   := space.intersect_ray(qd)
	if not down_hit:
		return

	var step_top   : float = down_hit.position.y
	var climb      : float = step_top - global_position.y

	# Must be a genuine small step — not a flat floor (<=0.02) or a real wall (>step_height)
	if climb <= 0.02 or climb > step_height:
		return

	# Lift the player directly onto the step and clear downward velocity.
	global_position.y = step_top + 0.01
	velocity.y = maxf(velocity.y, 0.0)


# ─── INTERACTION ──────────────────────────────────────────────────────────────

func _raycast_hit() -> Dictionary:
	## Fire a ray from the camera centre and return the hit dict (empty if none).
	if not camera:
		return {}
	var space := get_world_3d().direct_space_state
	var from  := camera.global_position
	var to    := from - camera.global_transform.basis.z * interact_reach
	var q     := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude  = [self]
	return space.intersect_ray(q)


func _try_interact() -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var interaction := _get_interaction_target()
	if interaction and interaction.hold_seconds <= 0.0:
		interaction.interact()


func _get_interaction_target() -> InteractionComponent:
	var hit := _raycast_hit()
	if hit.is_empty():
		return null
	return InteractionComponent.resolve(hit.collider)


func _update_interact_prompt(delta: float) -> void:
	if not _prompt_label:
		return
	var target := _get_interaction_target() if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else null
	_prompt_label.text = _advance_interaction_hold(target, delta, Input.is_action_pressed("interact"))


func _advance_interaction_hold(target: InteractionComponent, delta: float, pressed: bool) -> String:
	if target != _interaction_target or not pressed:
		_hold_elapsed = 0.0
		_hold_consumed = false
	_interaction_target = target
	if not is_instance_valid(target):
		return ""
	var text := target.get_prompt()
	if not target.enabled or target.hold_seconds <= 0.0 or _hold_consumed:
		return text
	if pressed:
		if _hold_elapsed == 0 and get_node("/root/Coop").active: get_node("/root/Coop").begin_hold(target)
		_hold_elapsed += delta
		text += "  %d%%" % mini(100, int(_hold_elapsed / target.hold_seconds * 100.0))
		if _hold_elapsed >= target.hold_seconds:
			_hold_consumed = true
			target.interact()
	return text


# ─── CROUCH / HEAD BOB / FOV ──────────────────────────────────────────────────
func _update_crouch(delta: float) -> void:
	if not collision_shape or not _current_capsule or not head:
		return
	var target_capsule_height: float = crouch_height if is_crouching else stand_height
	var target_head_y: float = crouch_camera_y if is_crouching else stand_camera_y
	_current_capsule.height = move_toward(_current_capsule.height, target_capsule_height, crouch_transition_speed * delta)
	collision_shape.position.y = _current_capsule.height * 0.5
	head.position.y = move_toward(head.position.y, target_head_y, crouch_transition_speed * delta)


func _update_head_bob(delta: float) -> void:
	if not enable_head_bob or not camera:
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horizontal_speed > 0.2:
		var speed_factor: float = horizontal_speed / walk_speed
		_bob_timer += delta * bob_frequency * speed_factor * PI * 2.0
		camera.position.y = _camera_initial_pos.y + sin(_bob_timer) * bob_amplitude
		camera.position.x = _camera_initial_pos.x + cos(_bob_timer * 0.5) * (bob_amplitude * 0.5)
	else:
		_bob_timer = 0.0
		camera.position.x = move_toward(camera.position.x, _camera_initial_pos.x, delta * bob_reset_speed * bob_amplitude)
		camera.position.y = move_toward(camera.position.y, _camera_initial_pos.y, delta * bob_reset_speed * bob_amplitude)


func _update_fov(delta: float) -> void:
	if not camera:
		return
	var target_fov: float = sprint_fov if is_sprinting else base_fov
	camera.fov = lerp(camera.fov, target_fov, delta * fov_change_speed)


# ─── CINEMATIC STAMINA HUD ───────────────────────────────────────────────────
func _update_stamina_hud(delta: float) -> void:
	if not _stamina_progress or not _stamina_fill_style or not _stamina_bg_style:
		return
	_displayed_stamina = lerp(_displayed_stamina, current_stamina, delta * 15.0)
	_stamina_progress.value = _displayed_stamina
	var pct: int = int(round((current_stamina / max_stamina) * 100.0))
	if is_exhausted:
		_stamina_fill_style.bg_color = Color(0.95, 0.28, 0.20, 0.95)
		_stamina_bg_style.border_color = Color(0.95, 0.35, 0.25, 0.85)
		if _stamina_readout:
			_stamina_readout.text = "EXHAUSTED"
			_stamina_readout.add_theme_color_override("font_color", Color(0.95, 0.35, 0.25, 0.95))
	elif current_stamina < max_stamina * 0.25:
		_stamina_fill_style.bg_color = Color(0.98, 0.72, 0.15, 0.95)
		_stamina_bg_style.border_color = Color(0.98, 0.75, 0.20, 0.75)
		if _stamina_readout:
			_stamina_readout.text = str(pct) + "%"
			_stamina_readout.add_theme_color_override("font_color", Color(0.98, 0.75, 0.20, 0.95))
	else:
		_stamina_fill_style.bg_color = Color(0.88, 0.94, 1.0, 0.95)
		_stamina_bg_style.border_color = Color(0.85, 0.90, 0.98, 0.45)
		if _stamina_readout:
			_stamina_readout.text = str(pct) + "%"
			_stamina_readout.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98, 0.85))
	if _stamina_container:
		_stamina_container.modulate.a = 1.0


# ─── FLASHLIGHT ──────────────────────────────────────────────────────────────
func toggle_flashlight() -> void:
	set_flashlight(not is_flashlight_on, true)


func set_flashlight(enabled: bool, play_sound: bool = true) -> void:
	if enabled and flashlight_charge <= 0:
		enabled = false
	var changed: bool = is_flashlight_on != enabled
	is_flashlight_on = enabled
	if flashlight:
		flashlight.visible = is_flashlight_on
	if flashlight_fill:
		flashlight_fill.visible = is_flashlight_on
	if changed and play_sound and click_player:
		click_player.stream = _flashlight_on_sound if enabled else _flashlight_off_sound
		click_player.play()


# ─── AUTO-SETUP & RESILIENCE ─────────────────────────────────────────────────
func _ensure_nodes() -> void:
	# 1. CollisionShape3D
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			var cap := CapsuleShape3D.new()
			cap.radius = 0.4
			cap.height = stand_height
			collision_shape.shape = cap
			collision_shape.position = Vector3(0.0, stand_height * 0.5, 0.0)
			add_child(collision_shape)
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		_current_capsule = collision_shape.shape.duplicate() as CapsuleShape3D
		collision_shape.shape = _current_capsule

	# 2. Head
	if not head:
		head = get_node_or_null("Head") as Node3D
		if not head:
			head = Node3D.new()
			head.name = "Head"
			head.position = Vector3(0.0, stand_camera_y, 0.0)
			add_child(head)

	# 3. Camera3D
	if not camera:
		camera = head.get_node_or_null("Camera3D") as Camera3D
		if not camera:
			camera = Camera3D.new()
			camera.name = "Camera3D"
			camera.current = true
			camera.fov = base_fov
			head.add_child(camera)
	_camera_initial_pos = camera.position

	# 4. Flashlight
	if not flashlight:
		flashlight = camera.get_node_or_null("Flashlight") as SpotLight3D
		if not flashlight:
			flashlight = SpotLight3D.new()
			flashlight.name = "Flashlight"
			flashlight.position = Vector3(0.23, -0.23, -0.66)
			flashlight.light_cull_mask = 0xFFFFFFFB
			flashlight.light_color = flashlight_color
			flashlight.light_energy = flashlight_energy
			flashlight.spot_range = flashlight_range
			flashlight.spot_angle = flashlight_angle
			flashlight.spot_angle_attenuation = 1.3
			flashlight.spot_attenuation = 1.0
			flashlight.shadow_enabled = true
			flashlight.shadow_bias = 0.04
			flashlight.shadow_blur = 1.5
			camera.add_child(flashlight)
	flashlight.position = Vector3(0.23, -0.23, -0.66)
	flashlight.light_cull_mask = 0xFFFFFFFB
	_flashlight_initial_rot = flashlight.rotation

	# 4b. Bounce fill
	if flashlight_bounce_fill and not flashlight_fill:
		flashlight_fill = flashlight.get_node_or_null("FlashlightFill") as OmniLight3D
		if not flashlight_fill:
			flashlight_fill = OmniLight3D.new()
			flashlight_fill.name = "FlashlightFill"
			flashlight_fill.light_color = flashlight_color
			flashlight_fill.light_energy = 0.22
			flashlight_fill.omni_range = 3.5
			flashlight_fill.omni_attenuation = 2.0
			flashlight.add_child(flashlight_fill)

	# 5. Click sound
	_step_sound = AudioStreamPlayer3D.new()
	_step_sound.name = "Footsteps"
	_step_sound.stream = MechanicalAudio.footstep()
	_step_sound.bus = "SFX"
	_step_sound.max_distance = 10
	add_child(_step_sound)
	if not click_player:
		click_player = get_node_or_null("ClickSound") as AudioStreamPlayer
		if not click_player:
			click_player = AudioStreamPlayer.new()
			click_player.name = "ClickSound"
			add_child(click_player)
	if click_player and click_player.stream == null:
		_flashlight_on_sound = MechanicalAudio.flashlight_switch(true)
		_flashlight_off_sound = MechanicalAudio.flashlight_switch(false)
		click_player.stream = _flashlight_on_sound
		click_player.volume_db = -12.0
	else:
		# Preserve an explicitly supplied replacement recording for both actions.
		_flashlight_on_sound = click_player.stream
		_flashlight_off_sound = click_player.stream
	click_player.bus = "SFX"

	# 6. Ceiling check
	if not ceiling_check:
		ceiling_check = get_node_or_null("CeilingCheck") as RayCast3D
		if not ceiling_check:
			ceiling_check = RayCast3D.new()
			ceiling_check.name = "CeilingCheck"
			ceiling_check.position = Vector3(0.0, crouch_height - 0.2, 0.0)
			ceiling_check.target_position = Vector3(0.0, stand_height - (crouch_height - 0.2) + 0.1, 0.0)
			add_child(ceiling_check)
	if ceiling_check:
		ceiling_check.add_exception(self)
		ceiling_check.collision_mask = collision_mask


func _setup_hud() -> void:
	if has_node("PlayerHUD"):
		return

	var canvas := CanvasLayer.new()
	canvas.name = "PlayerHUD"

	# 1. Reticle dot
	if show_reticle:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := ColorRect.new()
		dot.name = "ReticleDot"
		dot.custom_minimum_size = Vector2(4, 4)
		dot.color = reticle_color
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(dot)
		canvas.add_child(center)

	# 2. Interaction prompt (centre-bottom of screen)
	var prompt_anchor := Control.new()
	prompt_anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	prompt_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label = Label.new()
	_prompt_label.name = "InteractPrompt"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_top    = -80.0
	_prompt_label.offset_bottom = -50.0
	_prompt_label.offset_left   = -200.0
	_prompt_label.offset_right  =  200.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.text = ""
	prompt_anchor.add_child(_prompt_label)
	canvas.add_child(prompt_anchor)

	# 3. Stamina gauge
	if show_stamina_bar:
		var stamina_margin := MarginContainer.new()
		stamina_margin.name = "StaminaContainer"
		stamina_margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		stamina_margin.offset_left   = 36.0
		stamina_margin.offset_bottom = -28.0
		stamina_margin.offset_top    = -68.0
		stamina_margin.offset_right  = 266.0
		stamina_margin.mouse_filter  = Control.MOUSE_FILTER_IGNORE

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var header_hbox := HBoxContainer.new()
		header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label := Label.new()
		label.text = "STAMINA"
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 0.8))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_hbox.add_child(label)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_hbox.add_child(spacer)

		_stamina_readout = Label.new()
		_stamina_readout.text = "100%"
		_stamina_readout.add_theme_font_size_override("font_size", 10)
		_stamina_readout.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96, 0.8))
		_stamina_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_hbox.add_child(_stamina_readout)
		vbox.add_child(header_hbox)

		_stamina_progress = ProgressBar.new()
		_stamina_progress.name = "StaminaProgressBar"
		_stamina_progress.min_value = 0.0
		_stamina_progress.max_value = max_stamina
		_stamina_progress.value = max_stamina
		_stamina_progress.show_percentage = false
		_stamina_progress.custom_minimum_size = Vector2(230.0, 8.0)
		_stamina_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE

		_stamina_bg_style = StyleBoxFlat.new()
		_stamina_bg_style.bg_color = Color(0.04, 0.05, 0.07, 0.85)
		_stamina_bg_style.border_width_left   = 0
		_stamina_bg_style.border_width_right  = 1
		_stamina_bg_style.border_width_top    = 1
		_stamina_bg_style.border_width_bottom = 1
		_stamina_bg_style.border_color = Color(0.85, 0.90, 0.98, 0.45)
		_stamina_bg_style.corner_radius_top_left     = 2
		_stamina_bg_style.corner_radius_top_right    = 2
		_stamina_bg_style.corner_radius_bottom_right = 2
		_stamina_bg_style.corner_radius_bottom_left  = 2
		_stamina_bg_style.set_border_width_all(0)
		_stamina_bg_style.set_corner_radius_all(4)
		_stamina_progress.add_theme_stylebox_override("background", _stamina_bg_style)

		_stamina_fill_style = StyleBoxFlat.new()
		_stamina_fill_style.bg_color = Color(0.88, 0.94, 1.0, 0.95)
		_stamina_fill_style.corner_radius_top_left    = 1
		_stamina_fill_style.corner_radius_bottom_left = 1
		_stamina_fill_style.set_corner_radius_all(4)
		_stamina_progress.add_theme_stylebox_override("fill", _stamina_fill_style)

		for tick_pct in [0.25, 0.50, 0.75]:
			var tick := ColorRect.new()
			tick.name = "Tick"
			tick.color = Color(0.04, 0.05, 0.07, 0.65)
			tick.custom_minimum_size = Vector2(1.0, 8.0)
			tick.position = Vector2(230.0 * tick_pct, 0.0)
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_stamina_progress.add_child(tick)

		vbox.add_child(_stamina_progress)
		stamina_margin.add_child(vbox)
		_stamina_container = stamina_margin
		_stamina_container.modulate.a = 1.0
		canvas.add_child(stamina_margin)

	add_child(canvas)


func save_state() -> Dictionary:
	var save_position: Vector3 = position
	var save_yaw: float = rotation.y
	var save_pitch: float = head.rotation.x
	var services := get_tree().get_first_node_in_group("station_services")
	if get_meta("seated_workstation", false) and services:
		save_position = services._seated_origin
		save_yaw = services._seated_rotation.y
		save_pitch = services._seated_head_rotation.x
	var equipped: String = camera.get_node("Equipment").equipped if camera.has_node("Equipment") else "flashlight"
	return {"position": [save_position.x, save_position.y, save_position.z], "yaw": save_yaw, "pitch": save_pitch, "stamina": current_stamina, "flashlight": is_flashlight_on, "charge": flashlight_charge, "equipped": equipped}


func load_state(data: Dictionary) -> void:
	var point: Array = data.get("position", [0, 0.5, -14])
	position = Vector3(float(point[0]), float(point[1]), float(point[2]))
	rotation.y = float(data.get("yaw", 0.0))
	head.rotation.x = float(data.get("pitch", 0.0))
	current_stamina = clampf(float(data.get("stamina", max_stamina)), 0, max_stamina)
	velocity = Vector3.ZERO
	in_booth_inspection = false
	set_meta("seated_workstation", false)
	head.position.y = stand_camera_y
	collision_shape.set_deferred("disabled", false)
	flashlight_charge = clampf(float(data.get("charge", 100)), 0, 100)
	_hold_elapsed = 0
	set_flashlight(bool(data.get("flashlight", true)), false)
	if camera.has_node("Equipment"): camera.get_node("Equipment").equip(str(data.get("equipped", "flashlight")), false)


func _ensure_input_mappings() -> void:
	_register_action("move_forward",        [KEY_W, KEY_UP])
	_register_action("move_backward",       [KEY_S, KEY_DOWN])
	_register_action("move_left",           [KEY_A, KEY_LEFT])
	_register_action("move_right",          [KEY_D, KEY_RIGHT])
	_register_action("jump",                [KEY_SPACE])
	_register_action("sprint",              [KEY_SHIFT])
	_register_action("crouch",              [KEY_CTRL, KEY_C])
	_register_action("toggle_flashlight",   [KEY_F])
	_register_action("interact",            [KEY_E])
	_register_action("toggle_mouse_capture",[KEY_ESCAPE])   # ← was missing


func _register_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action_name, ev)


func _physical_desk_active() -> bool:
	if not get_meta("seated_workstation", false): return false
	var director := get_tree().get_first_node_in_group("passenger_director")
	return director != null and director.ui.is_open and not get_tree().paused
