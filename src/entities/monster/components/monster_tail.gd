class_name MonsterTail
extends MeshInstance3D
## Rendering-only trailing anatomy. The chain retains its own world-space state
## while the core moves, and reacts to public attack events without owning damage.

@export_category("Shape")
@export_range(8, 32) var segment_count := 20
@export_range(4, 12) var radial_sides := 8
@export var segment_length := 0.62
@export var root_radius := 0.58
@export var tip_radius := 0.045
@export_category("Motion")
@export var gravity := 1.8
@export var damping := 5.5
@export var idle_sway := 1.4
@export_range(1, 8) var constraint_iterations := 4

var _tail_mesh := ImmediateMesh.new()
var _points: PackedVector3Array = PackedVector3Array()
var _velocities: PackedVector3Array = PackedVector3Array()
var _time := 0.0
var _phase_elapsed := 0.0
var _phase_duration := 1.0
var _sweep_phase := &"IDLE"
var _player_position := Vector3.ZERO


func _ready() -> void:
	mesh = _tail_mesh
	_reset_chain()
	SignalBus.player_position_updated.connect(_on_player_position_updated)
	SignalBus.attack_phase_changed.connect(_on_attack_phase_changed)


func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position_updated):
		SignalBus.player_position_updated.disconnect(_on_player_position_updated)
	if SignalBus.attack_phase_changed.is_connected(_on_attack_phase_changed):
		SignalBus.attack_phase_changed.disconnect(_on_attack_phase_changed)


func _physics_process(delta: float) -> void:
	_time += delta
	_phase_elapsed += delta
	if _points.size() != segment_count + 1:
		_reset_chain()
	_update_chain(delta)
	_redraw_tail()


func _reset_chain() -> void:
	_points.resize(segment_count + 1)
	_velocities.resize(segment_count + 1)
	var root := global_position
	var outward := (global_basis * Vector3.BACK).normalized()
	for index in segment_count + 1:
		_points[index] = root + outward * segment_length * float(index)
		_velocities[index] = Vector3.ZERO


func _update_chain(delta: float) -> void:
	var root := global_position
	var previous_points := _points.duplicate()
	_points[0] = root
	_velocities[0] = Vector3.ZERO
	for index in range(1, _points.size()):
		var t := float(index) / float(segment_count)
		var phase := _time * (1.1 + t * 0.45) - t * 5.2
		var sway_force := Vector3(sin(phase), cos(phase * 0.73) * 0.25, cos(phase)) * idle_sway * t
		_velocities[index] += (Vector3.DOWN * gravity + sway_force) * delta
		_velocities[index] *= exp(-damping * delta)
		_points[index] += _velocities[index] * delta

	for _iteration in constraint_iterations:
		_points[0] = root
		for index in range(1, _points.size()):
			var offset := _points[index] - _points[index - 1]
			if offset.length_squared() < 0.0001:
				offset = (global_basis * Vector3.BACK).normalized() * segment_length
			_points[index] = _points[index - 1] + offset.normalized() * segment_length

	_apply_attack_pose(root, delta)
	for index in range(1, _points.size()):
		_velocities[index] = (_points[index] - previous_points[index]) / maxf(delta, 0.001)


func _apply_attack_pose(root: Vector3, delta: float) -> void:
	var pose_weight := 0.0
	match _sweep_phase:
		&"TELEGRAPH": pose_weight = minf(_phase_elapsed / maxf(_phase_duration * 0.55, 0.01), 1.0) * 0.9
		&"ACTIVE": pose_weight = 0.98
		&"RECOVERY": pose_weight = 0.7 * (1.0 - minf(_phase_elapsed / maxf(_phase_duration, 0.01), 1.0))
	if pose_weight <= 0.0:
		return

	var up := Vector3.UP
	var forward := (_player_position - root).slide(up).normalized()
	if forward.length_squared() < 0.01:
		forward = (global_basis * Vector3.FORWARD).slide(up).normalized()
	var side := up.cross(forward).normalized()
	var active_progress := clampf(_phase_elapsed / maxf(_phase_duration, 0.01), 0.0, 1.0)
	for index in range(1, _points.size()):
		var t := float(index) / float(segment_count)
		var target := root
		if _sweep_phase == &"TELEGRAPH":
			var coil_angle := t * TAU * 1.35 + _time * 0.35
			var coil_radius := segment_length * float(segment_count) * t * 0.22
			target += (forward * cos(coil_angle) + side * sin(coil_angle)) * coil_radius
			target += up * sin(t * PI) * 0.65
		else:
			var sweep_angle := lerpf(-2.15, 2.15, smoothstep(0.0, 1.0, active_progress))
			var trailing_angle := sweep_angle - (1.0 - t) * 0.8
			var reach := segment_length * float(segment_count) * t
			target += (forward * cos(trailing_angle) + side * sin(trailing_angle)) * reach
			target += up * sin(t * PI) * 0.42
		var response := 1.0 - exp(-18.0 * pose_weight * delta)
		_points[index] = _points[index].lerp(target, response)


func _redraw_tail() -> void:
	_tail_mesh.clear_surfaces()
	_tail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in segment_count:
		var t_a := float(index) / float(segment_count)
		var t_b := float(index + 1) / float(segment_count)
		var radius_a := lerpf(root_radius, tip_radius, pow(t_a, 0.72))
		var radius_b := lerpf(root_radius, tip_radius, pow(t_b, 0.72))
		_add_tube_segment(to_local(_points[index]), to_local(_points[index + 1]), radius_a, radius_b)
	_tail_mesh.surface_end()


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


func _add_triangle(a: Vector3, b: Vector3, c: Vector3, normal_a: Vector3, normal_b: Vector3, normal_c: Vector3) -> void:
	_tail_mesh.surface_set_normal(normal_a)
	_tail_mesh.surface_add_vertex(a)
	_tail_mesh.surface_set_normal(normal_b)
	_tail_mesh.surface_add_vertex(b)
	_tail_mesh.surface_set_normal(normal_c)
	_tail_mesh.surface_add_vertex(c)


func _on_player_position_updated(position_value: Vector3) -> void:
	_player_position = position_value


func _on_attack_phase_changed(attack_name: StringName, phase_name: StringName, duration: float) -> void:
	if attack_name in [&"Tail Sweep", &"Anchor Sweep"]:
		_sweep_phase = phase_name
		_phase_elapsed = 0.0
		_phase_duration = maxf(duration, 0.01)
	elif phase_name == &"IDLE" or phase_name == &"TELEGRAPH":
		_sweep_phase = &"IDLE"
		_phase_elapsed = 0.0
