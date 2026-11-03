extends Node3D
## Reused static printwork and wall wear. No collisions, lights, or per-frame work.
var _paper_materials: Dictionary = {}
func _ready() -> void:
	name = "StationDetail"
	_poster("ServicePoster", "night-service", Vector3(-5.4, 1.9, -15.73), 0)
	_poster("CrewPoster", "staff-notice", Vector3(15.73, 1.95, -8.6), -90)
	_poster("PlatformPoster", "platform-safety", Vector3(25.73, 1.9, 14), -90)
	_poster("BoothMemo", "staff-notice", Vector3(-9.2, 2.2, 6.79), 180)
	var wear := StandardMaterial3D.new()
	wear.albedo_texture = preload("res://assets/station_detail/wall-wear.png")
	wear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wear.roughness = 1
	var transforms: Array[Transform3D] = []
	for x in [-12.0, -8.0, -4.0, 4.0, 12.0]:
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.1, 0.45, 1)), Vector3(x, 0.62, -15.74)))
	for z in [-14.5, -12.2, -8.5, -1.2, 0.5, 4.4, 9.0]:
		transforms.append(Transform3D(Basis(Vector3.UP, -PI/2).scaled(Vector3(0.8, 0.6, 1)), Vector3(15.74, 0.7, z)))
	for z in [-12.0, -7.0, 0.0]:
		transforms.append(Transform3D(Basis(Vector3.UP, PI/2).scaled(Vector3(1.6, 0.5, 1)), Vector3(-15.74, 0.65, z)))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_batch("WallWear", quad, wear, transforms)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.14, 0.18, 0.17)
	metal.roughness = 0.85
	_box("CableRun", Vector3(0.035, 0.035, 23), Vector3(15.68, 3.25, -2.5), metal)
	var clips: Array[Transform3D] = []
	for i in range(29): clips.append(Transform3D(Basis.IDENTITY, Vector3(15.66, 3.25, -14 + i*0.8)))
	var clip := BoxMesh.new()
	clip.size = Vector3(0.08, 0.09, 0.025)
	_batch("CableClips", clip, metal, clips)
	for z in [-12.5, -0.5, 5.0]:
		_box("CableJunction", Vector3(0.14, 0.24, 0.20), Vector3(15.65, 3.25, z), metal)

func _poster(n: String, texture: String, at: Vector3, yaw: float) -> void:
	var visual := MeshInstance3D.new()
	visual.name = n
	var quad := QuadMesh.new()
	quad.size = Vector2(0.72, 0.96)
	visual.mesh = quad
	if not _paper_materials.has(texture):
		var paper := StandardMaterial3D.new()
		paper.albedo_texture = load("res://assets/station_detail/" + texture + ".png")
		paper.roughness = 1
		_paper_materials[texture] = paper
	visual.material_override = _paper_materials[texture]
	visual.position = at
	visual.rotation_degrees.y = yaw
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

func _box(n: String, size: Vector3, at: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

func _batch(n: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	var visual := MultiMeshInstance3D.new()
	visual.name = n
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for i in range(transforms.size()): batch.set_instance_transform(i, transforms[i])
	visual.multimesh = batch
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
