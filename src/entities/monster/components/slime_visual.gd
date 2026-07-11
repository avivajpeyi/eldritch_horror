class_name SlimeMantleVisual
extends MeshInstance3D
## Builds one continuous, asymmetric mantle. This is rendering-only.

@export_range(8, 48) var rings := 24
@export_range(8, 64) var segments := 32
@export var length := 5.8
@export var width := 2.35
@export var height := 1.55

func _ready() -> void:
	_build_mantle()
	_build_core_cluster()

func _build_mantle() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in rings:
		var v0 := float(ring) / float(rings)
		var v1 := float(ring + 1) / float(rings)
		for segment in segments:
			var u0 := float(segment) / float(segments)
			var u1 := float(segment + 1) / float(segments)
			_add_quad(surface, _mantle_point(u0, v0), _mantle_point(u1, v0), _mantle_point(u1, v1), _mantle_point(u0, v1))
	surface.generate_normals()
	mesh = surface.commit()

func _mantle_point(u: float, v: float) -> Vector3:
	var longitude := u * TAU
	var latitude := v * PI
	var axial := -cos(latitude)
	var radial := pow(maxf(sin(latitude), 0.0), 0.72)
	var front_mass := lerpf(1.22, 0.78, smoothstep(-0.2, 1.0, axial))
	var ridge := 1.0 + sin(longitude * 3.0 + axial * 4.0) * 0.075
	var asymmetry := 1.0 + sin(longitude + axial * 5.3) * 0.055
	var x := cos(longitude) * radial * width * front_mass * ridge
	var y := sin(longitude) * radial * height * asymmetry
	var z := axial * length * 0.5
	y += -0.22 * axial + 0.14 * sin(axial * 5.0 + longitude * 2.0) * radial
	x += sin(axial * 3.7) * 0.13 * radial
	return Vector3(x, y, z)

func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
	surface.add_vertex(a)
	surface.add_vertex(c)
	surface.add_vertex(d)

func _build_core_cluster() -> void:
	var source_material := material_override as ShaderMaterial
	if source_material == null:
		return
	var lobe_data := [
		[Vector3(-1.35, 0.72, -0.35), Vector3(1.1, 0.85, 1.35), 0.2],
		[Vector3(0.85, 0.88, 0.35), Vector3(1.0, 1.2, 1.0), 1.1],
		[Vector3(-0.25, 1.18, 0.8), Vector3(0.82, 1.0, 0.9), 2.3],
		[Vector3(1.35, 0.2, 1.0), Vector3(0.72, 0.8, 1.15), 3.7],
		[Vector3(-1.15, -0.55, 0.95), Vector3(0.88, 0.68, 1.0), 4.5],
		[Vector3(0.28, -0.82, 1.35), Vector3(1.15, 0.72, 0.78), 5.4],
		[Vector3(0.35, 0.52, -1.45), Vector3(0.78, 0.9, 0.72), 2.9],
	]
	for datum in lobe_data:
		var lobe := MeshInstance3D.new()
		var lobe_mesh := SphereMesh.new()
		lobe_mesh.radius = 1.0
		lobe_mesh.height = 2.0
		lobe_mesh.radial_segments = 20
		lobe_mesh.rings = 12
		lobe.mesh = lobe_mesh
		lobe.position = datum[0]
		lobe.scale = datum[1]
		lobe.rotation = Vector3(datum[2] * 0.13, datum[2], datum[2] * -0.19)
		var lobe_material := source_material.duplicate() as ShaderMaterial
		lobe_material.set_shader_parameter("pulse_phase", datum[2])
		lobe_material.set_shader_parameter("pulse_strength", 0.045 + fmod(datum[2], 0.025))
		lobe_material.set_shader_parameter("roughness", 0.18 + fmod(datum[2] * 0.07, 0.2))
		lobe_material.set_shader_parameter("displacement_frequency", 4.0 + fmod(datum[2], 2.2))
		lobe.material_override = lobe_material
		add_child(lobe)
