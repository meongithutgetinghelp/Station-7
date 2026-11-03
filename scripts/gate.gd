class_name Gate
extends Node3D
const Layers = preload("res://scripts/collision_layers.gd")

## One fare-gate lane (the gap between two turnstile pedestals).
## Place it at the lane centre on the floor. It builds its own glass flap,
## status light, presence sensor, sounds and scanner.
##
## Flow:   CLOSED --scan ok--> OPEN --person passes (or timeout)--> CLOSED
##         CLOSED --scan bad--> DENIED (red blink) --> CLOSED
##
## Anyone can call:
##   scan_employee(node)  — opens if the node has `has_employee_id == true`
##   scan_ticket(ticket)  — opens for a valid, unused Ticket
##   open_lane() / close() / deny()  — direct control (power events, alarms)

enum State { CLOSED, OPEN, DENIED }

signal state_changed(new_state: State)
signal scanned(success: bool, who: String)
signal passed_through

@export var lane_width: float = 1.0
@export var hold_time: float = 5.0     # seconds to stay open if nobody walks in
@export var open_angle_deg: float = 90.0

const COLOR_CLOSED := Color(0.95, 0.15, 0.12)
const COLOR_OPEN := Color(0.2, 0.9, 0.45)

var state: State = State.CLOSED
var powered: bool = true
var jammed: bool = false
var scanner: GateScanner

var _flap: AnimatableBody3D
var _sensor: Area3D
var _light_mat: StandardMaterial3D
var _beep: AudioStreamPlayer3D
var _snd_ok: AudioStreamWAV
var _snd_fail: AudioStreamWAV
var _tween: Tween
var _hold_left: float = 0.0
var _deny_left: float = 0.0
var _entered: bool = false


func _ready() -> void:
	add_to_group("save_participant")
	_build()
	_set_light(COLOR_CLOSED)


func _build() -> void:
	# ── Glass flap: hinged on the west pedestal, swings across the lane ──────
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.85, 1.0, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	_flap = AnimatableBody3D.new()
	_flap.name = "Flap"
	_flap.collision_layer = Layers.MOVING_DOORS
	_flap.sync_to_physics = false
	_flap.position = Vector3(-lane_width * 0.5 + 0.04, 0.13, 0.45)   # clear of the light strip
	var leaf := Vector3(lane_width - 0.06, 1.12, 0.04)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(leaf.x - 0.08, leaf.y - 0.08, 0.025)
	mi.mesh = bm
	mi.material_override = glass
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(leaf.x * 0.5, leaf.y * 0.5, 0.0)
	_flap.add_child(mi)
	# Moving glass is protected by a metal perimeter that swings with the leaf.
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.28, 0.35, 0.34)
	frame.metallic = 0.7
	frame.roughness = 0.4
	for edge in [
		["Bottom", Vector3(leaf.x - 0.08, 0.04, 0.06), Vector3(leaf.x * 0.5, 0.02, 0)],
		["Top", Vector3(leaf.x - 0.08, 0.04, 0.06), Vector3(leaf.x * 0.5, leaf.y - 0.02, 0)],
		["Hinge", Vector3(0.04, leaf.y, 0.06), Vector3(0.02, leaf.y * 0.5, 0)],
		["Latch", Vector3(0.04, leaf.y, 0.06), Vector3(leaf.x - 0.02, leaf.y * 0.5, 0)],
	]:
		var rim := MeshInstance3D.new()
		rim.name = "GlassFrame_" + edge[0]
		var rim_mesh := BoxMesh.new()
		rim_mesh.size = edge[1]
		rim.mesh = rim_mesh
		rim.material_override = frame
		rim.position = edge[2]
		_flap.add_child(rim)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = leaf
	cs.shape = bs
	cs.position = Vector3(leaf.x * 0.5, leaf.y * 0.5, 0.0)
	_flap.add_child(cs)
	add_child(_flap)

	# ── Presence sensor over the lane (detects player + NPCs on layer 2) ─────
	_sensor = Area3D.new()
	_sensor.name = "Sensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2
	var scs := CollisionShape3D.new()
	var sbs := BoxShape3D.new()
	sbs.size = Vector3(lane_width - 0.1, 1.8, 0.9)
	scs.shape = sbs
	scs.position = Vector3(0.0, 0.9, 0.0)
	_sensor.add_child(scs)
	add_child(_sensor)

	# ── Status light strips on both pedestal faces ───────────────────────────
	# Unshaded + no shadows: thin emissive strips sitting almost flush with the
	# pedestal otherwise show a hatched shadow-acne / z-fighting pattern.
	_light_mat = StandardMaterial3D.new()
	_light_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_light_mat.emission_enabled = true
	for sx in [-1.0, 1.0]:
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.012, 0.45, 0.2)
		strip.mesh = sm
		strip.material_override = _light_mat
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# lane side of the pedestal face (face is at ±lane_width/2), protruding 0.012 into the lane
		strip.position = Vector3(sx * (lane_width * 0.5 - 0.006), 0.94, -0.45)
		add_child(strip)

	# ── Scanner on top of the west pedestal ──────────────────────────────────
	scanner = GateScanner.new()
	scanner.name = "Scanner"
	scanner.gate = self
	scanner.position = Vector3(-(lane_width * 0.5 + 0.15), 1.31, -0.45)
	add_child(scanner)

	# ── Sound ────────────────────────────────────────────────────────────────
	_snd_ok = _make_tone([880.0, 1320.0], 0.09)
	_snd_fail = _make_tone([190.0, 190.0], 0.16)
	_beep = AudioStreamPlayer3D.new()
	_beep.name = "Beep"
	_beep.unit_size = 5.0
	_beep.max_distance = 16.0
	add_child(_beep)


# ── Public API ────────────────────────────────────────────────────────────────

func scan_employee(who: Node) -> bool:
	var ok: bool = powered and not jammed and who != null and who.get("has_employee_id") == true
	var who_id: String = str(who.get("employee_id")) if ok else ""
	scanned.emit(ok, who_id)
	if ok:
		open_lane()
	else:
		deny()
	return ok


func scan_ticket(ticket: Ticket) -> bool:
	var ok: bool = powered and not jammed and ticket != null and ticket.is_valid and not ticket.used
	scanned.emit(ok, ticket.id if ticket else "")
	if ok:
		ticket.used = true
		open_lane()
	else:
		deny()
	return ok


func open_lane() -> void:
	_hold_left = hold_time
	if state == State.OPEN:
		return
	state = State.OPEN
	_entered = false
	_swing(deg_to_rad(open_angle_deg), 0.3)
	_set_light(COLOR_OPEN)
	_play(_snd_ok)
	state_changed.emit(state)


func close() -> void:
	if state == State.CLOSED:
		return
	state = State.CLOSED
	_swing(0.0, 0.35)
	_set_light(COLOR_CLOSED)
	state_changed.emit(state)


func deny() -> void:
	if state == State.OPEN:
		return
	state = State.DENIED
	_deny_left = 1.2
	_play(_snd_fail)
	state_changed.emit(state)


func set_powered(on: bool) -> void:
	## Blackout: gate stays in whatever position it was in, light goes dark, scans fail.
	powered = on
	if not on:
		_set_light(Color(0.05, 0.05, 0.05))
	else:
		_set_light(COLOR_OPEN if state == State.OPEN else COLOR_CLOSED)


# ── Internals ─────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if get_node("/root/Coop").simulation_blocked(): return
	if not powered:
		return
	if state == State.OPEN:
		var occupied: bool = _sensor.has_overlapping_bodies()
		if occupied:
			_entered = true
			_hold_left = maxf(_hold_left, 1.0)
		elif _entered:
			# somebody walked in and out: they're through
			_entered = false
			_hold_left = minf(_hold_left, 0.4)
			passed_through.emit()
		if not occupied:
			_hold_left -= delta
			if _hold_left <= 0.0:
				close()
	elif state == State.DENIED:
		_deny_left -= delta
		if powered:
			_set_light(COLOR_CLOSED if int(_deny_left * 6.0) % 2 == 0 else Color(0.15, 0.02, 0.02))
		if _deny_left <= 0.0:
			state = State.CLOSED
			if powered:
				_set_light(COLOR_CLOSED)
			state_changed.emit(state)


func _swing(target_rad: float, seconds: float) -> void:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_flap, "rotation:y", target_rad, seconds)


func _set_light(c: Color) -> void:
	if not _light_mat:
		return
	_light_mat.albedo_color = c
	_light_mat.emission = c
	_light_mat.emission_energy_multiplier = 1.6


func _play(snd: AudioStreamWAV) -> void:
	if _beep and powered:
		_beep.stream = snd
		_beep.play()


func save_state() -> Dictionary:
	return {"state": state, "jammed": jammed, "hold": _hold_left, "entered": _entered, "angle": _flap.rotation.y}


func load_state(data: Dictionary) -> void:
	if _tween and _tween.is_running(): _tween.kill()
	state = data.get("state", State.CLOSED)
	jammed = bool(data.get("jammed", false))
	_hold_left = float(data.get("hold", 0))
	_entered = bool(data.get("entered", false))
	_flap.rotation.y = float(data.get("angle", 0))
	_set_light(COLOR_OPEN if state == State.OPEN else COLOR_CLOSED)


func _make_tone(freqs: Array, seg_seconds: float) -> AudioStreamWAV:
	var rate: int = 22050
	var per: int = int(rate * seg_seconds)
	var data := PackedByteArray()
	data.resize(per * freqs.size())
	for k in range(freqs.size()):
		for i in range(per):
			var t: float = float(i) / float(rate)
			var env: float = minf(1.0, float(per - i) / float(per) * 4.0)
			var s: float = sin(TAU * float(freqs[k]) * t) * env
			data[k * per + i] = int(clamp((s * 0.35 + 0.5) * 255.0, 0.0, 255.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
