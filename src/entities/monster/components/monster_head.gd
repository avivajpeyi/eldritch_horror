class_name MonsterHead
extends Node3D
## Rendering-only head aggregation. Player tracking arrives through SignalBus.

@export_range(5, 7) var core_lobe_count := 7
@export_range(3, 5) var primary_eye_count := 5
@export_range(15, 25) var swarm_eye_count := 22
@export_range(3, 5) var flesh_bridge_count := 5
@export var gaze_response := 7.5
@export var pulse_amount := 0.075

const FLESH_MATERIAL := preload("res://assets/materials/horror_flesh.tres")
const MUSCLE_MATERIAL := preload("res://assets/materials/boiling_muscle.tres")

var _rng := RandomNumberGenerator.new()
var _player_position := Vector3.ZERO
var _lobe_nodes: Array[CSGSphere3D] = []
var _lobe_base_scales: Array[Vector3] = []
var _lobe_phases: Array[float] = []
var _eyes: Array[Node3D] = []
var _normal_texture: ImageTexture
var _flesh_texture: ImageTexture
var _time := 0.0
var _pulse_accumulator := 0.0
var _signal_bus: Node

func _ready() -> void:
	_signal_bus = get_node("/root/SignalBus")
	_rng.seed = 0xE1D817C
	_build_procedural_textures()
	_build_lumpy_core()
	_build_flesh_bridges()
	_build_primary_eyes()
	_build_swarm_eyes()
	_build_micro_decals()
	_signal_bus.connect("player_position_updated", _on_player_position_updated)

func _exit_tree() -> void:
	if _signal_bus != null and _signal_bus.is_connected("player_position_updated", _on_player_position_updated):
		_signal_bus.disconnect("player_position_updated", _on_player_position_updated)

func _process(delta: float) -> void:
	_time += delta
	_pulse_accumulator += delta
	# CSG rebuilds are expensive; 12 Hz retains the malignant shifting motion
	# without rebuilding seven unions every rendered frame.
	if _pulse_accumulator >= 1.0 / 12.0:
		_pulse_accumulator = 0.0
		_pulse_lobes()
	_update_gazes(delta)

func _build_lumpy_core() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "FleshUnion"
	add_child(combiner)
	for index in core_lobe_count:
		var lobe := CSGSphere3D.new()
		lobe.name = "Lobe_%02d" % index
		lobe.operation = CSGShape3D.OPERATION_UNION
		lobe.radius = _rng.randf_range(1.15, 2.05)
		lobe.radial_segments = 24
		lobe.rings = 16
		lobe.position = Vector3(
			_rng.randf_range(-1.35, 1.35),
			_rng.randf_range(-0.85, 1.05),
			_rng.randf_range(-1.15, 1.25)
		)
		var base_scale := Vector3(
			_rng.randf_range(0.75, 1.3),
			_rng.randf_range(0.65, 1.2),
			_rng.randf_range(0.72, 1.35)
		)
		lobe.scale = base_scale
		lobe.material = FLESH_MATERIAL
		lobe.add_to_group("monster_flesh")
		combiner.add_child(lobe)
		_lobe_nodes.append(lobe)
		_lobe_base_scales.append(base_scale)
		_lobe_phases.append(_rng.randf_range(0.0, TAU))

func _pulse_lobes() -> void:
	for index in _lobe_nodes.size():
		var pulse := sin(_time * (0.8 + index * 0.07) + _lobe_phases[index]) * pulse_amount
		var cross_pulse := cos(_time * 0.67 + _lobe_phases[index]) * pulse_amount * 0.45
		_lobe_nodes[index].scale = _lobe_base_scales[index] * Vector3(1.0 + pulse, 1.0 - cross_pulse, 1.0 + cross_pulse)

func _build_primary_eyes() -> void:
	var placements := [
		Vector3(0.0, 0.05, -2.25), Vector3(-1.15, 0.42, -1.75),
		Vector3(1.2, 0.3, -1.65), Vector3(-0.55, -0.8, -1.85),
		Vector3(0.72, -0.72, -1.72)
	]
	for index in primary_eye_count:
		var scale_value := 1.15 if index == 0 else _rng.randf_range(0.62, 0.9)
		var eye := _create_primary_eye(scale_value)
		eye.position = placements[index]
		add_child(eye)
		_eyes.append(eye)

func _create_primary_eye(size: float) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * size
	var sclera := MeshInstance3D.new()
	var sclera_mesh := SphereMesh.new()
	sclera_mesh.radius = 0.48
	sclera_mesh.height = 0.84
	sclera_mesh.radial_segments = 24
	sclera_mesh.rings = 16
	sclera.mesh = sclera_mesh
	sclera.scale = Vector3(1.0, 0.78, 0.44)
	var sclera_material := StandardMaterial3D.new()
	sclera_material.albedo_color = Color(0.32, 0.055, 0.018)
	sclera_material.roughness = 0.22
	sclera_material.emission_enabled = true
	sclera_material.emission = Color(0.62, 0.045, 0.004)
	sclera_material.emission_energy_multiplier = 1.8
	sclera.material_override = sclera_material
	root.add_child(sclera)
	var iris := MeshInstance3D.new()
	var iris_mesh := SphereMesh.new()
	iris_mesh.radius = 0.3
	iris_mesh.height = 0.3
	iris.mesh = iris_mesh
	iris.position.z = -0.39
	iris.scale = Vector3(1.0, 1.35, 0.18)
	var iris_material := StandardMaterial3D.new()
	iris_material.albedo_color = Color(0.95, 0.28, 0.005)
	iris_material.emission_enabled = true
	iris_material.emission = Color(1.0, 0.055, 0.002)
	iris_material.emission_energy_multiplier = 3.8
	iris.material_override = iris_material
	root.add_child(iris)
	var pupil := MeshInstance3D.new()
	var pupil_mesh := CapsuleMesh.new()
	pupil_mesh.radius = 0.055
	pupil_mesh.height = 0.48
	pupil.mesh = pupil_mesh
	pupil.position.z = -0.56
	pupil.scale = Vector3(0.42, 1.0, 0.18)
	var pupil_material := StandardMaterial3D.new()
	pupil_material.albedo_color = Color(0.002, 0.0, 0.0)
	pupil_material.roughness = 0.03
	pupil.material_override = pupil_material
	root.add_child(pupil)
	var cornea := MeshInstance3D.new()
	var cornea_mesh := SphereMesh.new()
	cornea_mesh.radius = 0.5
	cornea_mesh.height = 0.86
	cornea.mesh = cornea_mesh
	cornea.scale = Vector3(1.02, 0.8, 0.46)
	var cornea_material := StandardMaterial3D.new()
	cornea_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cornea_material.albedo_color = Color(0.6, 0.12, 0.08, 0.17)
	cornea_material.roughness = 0.02
	cornea_material.metallic_specular = 1.0
	cornea.material_override = cornea_material
	root.add_child(cornea)
	return root

func _build_swarm_eyes() -> void:
	for index in swarm_eye_count:
		var eye := Node3D.new()
		var angle := _rng.randf_range(0.0, TAU)
		var elevation := _rng.randf_range(-0.85, 0.9)
		var radial := _rng.randf_range(1.65, 2.25)
		eye.position = Vector3(cos(angle) * radial, elevation * 1.55, sin(angle) * radial * 0.82)
		var orb := MeshInstance3D.new()
		var orb_mesh := SphereMesh.new()
		orb_mesh.radius = _rng.randf_range(0.085, 0.19)
		orb_mesh.height = orb_mesh.radius * 1.5
		orb_mesh.radial_segments = 12
		orb_mesh.rings = 8
		orb.mesh = orb_mesh
		orb.scale.z = 0.38
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.3, 0.0, 0.002)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.002, 0.0)
		material.emission_energy_multiplier = _rng.randf_range(2.5, 5.0)
		material.roughness = 0.08
		orb.material_override = material
		eye.add_child(orb)
		add_child(eye)
		_eyes.append(eye)

func _update_gazes(delta: float) -> void:
	for eye in _eyes:
		var direction := _player_position - eye.global_position
		if direction.length_squared() < 0.01:
			continue
		var up := global_basis.y
		if absf(direction.normalized().dot(up)) > 0.96:
			up = global_basis.x
		var target_basis := Basis.looking_at(direction.normalized(), up).orthonormalized()
		# Primary eye roots carry scale. Interpolate only normalized rotations,
		# then restore scale instead of passing a scaled Basis to Quaternion.
		var eye_scale := eye.global_basis.get_scale()
		var current_rotation := eye.global_basis.orthonormalized().get_rotation_quaternion()
		var target_rotation := target_basis.get_rotation_quaternion()
		var blended_rotation := current_rotation.slerp(target_rotation, 1.0 - exp(-gaze_response * delta))
		eye.global_basis = Basis(blended_rotation).scaled(eye_scale)

func _build_flesh_bridges() -> void:
	for index in flesh_bridge_count:
		var from := Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.7, 0.8), _rng.randf_range(-1.0, 1.0))
		var to := -from * _rng.randf_range(0.65, 1.15) + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.4, 0.4))
		var bridge := MeshInstance3D.new()
		bridge.mesh = _build_bridge_mesh(from, to, _rng.randf_range(0.18, 0.34))
		bridge.material_override = MUSCLE_MATERIAL
		bridge.add_to_group("monster_flesh")
		add_child(bridge)

func _build_bridge_mesh(from: Vector3, to: Vector3, radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bend := (from + to) * 0.5 + Vector3.UP * _rng.randf_range(-0.35, 0.45)
	var previous := from
	for section in 8:
		var t := float(section + 1) / 8.0
		var point := from.lerp(bend, t).lerp(bend.lerp(to, t), t)
		_add_tube_section(tool, previous, point, radius * (1.0 - t * 0.25), radius * (1.0 - (t + 0.125) * 0.25), 8)
		previous = point
	tool.generate_normals()
	return tool.commit()

func _add_tube_section(tool: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float, sides: int) -> void:
	var forward := (b - a).normalized()
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = forward.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := forward.cross(side).normalized()
	for face in sides:
		var n0 := side * cos(TAU * face / sides) + up * sin(TAU * face / sides)
		var n1 := side * cos(TAU * (face + 1) / sides) + up * sin(TAU * (face + 1) / sides)
		var a0 := a + n0 * radius_a
		var a1 := a + n1 * radius_a
		var b0 := b + n0 * radius_b
		var b1 := b + n1 * radius_b
		tool.add_vertex(a0); tool.add_vertex(b0); tool.add_vertex(b1)
		tool.add_vertex(a0); tool.add_vertex(b1); tool.add_vertex(a1)

func _build_micro_decals() -> void:
	for index in 18:
		var decal := Decal.new()
		var angle := _rng.randf_range(0.0, TAU)
		var height_value := _rng.randf_range(-1.2, 1.25)
		decal.position = Vector3(cos(angle) * 1.9, height_value, sin(angle) * 1.65)
		decal.size = Vector3(_rng.randf_range(0.45, 1.15), _rng.randf_range(0.45, 1.25), 1.5)
		decal.texture_normal = _normal_texture
		decal.texture_albedo = _flesh_texture
		decal.modulate = Color(0.42, 0.06, 0.075, _rng.randf_range(0.3, 0.62))
		decal.rotation = Vector3(_rng.randf_range(-PI, PI), angle, _rng.randf_range(-PI, PI))
		add_child(decal)

func _build_procedural_textures() -> void:
	const SIZE := 96
	var height_map := PackedFloat32Array()
	height_map.resize(SIZE * SIZE)
	for y in SIZE:
		for x in SIZE:
			var uv := Vector2(float(x), float(y)) / SIZE
			var fibers := sin((uv.x * 12.0 + sin(uv.y * 19.0) * 0.8) * TAU) * 0.28
			var orifice := exp(-pow((uv - Vector2(0.5, 0.5)).length() * 5.2, 2.0))
			height_map[y * SIZE + x] = fibers - orifice * 1.4
	var normal_image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var albedo_image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var left := height_map[y * SIZE + posmod(x - 1, SIZE)]
			var right := height_map[y * SIZE + (x + 1) % SIZE]
			var down := height_map[posmod(y - 1, SIZE) * SIZE + x]
			var up := height_map[((y + 1) % SIZE) * SIZE + x]
			var normal := Vector3((left - right) * 2.4, (down - up) * 2.4, 1.0).normalized()
			normal_image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
			var h := height_map[y * SIZE + x]
			albedo_image.set_pixel(x, y, Color(0.12 + h * 0.04, 0.008, 0.014, clampf(0.55 + absf(h) * 0.3, 0.0, 1.0)))
	_normal_texture = ImageTexture.create_from_image(normal_image)
	_flesh_texture = ImageTexture.create_from_image(albedo_image)

func _on_player_position_updated(position: Vector3) -> void:
	_player_position = position
