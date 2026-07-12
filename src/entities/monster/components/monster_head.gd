class_name MonsterHead
extends Node3D
## Rendering-only convergence knot. The locomotion tentacles are the creature;
## this tiny fused mass only hides their roots and must never dominate silhouette.

@export_range(2, 3) var core_lobe_count := 3
@export var pulse_amount := 0.13
@export var drift_amount := 0.08
@export_category("Cyclopean Face")
@export var eye_scale := Vector2(0.82, 0.58)
@export_range(6, 12) var tooth_count := 9
@export var jaw_open_distance := 0.38

const FLESH_MATERIAL := preload("res://assets/materials/horror_flesh.tres")
const EYE_SHADER := preload("res://src/shaders/monster_eye.gdshader")

var _lobes: Array[CSGSphere3D] = []
var _base_positions: Array[Vector3] = []
var _base_scales: Array[Vector3] = []
var _phases: Array[float] = []
var _speeds: Array[float] = []
var _noises: Array[FastNoiseLite] = []
var _time := 0.0
var _update_accumulator := 0.0
var _base_position := Vector3.ZERO
var _base_rotation := Vector3.ZERO
var _base_scale := Vector3.ONE
var _agitation := 0.0
var _agitation_target := 0.0
var _blink := 0.0
var _blink_timer := 1.8
var _eye_material: ShaderMaterial
var _eye_root: Node3D
var _mouth_root: Node3D
var _throat_material: StandardMaterial3D
var _upper_teeth: Node3D
var _lower_teeth: Node3D
var _mouth_exposure := 0.0
var _mouth_exposure_target := 0.0


func _ready() -> void:
	_base_position = position
	_base_rotation = rotation
	_base_scale = scale
	_build_convergence_knot()
	_build_cyclopean_face()
	SignalBus.attack_phase_changed.connect(_on_attack_phase_changed)


func _exit_tree() -> void:
	if SignalBus.attack_phase_changed.is_connected(_on_attack_phase_changed):
		SignalBus.attack_phase_changed.disconnect(_on_attack_phase_changed)


func _process(delta: float) -> void:
	_time += delta
	_update_accumulator += delta
	_agitation = move_toward(_agitation, _agitation_target, delta * (2.4 if _agitation_target > _agitation else 1.25))
	_mouth_exposure = move_toward(_mouth_exposure, _mouth_exposure_target, delta * 4.8)
	_update_face(delta)
	_update_knot_transform(delta)
	# The knot is small and the motion slow. Eight boolean rebuilds per second keep
	# independent swelling visible without spending frame time on hidden detail.
	if _update_accumulator >= 1.0 / 8.0:
		_update_accumulator = 0.0
		_update_lobes()


func _build_convergence_knot() -> void:
	var combiner := CSGCombiner3D.new()
	combiner.name = "TentacleConvergenceKnot"
	add_child(combiner)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xE1D817C
	var anatomy := [
		[Vector3(-0.08, 0.02, 0.02), 0.72, Vector3(1.0, 0.78, 0.92)],
		[Vector3(0.42, 0.2, 0.18), 0.52, Vector3(0.92, 1.05, 0.82)],
		[Vector3(-0.3, -0.3, 0.25), 0.48, Vector3(1.08, 0.82, 0.9)],
	]
	for index in mini(core_lobe_count, anatomy.size()):
		var datum: Array = anatomy[index]
		var lobe := CSGSphere3D.new()
		lobe.name = "KnotLobe_%02d" % index
		lobe.operation = CSGShape3D.OPERATION_UNION
		lobe.radius = datum[1]
		lobe.radial_segments = 14
		lobe.rings = 9
		var base_position: Vector3 = datum[0] + Vector3(
			rng.randf_range(-0.035, 0.035),
			rng.randf_range(-0.03, 0.03),
			rng.randf_range(-0.035, 0.035)
		)
		var base_scale: Vector3 = datum[2]
		lobe.position = base_position
		lobe.scale = base_scale
		lobe.rotation = Vector3(
			rng.randf_range(-0.16, 0.16),
			rng.randf_range(-0.18, 0.18),
			rng.randf_range(-0.14, 0.14)
		)
		lobe.material = FLESH_MATERIAL
		lobe.add_to_group("monster_flesh")
		combiner.add_child(lobe)
		_lobes.append(lobe)
		_base_positions.append(base_position)
		_base_scales.append(base_scale)
		_phases.append(rng.randf_range(0.0, TAU))
		_speeds.append(rng.randf_range(0.38, 0.72))
		var noise := FastNoiseLite.new()
		noise.seed = 0x51A7 + index * 3571
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = rng.randf_range(0.16, 0.24)
		_noises.append(noise)


func _build_cyclopean_face() -> void:
	_eye_root = Node3D.new()
	_eye_root.name = "CyclopeanFace"
	add_child(_eye_root)

	var socket := MeshInstance3D.new()
	socket.name = "EyeSocket"
	var socket_mesh := TorusMesh.new()
	socket_mesh.inner_radius = 0.34
	socket_mesh.outer_radius = 0.51
	socket_mesh.rings = 20
	socket_mesh.ring_segments = 8
	socket_mesh.material = FLESH_MATERIAL
	socket.mesh = socket_mesh
	socket.position = Vector3(0.0, 0.19, -0.63)
	socket.rotation.x = PI * 0.5
	socket.scale = Vector3(1.0, 1.0, 0.72)
	socket.add_to_group("monster_flesh")
	_eye_root.add_child(socket)

	var eye := MeshInstance3D.new()
	eye.name = "UnblinkingEye"
	var eye_mesh := QuadMesh.new()
	eye_mesh.size = eye_scale
	_eye_material = ShaderMaterial.new()
	_eye_material.shader = EYE_SHADER
	eye_mesh.material = _eye_material
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 0.19, -0.738)
	_eye_root.add_child(eye)

	_build_hollow_mouth()

	_upper_teeth = Node3D.new()
	_upper_teeth.name = "UpperTeeth"
	_upper_teeth.position = Vector3(0.0, -0.25, -0.755)
	_eye_root.add_child(_upper_teeth)
	_lower_teeth = Node3D.new()
	_lower_teeth.name = "LowerTeeth"
	_lower_teeth.position = Vector3(0.0, -0.51, -0.755)
	_eye_root.add_child(_lower_teeth)
	_build_teeth_row(_upper_teeth, false)
	_build_teeth_row(_lower_teeth, true)


func _build_hollow_mouth() -> void:
	_mouth_root = Node3D.new()
	_mouth_root.name = "HollowMouth"
	_mouth_root.position = Vector3(0.0, -0.38, 0.0)
	_eye_root.add_child(_mouth_root)

	var rim := MeshInstance3D.new()
	rim.name = "MouthRim"
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.36
	rim_mesh.outer_radius = 0.51
	rim_mesh.rings = 24
	rim_mesh.ring_segments = 9
	rim_mesh.material = FLESH_MATERIAL
	rim.mesh = rim_mesh
	rim.position.z = -0.67
	rim.rotation.x = PI * 0.5
	rim.scale = Vector3(1.0, 1.0, 0.54)
	rim.add_to_group("monster_flesh")
	_mouth_root.add_child(rim)

	var tunnel := MeshInstance3D.new()
	tunnel.name = "ThroatCavity"
	var tunnel_mesh := CylinderMesh.new()
	tunnel_mesh.top_radius = 0.46
	tunnel_mesh.bottom_radius = 0.1
	tunnel_mesh.height = 0.76
	tunnel_mesh.radial_segments = 24
	tunnel_mesh.rings = 5
	tunnel_mesh.cap_top = false
	tunnel_mesh.cap_bottom = false
	var cavity_material := StandardMaterial3D.new()
	cavity_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cavity_material.cull_mode = BaseMaterial3D.CULL_FRONT
	cavity_material.albedo_color = Color(0.012, 0.0, 0.018, 1.0)
	cavity_material.emission_enabled = true
	cavity_material.emission = Color(0.055, 0.0, 0.08)
	cavity_material.emission_energy_multiplier = 0.9
	tunnel_mesh.material = cavity_material
	tunnel.mesh = tunnel_mesh
	tunnel.position.z = -1.0
	tunnel.rotation.x = PI * 0.5
	tunnel.scale = Vector3(1.0, 1.0, 0.54)
	_mouth_root.add_child(tunnel)

	var throat_eye := MeshInstance3D.new()
	throat_eye.name = "ThroatWeakpointGlow"
	var throat_mesh := SphereMesh.new()
	throat_mesh.radius = 0.12
	throat_mesh.height = 0.24
	throat_mesh.radial_segments = 16
	throat_mesh.rings = 8
	_throat_material = StandardMaterial3D.new()
	_throat_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_throat_material.albedo_color = Color(0.02, 0.16, 0.34, 1.0)
	_throat_material.emission_enabled = true
	_throat_material.emission = Color(0.03, 0.42, 1.0)
	_throat_material.emission_energy_multiplier = 0.25
	throat_mesh.material = _throat_material
	throat_eye.mesh = throat_mesh
	throat_eye.position = Vector3(0.0, 0.0, -1.38)
	throat_eye.scale = Vector3(1.0, 0.72, 0.45)
	_mouth_root.add_child(throat_eye)


func _build_teeth_row(row: Node3D, points_up: bool) -> void:
	var tooth_material := StandardMaterial3D.new()
	tooth_material.albedo_color = Color(0.56, 0.51, 0.4)
	tooth_material.roughness = 0.72
	tooth_material.emission_enabled = true
	tooth_material.emission = Color(0.09, 0.035, 0.012)
	tooth_material.emission_energy_multiplier = 0.55
	for index in tooth_count:
		var normalized := float(index) / maxf(float(tooth_count - 1), 1.0)
		var x := lerpf(-0.39, 0.39, normalized)
		var edge := absf(normalized - 0.5) * 2.0
		var tooth := MeshInstance3D.new()
		tooth.name = "Tooth_%02d" % index
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = lerpf(0.045, 0.027, edge)
		mesh.height = lerpf(0.19, 0.1, edge) * (0.82 + fmod(float(index) * 0.37, 0.3))
		mesh.radial_segments = 5
		mesh.rings = 1
		mesh.material = tooth_material
		tooth.mesh = mesh
		tooth.position = Vector3(x, edge * 0.055 * (-1.0 if points_up else 1.0), 0.0)
		tooth.rotation.z = (PI if points_up else 0.0) + x * (0.38 if points_up else -0.38)
		row.add_child(tooth)


func _update_face(delta: float) -> void:
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.4, 5.8) / (1.0 + _agitation * 0.6)
		var blink_tween := create_tween()
		blink_tween.tween_method(_set_blink, 0.0, 1.0, 0.075)
		blink_tween.tween_method(_set_blink, 1.0, 0.0, 0.12)
	_eye_material.set_shader_parameter("agitation", _agitation)
	var jaw_open := (0.12 + _agitation * 0.48 + _mouth_exposure * 0.7) * jaw_open_distance
	_upper_teeth.position.y = -0.27 + jaw_open * 0.25
	_lower_teeth.position.y = -0.49 - jaw_open * 0.25
	_mouth_root.scale = Vector3(1.0, 0.72 + jaw_open * 1.4, 1.0)
	_throat_material.emission_energy_multiplier = lerpf(0.25, 6.0, _mouth_exposure)
	_eye_root.rotation.z = sin(_time * (0.58 + _agitation * 1.8)) * (0.025 + _agitation * 0.035)


func _set_blink(value: float) -> void:
	_blink = value
	if _eye_material != null:
		_eye_material.set_shader_parameter("blink", value)


func _update_lobes() -> void:
	for index in _lobes.size():
		var noise := _noises[index]
		var phase := _phases[index]
		var speed := _speeds[index]
		var speed_multiplier := 1.0 + _agitation * 0.75
		var amplitude_multiplier := 1.0 + _agitation * 0.65
		var sample_time := _time * speed * speed_multiplier
		var swelling: float = noise.get_noise_1d(sample_time + phase * 4.0) * pulse_amount * amplitude_multiplier
		swelling += sin(_time * speed * 0.68 * speed_multiplier + phase) * pulse_amount * 0.38 * amplitude_multiplier
		var cross: float = noise.get_noise_1d(sample_time * 0.71 + 51.0) * pulse_amount * 0.52 * amplitude_multiplier
		_lobes[index].scale = _base_scales[index] * Vector3(
			1.0 + swelling,
			1.0 - swelling * 0.48 + cross,
			1.0 + swelling * 0.62 - cross * 0.3
		)
		_lobes[index].position = _base_positions[index] + Vector3(
			noise.get_noise_1d(sample_time * 0.53 + 17.0),
			noise.get_noise_1d(sample_time * 0.47 + 73.0),
			noise.get_noise_1d(sample_time * 0.41 + 131.0)
		) * drift_amount * amplitude_multiplier


func _update_knot_transform(delta: float) -> void:
	var breath := sin(_time * 0.92) * 0.075
	var cross_breath := sin(_time * 0.61 + 1.7) * 0.035
	var active_tremor := sin(_time * 3.1 + 0.4) * 0.018 * _agitation
	var target_scale := _base_scale * Vector3(
		1.0 + breath + active_tremor,
		1.0 - breath * 0.52 + cross_breath,
		1.0 + breath * 0.7 - cross_breath * 0.3
	)
	var target_position := _base_position + Vector3(
		sin(_time * 0.47 + 0.8) * 0.025,
		sin(_time * 0.73) * 0.035 + active_tremor * 0.7,
		cos(_time * 0.39 + 1.2) * 0.022
	)
	var target_rotation := _base_rotation + Vector3(
		sin(_time * 0.43) * 0.055,
		sin(_time * 0.31 + 1.1) * 0.065,
		cos(_time * 0.37 + 2.0) * 0.05
	)
	var response := 1.0 - exp(-7.0 * delta)
	scale = scale.lerp(target_scale, response)
	position = position.lerp(target_position, response)
	rotation = rotation.lerp(target_rotation, response)


func _on_attack_phase_changed(attack_name: StringName, phase_name: StringName, _duration: float) -> void:
	_mouth_exposure_target = 1.0 if attack_name in [&"Fleshy Shrapnel", &"Eye Swarm"] and phase_name in [&"TELEGRAPH", &"ACTIVE"] else 0.0
	match phase_name:
		&"TELEGRAPH": _agitation_target = 0.55
		&"ACTIVE": _agitation_target = 1.0
		&"RECOVERY": _agitation_target = 0.32
		_: _agitation_target = 0.0
