class_name PassiveSlimeTendrils
extends MeshInstance3D
## Rendering-only sensory feelers. Locomotion remains owned by MonsterLegAnchor.

@export var tendril_count := 9
@export var curve_sections := 9
@export var radial_sides := 8
@export var base_radius := 0.22
@export var min_length := 1.6
@export var max_length := 3.7

var _mesh := ImmediateMesh.new()
var _time := 0.0
var _player_position := Vector3.ZERO
var _attack_target := Vector3.ZERO
var _attack_name := &""
var _attack_phase := &"IDLE"
var _phase_elapsed := 0.0
var _phase_duration := 0.0

func _ready() -> void:
	mesh = _mesh
	SignalBus.player_position_updated.connect(_on_player_position_updated)
	SignalBus.attack_telegraphed.connect(_on_attack_telegraphed)
	SignalBus.attack_phase_changed.connect(_on_attack_phase_changed)
	_redraw_tendrils()

func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position_updated):
		SignalBus.player_position_updated.disconnect(_on_player_position_updated)
	if SignalBus.attack_telegraphed.is_connected(_on_attack_telegraphed):
		SignalBus.attack_telegraphed.disconnect(_on_attack_telegraphed)
	if SignalBus.attack_phase_changed.is_connected(_on_attack_phase_changed):
		SignalBus.attack_phase_changed.disconnect(_on_attack_phase_changed)

func _process(delta: float) -> void:
	_time += delta
	_phase_elapsed += delta
	_redraw_tendrils()

func _redraw_tendrils() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in tendril_count:
		_draw_tendril(index)
	_mesh.surface_end()

func _draw_tendril(index: int) -> void:
	var phase := float(index) * 2.39996
	var side_bias := sin(phase * 1.7) * 0.28
	var origin := Vector3(cos(phase) * 1.48, -0.52 + sin(phase * 1.31) * 0.52, sin(phase) * 1.55)
	var direction := Vector3(cos(phase), -0.18 + side_bias, sin(phase)).normalized()
	var local_player := to_local(_player_position) - origin
	var local_attack_target := to_local(_attack_target) - origin
	var player_proximity := 1.0 - smoothstep(4.0, 14.0, local_player.length())
	if index % 3 == 0 and local_player.length_squared() > 0.01:
		direction = direction.slerp(local_player.normalized(), player_proximity * 0.34).normalized()
	var individual_speed := 0.78 + 0.24 * (0.5 + 0.5 * sin(phase * 1.83))
	var reach_pulse := 0.92 + sin(_time * individual_speed * 0.72 + phase * 0.63) * 0.1
	var length_value := lerpf(min_length, max_length, 0.5 + 0.5 * sin(phase * 2.17)) * reach_pulse
	var droop := Vector3.DOWN * (0.65 + 0.45 * sin(phase))
	var whip_amount := _whip_amount()
	if _attack_name == &"Tendril Whip" and local_attack_target.length_squared() > 0.01:
		direction = direction.slerp(local_attack_target.normalized(), whip_amount).normalized()
		var target_reach := clampf(local_attack_target.length(), min_length, 16.0)
		length_value = lerpf(length_value, target_reach, whip_amount)
		droop *= 1.0 - whip_amount * 0.8
	var previous := origin
	for section in curve_sections:
		var t := float(section + 1) / float(curve_sections)
		var tip_activity := smoothstep(0.18, 1.0, t)
		var wave := Vector3(
			sin(_time * (1.2 + player_proximity) * individual_speed + phase + t * 5.0),
			cos(_time * 0.85 * individual_speed + phase * 1.3 + t * 4.0),
			sin(_time * (1.05 + player_proximity * 0.65) - phase + t * 3.0)
		) * (0.14 + tip_activity * (0.34 + player_proximity * 0.18))
		var point := origin + direction * length_value * t + droop * t * t + wave * t
		if _attack_name == &"Tendril Whip" and whip_amount > 0.01:
			var attack_side := direction.cross(Vector3.UP)
			if attack_side.length_squared() < 0.01:
				attack_side = direction.cross(Vector3.RIGHT)
			attack_side = attack_side.normalized()
			var strand_offset := (float(index) - float(tendril_count - 1) * 0.5) * 0.22
			var coil := sin(t * PI) * sin(phase + _time * 5.0) * (1.0 - whip_amount) * 1.2
			point += attack_side * (strand_offset * t + coil)
		var pulse_a := 1.0 + sin(_time * 2.4 - t * 8.0 + phase) * 0.09 * (1.0 - t)
		var pulse_b := 1.0 + sin(_time * 2.4 - t * 8.0 - 0.4 + phase) * 0.09 * (1.0 - t)
		var radius_a := base_radius * pow(1.0 - float(section) / float(curve_sections), 1.3) * pulse_a
		var radius_b := base_radius * pow(maxf(1.0 - t, 0.08), 1.3) * pulse_b
		_add_tube_segment(previous, point, radius_a, radius_b)
		previous = point

func _on_player_position_updated(position_value: Vector3) -> void:
	_player_position = position_value


func _on_attack_telegraphed(attack_name: StringName, world_position: Vector3, duration: float) -> void:
	if attack_name != &"Tendril Whip":
		return
	_attack_name = attack_name
	_attack_target = world_position
	_attack_phase = &"TELEGRAPH"
	_phase_elapsed = 0.0
	_phase_duration = maxf(duration, 0.01)


func _on_attack_phase_changed(attack_name: StringName, phase_name: StringName, duration: float) -> void:
	if attack_name != &"Tendril Whip" and phase_name != &"IDLE":
		return
	_attack_name = attack_name
	_attack_phase = phase_name
	_phase_elapsed = 0.0
	_phase_duration = maxf(duration, 0.01)


func _whip_amount() -> float:
	if _attack_name != &"Tendril Whip":
		return 0.0
	var progress := clampf(_phase_elapsed / maxf(_phase_duration, 0.01), 0.0, 1.0)
	match _attack_phase:
		&"TELEGRAPH":
			# Gather slowly, making the target lock readable before the snap.
			return smoothstep(0.0, 1.0, progress) * 0.48
		&"ACTIVE":
			return lerpf(0.48, 1.0, 1.0 - pow(1.0 - progress, 4.0))
		&"RECOVERY":
			return 1.0 - smoothstep(0.0, 1.0, progress)
	return 0.0

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
