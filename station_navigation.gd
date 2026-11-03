extends NavigationRegion3D

signal paths_ready
var ready_for_paths: bool = false


func _ready() -> void:
	add_to_group("station_navigation")
	call_deferred("_bake")


func _bake() -> void:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = preload("res://collision_layers.gd").WORLD
	mesh.cell_size = 0.125
	mesh.cell_height = 0.125
	mesh.agent_height = 1.75
	# Finer voxels preserve narrow doorways while clearing the 0.31 m capsules.
	mesh.agent_radius = 0.375
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 50.0
	mesh.filter_baking_aabb = AABB(Vector3(-27, -0.6, -39), Vector3(70, 16, 58.4))
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.map_set_cell_size(get_world_3d().navigation_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map, mesh.cell_height)
	NavigationServer3D.parse_source_geometry_data(mesh, source, get_parent())
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	var map := get_world_3d().navigation_map
	navigation_mesh = mesh
	# Baking is synchronous, but publishing the region to the server is not.
	# Never let agents request paths against the previous (possibly empty) map.
	NavigationServer3D.map_force_update(map)
	# Navigation iterations can finish asynchronously even after a force update.
	# Verify the station's essential booth-to-platform route before releasing AI.
	for attempt in range(240):
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_path(map, Vector3(-10, 0.35, 3), Vector3(0, 0.35, 13), true).size() >= 2:
			ready_for_paths = true
			break
	if ready_for_paths:
		paths_ready.emit()
	else:
		push_error("Station navigation did not publish a connected booth-to-platform route")
