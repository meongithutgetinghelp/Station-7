extends Node3D
## Furniture is batched by material; seat anchors remain explicit for boarding.
var seats: Array[Vector3] = []
var surfaces: Array[SurfaceTool] = []
const CAR_CENTRES := [-18.75,-6.25,6.25,18.75]
const SEAT_HEIGHT := 0.84

func _ready() -> void:
	name = "CarriageInterior"
	for color in [Color("244e68"),Color("bdc8ca"),Color("e7bc49"),Color("454d50")]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.35 if surfaces.size() == 1 else (0.48 if surfaces.is_empty() else 0.65)
		material.metallic = 0.4 if surfaces.size() == 1 else 0.0
		surface.set_material(material)
		surfaces.append(surface)
	for centre in CAR_CENTRES:
		_box(Vector3(11.95,0.018,2.76),Vector3(centre,0.36,0),3)
		for side in [-1.0,1.0]:
			for x in [-2.75,-1.95,-1.15,1.15,1.95,2.75,-5.25,5.25]:
				_seat(Vector3(centre+x,0,side*1.05),side,2 if absf(x)>5 else 0)
				seats.append(Vector3(centre+x,0.35,side*1.05))
			for x in [-2.0,2.0]:
				_bar(Vector3(centre+x-1.1,0.73,side*1.05),Vector3(centre+x+1.1,0.73,side*1.05),0.026,1)
				for leg in [-0.8,0.8]: _bar(Vector3(centre+x+leg,0.37,side*1.05),Vector3(centre+x+leg,0.73,side*1.05),0.024,1)
			for x in [-5.25,5.25]: _bar(Vector3(centre+x,0.37,side*1.05),Vector3(centre+x,0.75,side*1.05),0.03,1)
			# Continuous overhead rails, with suspended individual hand loops.
			_bar(Vector3(centre-5.7,2.40,side*0.62),Vector3(centre+5.7,2.40,side*0.62),0.024,1)
			for x in [-5.0,-4.1,-3.2,-2.3,-1.4,-0.5,0.5,1.4,2.3,3.2,4.1,5.0]:
				_bar(Vector3(centre+x,2.40,side*0.62),Vector3(centre+x,2.26,side*0.62),0.012,3)
				var loop := TorusMesh.new()
				loop.inner_radius = 0.062
				loop.outer_radius = 0.086
				loop.rings = 12
				loop.ring_segments = 6
				_append(loop,Transform3D(Basis(Vector3.RIGHT,PI*0.5),Vector3(centre+x,2.18,side*0.62)),2)
			# Seat-end rails leave every doorway's full opening unobstructed.
			for x in [-3.17,-0.75,0.75,3.17]:
				_bar(Vector3(centre+x,0.38,side*1.22),Vector3(centre+x,2.49,side*1.22),0.024,1)
				_bar(Vector3(centre+x,1.05,side*1.22),Vector3(centre+x,1.05,side*0.78),0.025,1)
		for x in [-4.0,0.0,4.0]:
			_bar(Vector3(centre+x,0.38,0.50),Vector3(centre+x,2.49,0.50),0.027,1)
			_bar(Vector3(centre+x,2.49,-1.25),Vector3(centre+x,2.49,1.25),0.022,1)
		# Bulkhead frames suggest gangways between coaches without filling the aisle.
		for end in [-5.98,5.98]:
			for side in [-1.0,1.0]: _box(Vector3(0.055,2.12,0.87),Vector3(centre+end,1.42,side*0.94),3)
			_box(Vector3(0.055,0.15,2.75),Vector3(centre+end,2.445,0),3)
	var mesh := ArrayMesh.new()
	for surface in surfaces:
		surface.index()
		surface.commit(mesh)
	var visual := MeshInstance3D.new()
	visual.name = "SeatsRailsAndStraps"
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	surfaces.clear()

func _seat(point: Vector3, side: float, material: int) -> void:
	# A continuous moulded seat shell: rounded front lip, seat pan and reclined back.
	var profile := [Vector2(-0.32,0.78),Vector2(-0.30,0.84),Vector2(-0.12,0.86),Vector2(0.12,0.87),Vector2(0.19,1.32),Vector2(0.22,1.46),Vector2(0.28,1.44),Vector2(0.25,1.29),Vector2(0.18,0.79)]
	var vertices := PackedVector3Array()
	for x in [-0.355,0.355]:
		for yz in profile: vertices.append(point+Vector3(x,yz.y,side*yz.x))
	var indices := PackedInt32Array()
	var n: int = profile.size()
	for i in range(n):
		var j := (i+1)%n
		indices.append_array([i,j,n+j,i,n+j,n+i])
	var caps := Geometry2D.triangulate_polygon(PackedVector2Array(profile))
	for i in range(0,caps.size(),3): indices.append_array([caps[i],caps[i+1],caps[i+2],n+caps[i+2],n+caps[i+1],n+caps[i]])
	for i in range(0,indices.size(),3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		if side < 0:
			var swap := b
			b=c
			c=swap
		var normal := (b-a).cross(c-a).normalized()
		for vertex in [a,b,c]:
			surfaces[material].set_normal(normal)
			surfaces[material].add_vertex(vertex)

func _box(size: Vector3, at: Vector3, material: int) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh,Transform3D(Basis.IDENTITY,at),material)

func _bar(start: Vector3, end: Vector3, radius: float, material: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.height = start.distance_to(end)
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.radial_segments = 10
	var y := (end-start).normalized()
	var reference := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(reference).normalized()
	_append(mesh,Transform3D(Basis(x,y,x.cross(y)),(start+end)*0.5),material)

func _append(mesh: PrimitiveMesh, transform: Transform3D, material: int) -> void:
	surfaces[material].append_from(mesh,0,transform)
