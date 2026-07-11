class_name PassiveSlimeTendrils
extends MeshInstance3D
## Decorative only: adds silhouette complexity without participating in locomotion.

@export var tendril_count := 16
@export var curve_sections := 11
@export var radial_sides := 6
@export var base_radius := 0.13
@export var min_length := 2.4
@export var max_length := 5.8

var _mesh := ImmediateMesh.new()
var _time := 0.0

func _ready() -> void:
	mesh = _mesh

func _process(delta: float) -> void:
	_time += delta
	_redraw_tendrils()

func _redraw_tendrils() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in tendril_count:
		_draw_tendril(index)
	_mesh.surface_end()

func _draw_tendril(index: int) -> void:
	var phase := float(index) * 2.39996
	var side_bias := sin(phase * 1.7) * 0.5
	var origin := Vector3(cos(phase) * 1.5, sin(phase * 1.31) * 0.85, sin(phase) * 1.65)
	var direction := Vector3(cos(phase), side_bias, sin(phase)).normalized()
	var length_value := lerpf(min_length, max_length, 0.5 + 0.5 * sin(phase * 2.17))
	var droop := Vector3.DOWN * (0.65 + 0.45 * sin(phase))
	var previous := origin
	for section in curve_sections:
		var t := float(section + 1) / float(curve_sections)
		var wave := Vector3(
			sin(_time * 1.2 + phase + t * 5.0),
			cos(_time * 0.85 + phase * 1.3 + t * 4.0),
			sin(_time * 1.05 - phase + t * 3.0)
		) * (0.16 + t * 0.38)
		var point := origin + direction * length_value * t + droop * t * t + wave * t
		var radius_a := base_radius * pow(1.0 - float(section) / float(curve_sections), 1.3)
		var radius_b := base_radius * pow(maxf(1.0 - t, 0.08), 1.3)
		_add_tube_segment(previous, point, radius_a, radius_b)
		previous = point

func _add_tube_segment(a: Vector3, b: Vector3, radius_a: float, radius_b: float) -> void:
	var direction := (b - a).normalized()
	if direction.length_squared() < 0.01:
		return
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var binormal := direction.cross(side).normalized()
	for face in radial_sides:
		var next := (face + 1) % radial_sides
		var normal_a := side * cos(TAU * float(face) / radial_sides) + binormal * sin(TAU * float(face) / radial_sides)
		var normal_b := side * cos(TAU * float(next) / radial_sides) + binormal * sin(TAU * float(next) / radial_sides)
		var a0 := a + normal_a * radius_a
		var a1 := a + normal_b * radius_a
		var b0 := b + normal_a * radius_b
		var b1 := b + normal_b * radius_b
		_add_triangle(a0, b0, b1, normal_a, normal_a, normal_b)
		_add_triangle(a0, b1, a1, normal_a, normal_b, normal_b)

func _add_triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	_mesh.surface_set_normal(na); _mesh.surface_add_vertex(a)
	_mesh.surface_set_normal(nb); _mesh.surface_add_vertex(b)
	_mesh.surface_set_normal(nc); _mesh.surface_add_vertex(c)
