class_name MonsterLegAnchor
extends Node3D
## Independent locomotion limb. It owns surface acquisition and visual resolution;
## the monster core only consumes its public anchor state.

signal step_started(leg: MonsterLegAnchor)
signal step_finished(leg: MonsterLegAnchor)

@export_category("Reach And Gait")
@export var max_leg_length := 16.0
@export var step_threshold := 3.4
@export var step_height := 1.8
@export var step_duration := 0.28
@export var probe_interval := 0.07
@export var probe_outward_distance := 8.2
@export var probe_surface_depth := 10.5
@export var locomotion_reach_bias := 7.0
@export_category("Shape")
@export var upper_radius := 0.46
@export var lower_radius := 0.026
@export var knee_lift := 1.75
@export var probe_spread := 1.3
@export var curl_amount := 0.82
@export var idle_twitch := 0.18
@export var body_overlap_depth := 1.9
@export var front_activation_distance := 11.0
@export var front_reactivity := 0.62
@export_range(8, 24) var curve_sections := 18
@export_range(6, 12) var tube_sides := 8
@export_range(0.0, 0.2) var ridge_strength := 0.0
@export_range(0.15, 1.0) var ribbon_flatness := 0.64
@export_category("Procedural Motion")
@export_range(4, 10) var fabrik_joint_count := 9
@export_range(1, 8) var fabrik_iterations := 4
@export var chain_spring := 74.0
@export var chain_damping := 7.2
@export var max_chain_speed := 22.0
@export var noise_amplitude := 0.68
@export var behavior_interval_min := 4.0
@export var behavior_interval_max := 9.0
@export_range(0.75, 1.0) var hard_reach_ratio := 0.94
@export_category("Muscular Pull")
@export var load_response := 7.0
@export_range(0.0, 1.0) var loaded_curl_retention := 0.16
@export_range(0.0, 0.5) var loaded_root_thickening := 0.24

@onready var raycast: RayCast3D = $RayCast3D
@onready var foot_marker: Marker3D = $Marker3D
@onready var leg_mesh: MeshInstance3D = $MeshInstance3D

var mesh := ArrayMesh.new()

var debug_view := false

var current_foot_global_pos := Vector3.ZERO
var target_foot_global_pos := Vector3.ZERO
var surface_normal := Vector3.UP
var is_stepping := false
var is_planted := false
var can_step := true
## Smoothed load written by the core. Rendering consumes this value, but never
## feeds transforms back into locomotion.
var pull_load := 0.0

var _step_elapsed := 0.0
var _step_origin := Vector3.ZERO
var _motion_time := 0.0
var _phase_offset := 0.0
var _probe_elapsed := 0.0
var _outward_local := Vector3.FORWARD
var _surface_direction := Vector3.UP
var _locomotion_intent := Vector3.ZERO
var _pull_load_target := 0.0
var _is_front_limb := false
var _player_position := Vector3.ZERO
var _collision_exception := RID()
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _anatomy_seed := 0
var _chain_points: Array[Vector3] = []
var _chain_velocities: Array[Vector3] = []
var _behavior_timer := 0.0
var _behavior_remaining := 0.0
var _behavior := 0
var _curl_direction := 1.0
var _resting_curl := 0.6
var _grasp_amount := 0.0
var _grasp_target := 0.0
var _is_grasping_limb := false
var _debug_sphere: MeshInstance3D
var _debug_line: MeshInstance3D
var _debug_material: StandardMaterial3D

enum LimbBehavior { IDLE, CURL, TAP, PROBE }


func _ready() -> void:
	if _anatomy_seed == 0:
		configure_anatomy(0x51A7 + get_index() * 7919, 1.0, 1.0)
	_probe_elapsed = fmod(_phase_offset * 0.019, maxf(probe_interval, 0.01))
	_is_front_limb = position.z < -0.35
	var radial_parent := Vector3(position.x, 0.0, position.z)
	if radial_parent.length_squared() < 0.01:
		radial_parent = Vector3.FORWARD
	_outward_local = (transform.basis.inverse() * radial_parent.normalized()).normalized()
	_find_collision_exception()
	leg_mesh.mesh = mesh
	SignalBus.player_position_updated.connect(_on_player_position_updated)
	SignalBus.attack_phase_changed.connect(_on_attack_phase_changed)
	set_surface_direction(Vector3.UP)
	# Surface acquisition uses the batched/scored direct queries below. Keeping this
	# helper enabled would add one unused physics ray per limb on every physics tick.
	raycast.enabled = false
	current_foot_global_pos = global_position
	target_foot_global_pos = global_position
	# The procedural arena creates collision after its children enter the tree. A
	# deferred probe prevents a missed ready-time ray from becoming a fake anchor.
	call_deferred("force_probe", true)


func configure_anatomy(seed_value: int, length_scale: float, thickness_scale: float) -> void:
	_anatomy_seed = seed_value
	_rng.seed = seed_value
	_phase_offset = _rng.randf_range(0.0, TAU)
	_noise.seed = seed_value
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = _rng.randf_range(0.22, 0.38)
	_curl_direction = -1.0 if _rng.randf() < 0.5 else 1.0
	_is_grasping_limb = posmod(seed_value, 3) == 0
	max_leg_length *= length_scale
	probe_outward_distance *= length_scale
	upper_radius *= thickness_scale
	lower_radius *= lerpf(1.0, thickness_scale, 0.55)
	_resting_curl = max_leg_length * _rng.randf_range(0.18, 0.34)
	step_duration *= _rng.randf_range(0.88, 1.18)
	_idle_chain_reset()
	_behavior_timer = _rng.randf_range(behavior_interval_min, behavior_interval_max)
	var radial_parent := Vector3(position.x, 0.0, position.z)
	if radial_parent.length_squared() < 0.01:
		radial_parent = Vector3.FORWARD
	_outward_local = (transform.basis.inverse() * radial_parent.normalized()).normalized()


func _idle_chain_reset() -> void:
	_chain_points.clear()
	_chain_velocities.clear()
	for joint in fabrik_joint_count:
		_chain_points.append(Vector3.ZERO)
		_chain_velocities.append(Vector3.ZERO)


func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position_updated):
		SignalBus.player_position_updated.disconnect(_on_player_position_updated)
	if SignalBus.attack_phase_changed.is_connected(_on_attack_phase_changed):
		SignalBus.attack_phase_changed.disconnect(_on_attack_phase_changed)


func _physics_process(delta: float) -> void:
	_motion_time += delta
	pull_load = lerpf(pull_load, _pull_load_target, 1.0 - exp(-load_response * delta))
	_grasp_amount = move_toward(_grasp_amount, _grasp_target, delta * (3.2 if _grasp_target > _grasp_amount else 2.0))
	_update_independent_behavior(delta)
	_probe_elapsed += delta
	_enforce_hard_reach_limit()
	if is_stepping:
		_update_step(delta)
	elif is_planted:
		_probe_for_step()
	else:
		_update_surface_search(delta)
	foot_marker.global_position = current_foot_global_pos
	_align_foot()
	leg_mesh.visible = not debug_view
	if debug_view:
		_draw_debug_view()
	else:
		if _debug_sphere != null:
			_debug_sphere.visible = false
			_debug_line.visible = false
		_draw_jointed_leg(delta)


## An anchor is a contact constraint, not an infinitely extensible cable. Drop it
## even when the surface probe misses so a stale point can never trail the body.
func _enforce_hard_reach_limit() -> void:
	var offset := current_foot_global_pos - global_position
	var hard_reach := max_leg_length * hard_reach_ratio
	if offset.length() <= hard_reach:
		return
	current_foot_global_pos = global_position + offset.normalized() * hard_reach
	target_foot_global_pos = current_foot_global_pos
	if is_planted or is_stepping:
		is_planted = false
		is_stepping = false
		_step_elapsed = 0.0
		_probe_elapsed = probe_interval
		_chain_velocities.fill(Vector3.ZERO)


func _update_independent_behavior(delta: float) -> void:
	if _locomotion_intent.length_squared() > 0.01:
		_behavior = LimbBehavior.IDLE
		_behavior_remaining = 0.0
		_behavior_timer = maxf(_behavior_timer, behavior_interval_min * 0.5)
		return
	if _behavior_remaining > 0.0:
		_behavior_remaining -= delta
		if _behavior_remaining <= 0.0:
			_behavior = LimbBehavior.IDLE
			_behavior_timer = _rng.randf_range(behavior_interval_min, behavior_interval_max)
		return
	_behavior_timer -= delta
	if _behavior_timer <= 0.0:
		_behavior = _rng.randi_range(LimbBehavior.CURL, LimbBehavior.PROBE)
		_behavior_remaining = _rng.randf_range(0.7, 1.8)


func _find_collision_exception() -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is CollisionObject3D:
			_collision_exception = (ancestor as CollisionObject3D).get_rid()
			raycast.add_exception(ancestor)
			return
		ancestor = ancestor.get_parent()


func _set_initial_foot(point: Vector3, normal: Vector3) -> void:
	current_foot_global_pos = point
	target_foot_global_pos = point
	surface_normal = normal.normalized()
	is_stepping = false
	is_planted = true


func _probe_for_step() -> void:
	if _probe_elapsed < probe_interval:
		return
	_probe_elapsed = 0.0
	var overstretched := global_position.distance_to(current_foot_global_pos) > max_leg_length * 0.82
	var hit := _find_surface_candidate()
	if hit.is_empty():
		if overstretched:
			is_planted = false
			current_foot_global_pos = global_position + (current_foot_global_pos - global_position).limit_length(max_leg_length * 0.88)
		return
	var candidate: Vector3 = hit.position
	var target_shifted := current_foot_global_pos.distance_to(candidate) > step_threshold
	var changed_surface := surface_normal.dot(hit.normal) < 0.78
	if can_step and (overstretched or target_shifted or changed_surface):
		request_step(candidate, hit.normal)


func request_step(point: Vector3, normal: Vector3, instant := false) -> void:
	if is_stepping or not can_step:
		return
	if instant:
		_set_initial_foot(point, normal)
		return
	is_stepping = true
	is_planted = false
	_pull_load_target = 0.0
	_step_elapsed = 0.0
	_step_origin = current_foot_global_pos
	target_foot_global_pos = point
	surface_normal = normal.normalized()
	step_started.emit(self)


func release() -> void:
	is_stepping = false
	is_planted = false
	can_step = false
	_pull_load_target = 0.0


func enable_planting() -> void:
	can_step = true
	force_probe()


func force_probe(instant := false) -> bool:
	can_step = true
	_probe_elapsed = 0.0
	var hit := _find_surface_candidate()
	if hit.is_empty():
		return false
	request_step(hit.position, hit.normal, instant)
	return true


func set_surface_direction(normal: Vector3) -> void:
	if normal.length_squared() < 0.01:
		return
	_surface_direction = normal.normalized()
	var local_normal := global_basis.inverse() * _surface_direction
	raycast.target_position = _outward_local * probe_outward_distance - local_normal * probe_surface_depth


## Movement intent never moves the foot or body directly. It only moves the next
## surface-search region ahead of the current support polygon.
func set_locomotion_intent(intent: Vector3, strength := 1.0) -> void:
	var along_surface := intent.slide(_surface_direction)
	if along_surface.length_squared() < 0.01:
		_locomotion_intent = Vector3.ZERO
		return
	_locomotion_intent = along_surface.normalized() * clampf(strength, 0.0, 1.75)


## The core assigns load from fixed contact geometry. Keeping this as a scalar
## lets the visual chain show tension without coupling mesh code to body motion.
func set_pull_load(value: float) -> void:
	_pull_load_target = clampf(value, 0.0, 1.0) if is_planted else 0.0


func get_pull_score(body_position: Vector3, travel_intent: Vector3, support: Vector3) -> float:
	if not is_planted:
		return 0.0
	var travel := travel_intent.slide(support).normalized()
	if travel.length_squared() < 0.01:
		return 0.0
	var to_anchor := (current_foot_global_pos - body_position).slide(support)
	if to_anchor.length_squared() < 0.01:
		return 0.1
	var forward_amount := clampf(to_anchor.normalized().dot(travel), -1.0, 1.0)
	var extension := clampf(body_position.distance_to(current_foot_global_pos) / maxf(max_leg_length, 0.01), 0.0, 1.0)
	return smoothstep(-0.25, 0.65, forward_amount) * smoothstep(0.16, 0.68, extension)


func _find_surface_candidate() -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}
	var outward := (global_basis * _outward_local).normalized()
	var support := _surface_direction.normalized()
	var lateral := support.cross(outward).normalized()
	if lateral.length_squared() < 0.01:
		lateral = outward.cross(Vector3.UP).normalized()
	if lateral.length_squared() < 0.01:
		lateral = Vector3.RIGHT

	var reach_advance := _locomotion_intent * locomotion_reach_bias
	var desired_offset := outward * probe_outward_distance + reach_advance - support * probe_surface_depth
	var ray_offsets: Array[Vector3] = [
		desired_offset,
		outward.rotated(support, 0.48) * probe_outward_distance + reach_advance - support * probe_surface_depth,
		outward.rotated(support, -0.48) * probe_outward_distance + reach_advance - support * probe_surface_depth,
		(outward * 0.9 + lateral * 0.55 + reach_advance / maxf(locomotion_reach_bias, 0.01) - support * 0.72).normalized() * max_leg_length,
		(outward * 0.9 - lateral * 0.55 + reach_advance / maxf(locomotion_reach_bias, 0.01) - support * 0.72).normalized() * max_leg_length,
		outward * max_leg_length,
		(reach_advance - support * max_leg_length).limit_length(max_leg_length),
		Vector3.DOWN * max_leg_length,
		Vector3.UP * max_leg_length,
	]
	# Planted feet only need the five gait-directed probes. Detached limbs retain
	# the broad fallback fan so recovery and corner acquisition stay robust.
	if is_planted:
		ray_offsets.resize(5)

	var origin := global_position
	var desired_point := origin + desired_offset
	var best_hit: Dictionary = {}
	var best_score := INF
	var space := get_world_3d().direct_space_state
	for offset in ray_offsets:
		if offset.length_squared() < 0.01:
			continue
		if offset.length() > max_leg_length:
			offset = offset.normalized() * max_leg_length
		var query := PhysicsRayQueryParameters3D.create(origin, origin + offset, raycast.collision_mask)
		query.collide_with_areas = raycast.collide_with_areas
		query.collide_with_bodies = raycast.collide_with_bodies
		if _collision_exception.is_valid():
			query.exclude = [_collision_exception]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var hit_normal: Vector3 = hit.normal.normalized()
		var score := (hit.position as Vector3).distance_to(desired_point)
		score += (1.0 - clampf(hit_normal.dot(support), -1.0, 1.0)) * 1.6
		if is_planted:
			score += (hit.position as Vector3).distance_to(current_foot_global_pos) * 0.12
		if score < best_score:
			best_score = score
			best_hit = {"position": hit.position, "normal": hit_normal}
	return best_hit


func _update_surface_search(delta: float) -> void:
	if can_step and _probe_elapsed >= probe_interval * 0.55:
		_probe_elapsed = 0.0
		var hit := _find_surface_candidate()
		if not hit.is_empty():
			request_step(hit.position, hit.normal)
			return
	# A detached limb actively tastes the nearby space instead of collapsing into
	# the body and appearing frozen while it waits for its gait slot.
	var outward := (global_basis * _outward_local).normalized()
	var support := _surface_direction
	var side := support.cross(outward).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var search_wave := sin(_motion_time * 2.8 + _phase_offset)
	var search_wave_b := cos(_motion_time * 2.05 + _phase_offset * 1.37)
	var searching_target := global_position
	searching_target += outward * (probe_outward_distance * 0.78)
	searching_target -= support * (probe_surface_depth * 0.46)
	searching_target += side * search_wave * 0.9 + support * search_wave_b * 0.42
	current_foot_global_pos = current_foot_global_pos.lerp(searching_target, 1.0 - exp(-6.0 * delta))
	surface_normal = support


func _update_step(delta: float) -> void:
	_step_elapsed += delta
	var t := clampf(_step_elapsed / maxf(step_duration, 0.01), 0.0, 1.0)
	# Fast extension and a crisp final plant read as an intentional throw/grab.
	var smooth_t := 1.0 - pow(1.0 - t, 3.0)
	current_foot_global_pos = _step_origin.lerp(target_foot_global_pos, smooth_t)
	current_foot_global_pos += surface_normal * sin(t * PI) * step_height * (1.0 - t * 0.35)
	if t >= 1.0:
		current_foot_global_pos = target_foot_global_pos
		is_stepping = false
		is_planted = true
		step_finished.emit(self)


## Movement-evaluation view: a state-colored sphere at the foot contact and a
## straight line back to the leg root, replacing the tentacle mesh entirely.
func _draw_debug_view() -> void:
	if _debug_sphere == null:
		_debug_material = StandardMaterial3D.new()
		_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_debug_material.no_depth_test = true
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.3
		sphere_mesh.height = 0.6
		sphere_mesh.material = _debug_material
		_debug_sphere = MeshInstance3D.new()
		_debug_sphere.mesh = sphere_mesh
		_debug_sphere.top_level = true
		add_child(_debug_sphere)
		_debug_line = MeshInstance3D.new()
		_debug_line.mesh = ImmediateMesh.new()
		_debug_line.material_override = _debug_material
		add_child(_debug_line)
	_debug_sphere.visible = true
	_debug_line.visible = true
	var color := Color.GREEN if is_planted else (Color.YELLOW if is_stepping else Color.RED)
	_debug_material.albedo_color = color
	_debug_sphere.global_position = current_foot_global_pos
	var line := _debug_line.mesh as ImmediateMesh
	line.clear_surfaces()
	line.surface_begin(Mesh.PRIMITIVE_LINES)
	line.surface_add_vertex(Vector3.ZERO)
	line.surface_add_vertex(to_local(current_foot_global_pos))
	line.surface_end()


func _align_foot() -> void:
	if surface_normal.length_squared() < 0.01:
		return
	var forward := global_basis.z.slide(surface_normal).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD.slide(surface_normal).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.RIGHT
	foot_marker.global_basis = Basis.looking_at(forward, surface_normal)


func _draw_jointed_leg(delta: float) -> void:
	var foot := to_local(current_foot_global_pos)
	foot = foot.limit_length(max_leg_length * hard_reach_ratio)
	var outward := foot.normalized()
	if outward.length_squared() < 0.01:
		outward = _outward_local
	var support_up := (global_basis.inverse() * surface_normal).normalized()
	if support_up.length_squared() < 0.01:
		support_up = Vector3.UP
	var side := outward.cross(support_up).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stretch_ratio := clampf(foot.length() / maxf(max_leg_length, 0.01), 0.0, 1.0)
	var tension_scale := lerpf(1.0, 0.68, smoothstep(0.55, 1.0, stretch_ratio))
	tension_scale *= 1.0 + pull_load * loaded_root_thickening
	var body_center_local := transform.affine_inverse() * Vector3.ZERO
	var root_start := body_center_local.normalized() * minf(body_overlap_depth, body_center_local.length() * 0.72)
	var solved_chain := _solve_fabrik_chain(root_start, foot, outward, support_up, side, delta)
	_draw_continuous_tentacle(tool, solved_chain, tension_scale)
	mesh.clear_surfaces()
	tool.commit(mesh)


func _solve_fabrik_chain(root: Vector3, foot: Vector3, outward: Vector3, support_up: Vector3, side: Vector3, delta: float) -> Array[Vector3]:
	if _chain_points.size() != fabrik_joint_count:
		_idle_chain_reset()
	var count := _chain_points.size()
	# Fixed rest length is the key anatomical constraint. Deriving this from the
	# current target distance made stale anchors turn the limb into elastic rope.
	var segment_length := maxf(max_leg_length * 1.04 / float(count - 1), 0.12)
	var target := foot
	var time_seed := _motion_time * 0.72 + _phase_offset * 3.17
	var layered := Vector3(
		_noise.get_noise_2d(time_seed, 11.3),
		_noise.get_noise_2d(time_seed * 0.71, 37.1),
		_noise.get_noise_2d(time_seed * 1.23, 73.7)
	)
	# A planted tip must remain pixel-stable at its physics contact. All secondary
	# noise is carried by the middle joints so the anchor never appears to float.
	var free_motion := 1.0 if not is_planted else 0.0
	target += (side * layered.x + support_up * layered.y + outward * layered.z) * noise_amplitude * free_motion
	var player_local := to_local(_player_position)
	if not is_planted and _is_grasping_limb and _grasp_amount > 0.01 and player_local.length_squared() > 0.01:
		var wrap_target := player_local.limit_length(max_leg_length * hard_reach_ratio)
		wrap_target += side * _curl_direction * _resting_curl * 0.62
		target = target.lerp(wrap_target, _grasp_amount * 0.78)
	if _behavior == LimbBehavior.PROBE and not is_planted:
		if player_local.length_squared() > 0.01:
			target = foot.lerp(player_local.limit_length(max_leg_length), 0.38)
	elif _behavior == LimbBehavior.TAP and not is_planted:
		target += support_up * absf(sin(_motion_time * 8.0 + _phase_offset)) * 0.7
	elif _behavior == LimbBehavior.CURL and not is_planted:
		target = root + outward * minf(root.distance_to(foot) * 0.45, max_leg_length * 0.4) + support_up * 0.55

	var desired: Array[Vector3] = []
	for joint in count:
		desired.append(root.lerp(target, float(joint) / float(count - 1)))
	for iteration in fabrik_iterations:
		desired[count - 1] = target
		for joint in range(count - 2, -1, -1):
			var direction := (desired[joint] - desired[joint + 1]).normalized()
			desired[joint] = desired[joint + 1] + direction * segment_length
		desired[0] = root
		for joint in range(1, count):
			var direction := (desired[joint] - desired[joint - 1]).normalized()
			desired[joint] = desired[joint - 1] + direction * segment_length

	for joint in range(1, count - 1):
		var t := float(joint) / float(count - 1)
		var phase_delay := t * 2.4
		var wave := sin(_motion_time * (1.15 + _noise.frequency) + _phase_offset - phase_delay)
		var curl_wave := cos(_motion_time * 0.83 + _phase_offset * 1.7 - phase_delay * 1.4)
		var curl_envelope := sin(t * PI)
		var loaded_curl := lerpf(1.0, loaded_curl_retention, pull_load)
		desired[joint] += side * _curl_direction * _resting_curl * curl_envelope * loaded_curl
		desired[joint] += side * wave * noise_amplitude * curl_envelope * loaded_curl
		desired[joint] += support_up * curl_wave * noise_amplitude * 0.55 * sin(t * PI) * loaded_curl
		if not is_planted and _grasp_amount > 0.01 and player_local.length_squared() > 0.01:
			var grasp_direction := (player_local - desired[joint]).normalized()
			desired[joint] += grasp_direction * _grasp_amount * (0.75 + _resting_curl * 0.35) * curl_envelope
		if not is_planted and _is_front_limb:
			var proximity := 1.0 - smoothstep(front_activation_distance * 0.3, front_activation_distance, player_local.length())
			if player_local.length_squared() > 0.01:
				desired[joint] += (player_local - desired[joint]).normalized() * front_reactivity * proximity * curl_envelope
		if not is_planted and _behavior == LimbBehavior.CURL:
			desired[joint] += side * sin(t * TAU) * curl_amount

	for joint in count:
		if _chain_points[joint] == Vector3.ZERO:
			_chain_points[joint] = desired[joint]
		# Interior joints retain a controlled overshoot; the root and contact tip are
		# pinned immediately after this spring pass.
		var lag := lerpf(1.0, 0.72, float(joint) / float(count - 1))
		var acceleration := (desired[joint] - _chain_points[joint]) * chain_spring * lag
		_chain_velocities[joint] = (_chain_velocities[joint] + acceleration * delta) * exp(-chain_damping * lag * delta)
		_chain_velocities[joint] = _chain_velocities[joint].limit_length(max_chain_speed)
		_chain_points[joint] += _chain_velocities[joint] * delta
	_chain_points[0] = root
	_chain_points[count - 1] = target.limit_length(max_leg_length * hard_reach_ratio)
	return _chain_points.duplicate()


func _draw_continuous_tentacle(tool: SurfaceTool, chain: Array[Vector3], tension_scale: float) -> void:
	var previous_points: Array[Vector3] = []
	var previous_normals: Array[Vector3] = []
	var root := chain[0]
	var control_a := chain[2].lerp(chain[3], 0.35)
	var control_b := chain[-4].lerp(chain[-3], 0.65)
	var tip := chain[-1]
	# Load straightens the silhouette from both ends. The remaining bend sits near
	# the middle like a contracting muscle instead of an idle hose.
	control_a = control_a.lerp(root.lerp(tip, 0.32), pull_load * 0.86)
	control_b = control_b.lerp(root.lerp(tip, 0.74), pull_load * 0.86)
	for section in curve_sections + 1:
		var t := float(section) / float(curve_sections)
		var center := _cubic_bezier(root, control_a, control_b, tip, t)
		var behind := _cubic_bezier(root, control_a, control_b, tip, maxf(t - 0.015, 0.0))
		var ahead := _cubic_bezier(root, control_a, control_b, tip, minf(t + 0.015, 1.0))
		var tangent := (ahead - behind).normalized()
		if tangent.length_squared() < 0.01:
			tangent = (chain[-1] - chain[0]).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length_squared() < 0.01:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var binormal := tangent.cross(side).normalized()

		var radius := lower_radius + upper_radius * tension_scale * pow(maxf(1.0 - t, 0.0), 0.58)
		var contraction_wave := sin(_motion_time * 9.0 - t * 10.0 + _phase_offset)
		var contraction := contraction_wave * lerpf(0.035, 0.11, pull_load) * (1.0 - t)
		radius *= 1.0 + contraction

		var current_points: Array[Vector3] = []
		var current_normals: Array[Vector3] = []
		for ring in tube_sides:
			var angle := TAU * float(ring) / float(tube_sides)
			var radial_offset := side * cos(angle) * ribbon_flatness + binormal * sin(angle)
			var radial_normal := (side * cos(angle) / ribbon_flatness + binormal * sin(angle)).normalized()
			current_points.append(center + radial_offset * radius)
			current_normals.append(radial_normal)
		if section > 0:
			for ring in tube_sides:
				var next := (ring + 1) % tube_sides
				_add_triangle(tool, previous_points[ring], current_points[ring], current_points[next], previous_normals[ring], current_normals[ring], current_normals[next])
				_add_triangle(tool, previous_points[ring], current_points[next], previous_points[next], previous_normals[ring], current_normals[next], previous_normals[next])
		previous_points = current_points
		previous_normals = current_normals


func _sample_chain(chain: Array[Vector3], t: float) -> Vector3:
	var scaled := clampf(t, 0.0, 1.0) * float(chain.size() - 1)
	var index := mini(int(floor(scaled)), chain.size() - 2)
	var local_t := scaled - float(index)
	# Catmull-Rom removes the angular FABRIK silhouette without erasing its lag.
	var a := chain[maxi(index - 1, 0)]
	var b := chain[index]
	var c := chain[index + 1]
	var d := chain[mini(index + 2, chain.size() - 1)]
	return 0.5 * ((2.0 * b) + (-a + c) * local_t + (2.0 * a - 5.0 * b + 4.0 * c - d) * local_t * local_t + (-a + 3.0 * b - 3.0 * c + d) * local_t * local_t * local_t)


func _cubic_bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var inverse := 1.0 - t
	return inverse * inverse * inverse * a + 3.0 * inverse * inverse * t * b + 3.0 * inverse * t * t * c + t * t * t * d


func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	tool.set_normal(na); tool.add_vertex(a)
	tool.set_normal(nb); tool.add_vertex(b)
	tool.set_normal(nc); tool.add_vertex(c)


func _on_player_position_updated(position_value: Vector3) -> void:
	_player_position = position_value


func _on_attack_phase_changed(_attack_name: StringName, phase_name: StringName, _duration: float) -> void:
	match phase_name:
		&"TELEGRAPH": _grasp_target = 0.55
		&"ACTIVE": _grasp_target = 1.0
		&"RECOVERY": _grasp_target = 0.28
		_: _grasp_target = 0.0
