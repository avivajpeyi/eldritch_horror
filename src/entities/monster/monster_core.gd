extends CharacterBody3D

enum LocomotionMode { ANCHORED, AIRBORNE, COLLAPSED, RECOVERING }

const SLIME_CORE_SHADER: Shader = preload("res://src/shaders/slime_core.gdshader")
const MONSTER_FLESH_GROUP := &"monster_flesh"
const MONSTER_LIMB_FLESH_GROUP := &"monster_limb_flesh"
const ROAM_STATE = preload("res://src/entities/monster/states/state_roam.gd")
const ARTILLERY_STATE = preload("res://src/entities/monster/states/state_artillery.gd")
const NEST_STATE = preload("res://src/entities/monster/states/state_nest.gd")

@export_category("Anchored Locomotion")
@export var speed := 5.8
@export var stopping_distance := 6.0
@export var hover_height := 3.8
@export var core_surface_probe_margin := 8.0
@export var orientation_response := 9.0
@export var travel_facing_response := 3.6
@export var attachment_response := 7.5
@export var locomotion_response := 12.0
@export var surface_height_response := 8.5
@export var travel_velocity_response := 8.0
@export var max_attachment_speed := 10.0
@export var step_settle_sag := 0.08
@export var step_settle_response := 4.8
@export var reaching_lean_radians := 0.1
@export_range(1, 3) var max_simultaneous_steps := 2
@export var gait_transfer_pause := 0.12
@export var surface_transition_lock := 0.28
@export var wall_climb_bias := 9.5
@export var ceiling_contraction_speed := 4.6
@export_category("Surface Exploration")
@export var surface_route_scan_distance := 45.0
@export var surface_route_duration_min := 3.8
@export var surface_route_duration_max := 5.8
@export var surface_route_cooldown_min := 7.0
@export var surface_route_cooldown_max := 11.0
@export_category("Anchored Surge")
@export var jump_speed := 10.0
@export var anchored_attack_max_speed := 11.0
@export_category("Collapse")
@export var airborne_gravity := 14.0
@export var collapse_gravity := 20.0
@export var recovery_delay := 1.4
@export_category("Organic Motion")
@export var squash_stretch_strength := 0.25
@export var squash_stretch_response := 8.0
@export var anatomy_seed := 0x0E1D817C
@export var limb_root_radius := 2.1
@export_range(0.0, 0.35) var limb_length_variance := 0.08
@export_range(0.0, 0.45) var limb_thickness_variance := 0.32
@export_category("Flesh Shader")
@export var flesh_base_color := Color(0.009, 0.011, 0.016, 1.0)
@export var flesh_vein_color := Color(0.009, 0.011, 0.016, 1.0)
@export var flesh_edge_glow_color := Color(0.19, 0.012, 0.025, 1.0)
@export_range(0.0, 8.0) var flesh_pulse_speed := 2.15
@export_range(0.0, 0.5) var flesh_distortion_strength := 0.065
@export_range(0.0, 5.0) var flesh_edge_emission_strength := 0.24
@export_category("Boss Health")
@export var max_health := 1000.0
@export_range(0.35, 0.9) var artillery_phase_ratio := 0.67
@export_range(0.1, 0.6) var nest_phase_ratio := 0.34
@export_category("Structural Weakpoints")
@export_range(0.0, 1.0) var armored_body_damage_ratio := 0.08
@export var anchor_max_health := 80.0
@export_range(1, 3) var anchors_required_for_collapse := 2
@export var exposure_duration := 5.0
@export_range(0.05, 1.0) var max_health_per_exposure_ratio := 0.3
@export_range(1.0, 4.0) var mouth_damage_multiplier := 1.6

var current_state: GameManager.MonsterState = GameManager.MonsterState.ROAM
var _combat_state: GameManager.MonsterState = GameManager.MonsterState.ROAM
var _state_profile: RefCounted = ROAM_STATE.new()
var locomotion_mode := LocomotionMode.ANCHORED
var player_position := Vector3.ZERO
var surface_up := Vector3.UP
var health := 0.0

var _recovery_timer := 0.0
var _recovery_probe_timer := 0.0
var _defeated := false
var _visual_time := 0.0
var _visual_base_position := Vector3.ZERO
var _visual_base_scale := Vector3.ONE
var _visual_base_rotation := Vector3.ZERO
var _attack_motion_override := false
var _attack_velocity := Vector3.ZERO
var _attack_compression := 0.0
var _scramble_phase := 0.0
var _surface_lock_timer := 0.0
var _surface_route_cooldown := 3.0
var _surface_route_remaining := 0.0
var _surface_route_direction := Vector3.ZERO
var _wall_vertical_intent := 1.0
var _anchored_surge_timer := 0.0
var _anchored_surge_direction := Vector3.ZERO
var _pre_move_velocity := Vector3.ZERO
var _step_settle_amount := 0.0
var _pull_authority := 0.0
var _smoothed_surface_coordinate := 0.0
var _smoothed_travel_velocity := Vector3.ZERO
var _surface_coordinate_ready := false
var _visual_lunge_offset := Vector3.ZERO
var _reaching_lean_local := Vector3.ZERO
var _slime_core_material: ShaderMaterial
var _debug_view := false
var _anchor_health: Dictionary = {}
var _anchor_elements: Dictionary = {
	&"ANCHOR_RED": GameManager.ElementType.KINETIC,
	&"ANCHOR_BLUE": GameManager.ElementType.KINETIC,
	&"ANCHOR_GREEN": GameManager.ElementType.KINETIC,
}
var _broken_anchors: Dictionary = {}
var _core_exposed := false
var _exposure_timer := 0.0
var _exposure_damage_taken := 0.0
var _mouth_open := false
var _mouth_element: int = GameManager.ElementType.BLUE
var _facing_direction := Vector3.FORWARD
var _active_gait_group := -1
var _gait_group_cursor := 0
var _gait_pause_timer := 0.0

const GAIT_GROUPS: Array[Array] = [
	[0, 5],
	[1, 4],
	[2, 7],
	[3, 6],
	[8],
	[9],
]

@onready var debug_label: Label3D = $DebugLabel
@onready var visual_root: Node3D = $VisualRoot
@onready var legs: Array[Node] = $Legs.get_children()
@onready var attack_controller: Node = $AttackController


func _ready() -> void:
	_visual_base_position = visual_root.position
	_visual_base_scale = visual_root.scale
	_visual_base_rotation = visual_root.rotation
	_configure_limb_asymmetry()
	health = max_health
	add_to_group("Enemies")
	distribute_slime_material()
	SignalBus.player_position_updated.connect(_on_player_position_updated)
	SignalBus.monster_anchor_hit.connect(_on_anchor_hit)
	SignalBus.monster_eye_hit.connect(_on_eye_hit)
	SignalBus.monster_mouth_hit.connect(_on_mouth_hit)
	SignalBus.monster_mouth_exposure_changed.connect(_on_mouth_exposure_changed)
	for leg in legs:
		leg.step_started.connect(_on_leg_step_started)
		leg.step_finished.connect(_on_leg_step_finished)
	_update_gait_permissions()
	SignalBus.monster_state_changed.emit(current_state)
	call_deferred("_emit_initial_health")
	attack_controller.motion_override_changed.connect(_on_attack_motion_override_changed)
	attack_controller.velocity_requested.connect(_on_attack_velocity_requested)
	attack_controller.visual_compression_requested.connect(_on_attack_compression_requested)
	_reset_anchors()
	var initial_forward := (-global_basis.z).slide(surface_up).normalized()
	if initial_forward.length_squared() > 0.01:
		_facing_direction = initial_forward
	# Arena collision is assembled by the parent scene in its ready callback.
	call_deferred("_establish_initial_anchors")


func _emit_initial_health() -> void:
	SignalBus.monster_health_changed.emit(health, max_health)


## Applies one deterministic anatomy pass. Clustered angular slots deliberately
## leave two large silhouette gaps; per-limb reach and girth remain reproducible.
func _configure_limb_asymmetry() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = anatomy_seed
	var clustered_angles := PackedFloat32Array([
		-2.82, -2.48, -1.12, -0.83, -0.58,
		0.18, 0.43, 1.42, 1.68, 2.72,
	])
	var reach_profile := PackedFloat32Array([0.68, 1.24, 0.86, 1.42, 0.76, 1.12, 0.62, 1.34, 0.91, 1.06])
	var girth_profile := PackedFloat32Array([0.78, 1.08, 0.66, 0.9, 1.14, 0.72, 0.82, 1.02, 0.62, 0.88])
	for index in legs.size():
		var leg := legs[index]
		var radius := rng.randf_range(0.68, 1.0) * limb_root_radius
		var angle := clustered_angles[index % clustered_angles.size()]
		angle += rng.randf_range(-0.11, 0.11)
		leg.position.x = sin(angle) * radius
		leg.position.z = cos(angle) * radius
		leg.position.y = rng.randf_range(-0.24, 0.24)
		var length_scale := reach_profile[index % reach_profile.size()] * (1.0 + rng.randf_range(-limb_length_variance, limb_length_variance))
		var thickness_scale := girth_profile[index % girth_profile.size()] * (1.0 + rng.randf_range(-limb_thickness_variance * 0.35, limb_thickness_variance * 0.35))
		leg.configure_anatomy(anatomy_seed + index * 7919, length_scale, thickness_scale)


## Creates one material per monster, then shares it across every explicitly tagged
## flesh surface. Eye and cornea materials remain independent and readable.
func distribute_slime_material() -> void:
	_slime_core_material = ShaderMaterial.new()
	_slime_core_material.shader = SLIME_CORE_SHADER
	_slime_core_material.set_shader_parameter("base_color", flesh_base_color)
	_slime_core_material.set_shader_parameter("vein_color", flesh_vein_color)
	_slime_core_material.set_shader_parameter("edge_glow_color", flesh_edge_glow_color)
	_slime_core_material.set_shader_parameter("pulse_speed", flesh_pulse_speed)
	_slime_core_material.set_shader_parameter("distortion_strength", flesh_distortion_strength)
	_slime_core_material.set_shader_parameter("edge_emission_strength", flesh_edge_emission_strength)
	var pulse_phase := fmod(float(get_instance_id()) * 0.61803398875, TAU)
	_slime_core_material.set_shader_parameter("pulse_phase", pulse_phase)

	for node in get_tree().get_nodes_in_group(MONSTER_FLESH_GROUP):
		if not is_ancestor_of(node) or not (node is GeometryInstance3D):
			continue
		var geometry := node as GeometryInstance3D
		# CSG primitives bake their own material into the combiner output; a regular
		# GeometryInstance material_override does not replace that baked surface.
		if node is CSGShape3D:
			node.set("material", _slime_core_material)
		else:
			geometry.material_override = _slime_core_material
		var displacement_multiplier := 0.38 if node.is_in_group(MONSTER_LIMB_FLESH_GROUP) else 1.0
		geometry.set_instance_shader_parameter("displacement_multiplier", displacement_multiplier)


func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position_updated):
		SignalBus.player_position_updated.disconnect(_on_player_position_updated)
	if SignalBus.monster_anchor_hit.is_connected(_on_anchor_hit):
		SignalBus.monster_anchor_hit.disconnect(_on_anchor_hit)
	if SignalBus.monster_eye_hit.is_connected(_on_eye_hit):
		SignalBus.monster_eye_hit.disconnect(_on_eye_hit)
	if SignalBus.monster_mouth_hit.is_connected(_on_mouth_hit):
		SignalBus.monster_mouth_hit.disconnect(_on_mouth_hit)
	if SignalBus.monster_mouth_exposure_changed.is_connected(_on_mouth_exposure_changed):
		SignalBus.monster_mouth_exposure_changed.disconnect(_on_mouth_exposure_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("monster_jump"):
		jump_at(player_position)
	elif event.is_action_pressed("monster_collapse"):
		collapse()
	elif event.is_action_pressed("monster_debug_view"):
		_debug_view = not _debug_view
		visual_root.visible = not _debug_view
		for leg in legs:
			leg.debug_view = _debug_view


func _physics_process(delta: float) -> void:
	_update_exposure(delta)
	_surface_lock_timer = maxf(_surface_lock_timer - delta, 0.0)
	_update_gait_permissions(delta)
	var can_attack := locomotion_mode == LocomotionMode.ANCHORED and not _defeated
	attack_controller.set_attack_enabled(can_attack)
	if can_attack:
		attack_controller.update_attack(delta, global_position, surface_up.dot(Vector3.UP) < 0.65)

	if _attack_motion_override and locomotion_mode == LocomotionMode.ANCHORED:
		if not _find_core_surface_contact().is_empty() or _planted_leg_count() > 0:
			var attack_intent := _attack_velocity.slide(surface_up)
			var attack_strength := clampf(attack_intent.length() / maxf(anchored_attack_max_speed, 0.01), 0.0, 1.75)
			_apply_core_surface_motion(delta, attack_intent, attack_strength)
		else:
			_begin_recovery()
			_update_recovery(delta)
	else:
		match locomotion_mode:
			LocomotionMode.ANCHORED:
				_update_anchored(delta)
			LocomotionMode.AIRBORNE:
				_update_airborne(delta)
			LocomotionMode.COLLAPSED:
				_update_collapsed(delta)
			LocomotionMode.RECOVERING:
				_update_recovery(delta)

	_pre_move_velocity = velocity
	move_and_slide()
	_handle_surface_contacts()
	_update_visual_deformation(delta)
	_update_debug_label()


func _establish_initial_anchors() -> void:
	for leg in legs:
		leg.set_surface_direction(surface_up)
		leg.force_probe(true)
	_update_gait_permissions()
	if _find_core_surface_contact().is_empty() and _planted_leg_count() == 0:
		locomotion_mode = LocomotionMode.RECOVERING
		_recovery_timer = 0.0


func _update_anchored(delta: float) -> void:
	_update_surface_orientation(delta)
	_update_surface_route(delta)
	var travel := _get_crawl_direction()
	# Attacks are committed poses. Letting locomotion continue underneath every
	# telegraph made the creature's intention unreadable and all ten limbs scramble.
	var attack_phase: StringName = attack_controller.get_phase_name()
	if attack_phase != &"IDLE" and not _attack_motion_override:
		travel = Vector3.ZERO
	_update_anchor_surface_transition(travel)
	var drive_strength := 0.0
	var cadence_multiplier: float = _state_profile.cadence_multiplier()
	_scramble_phase += delta * (ceiling_contraction_speed if surface_up.dot(Vector3.DOWN) > 0.65 else 3.4) * cadence_multiplier
	if travel.length_squared() > 0.01:
		# The hidden core commits to a definite route. Cadence belongs to tentacle
		# animation and never changes whether the creature follows through.
		drive_strength = _state_profile.locomotion_multiplier()
		if absf(surface_up.y) < 0.65:
			drive_strength *= 1.12

	if _anchored_surge_timer > 0.0:
		_anchored_surge_timer -= delta
		travel = _anchored_surge_direction
		drive_strength = clampf(jump_speed / maxf(speed, 0.01), 1.0, 1.75)

	_apply_core_surface_motion(delta, travel, drive_strength)


func _get_crawl_direction() -> Vector3:
	var player_offset := (player_position - global_position).slide(surface_up)
	var is_ceiling := surface_up.dot(Vector3.DOWN) > 0.65
	var is_ground := surface_up.dot(Vector3.UP) > 0.65
	var intent := player_offset

	if (is_ground or is_ceiling) and _surface_route_remaining > 0.0 and _surface_route_direction.length_squared() > 0.01:
		intent = _surface_route_direction.slide(surface_up) * maxf(player_offset.length(), 8.0)
	elif not is_ground and not is_ceiling:
		# Remember which horizontal plane the monster left: floor transfers climb,
		# ceiling transfers descend. This produces complete pendular surface loops.
		intent.y = wall_climb_bias * _wall_vertical_intent
	elif is_ceiling:
		# An offset crawl line prevents a ceiling monster from simply mirroring the
		# player in a perfectly straight, mechanical path.
		intent += global_basis.x * sin(_scramble_phase * 0.37) * 2.4

	if intent.length() <= stopping_distance and is_ground and _surface_route_remaining <= 0.0:
		return Vector3.ZERO
	return intent.normalized() if intent.length_squared() > 0.01 else Vector3.ZERO


## The CharacterBody is the hidden locomotion sphere. It commits to a tangent
## velocity and only uses contacts to maintain surface height. Tentacles receive
## the same intent so their reaches and contractions explain that movement.
func _apply_core_surface_motion(delta: float, travel_intent := Vector3.ZERO, drive_strength := 0.0) -> void:
	for leg in legs:
		leg.set_locomotion_intent(travel_intent, drive_strength)
	var support_center := Vector3.ZERO
	var support_weight := 0.0
	var pull_score_total := 0.0
	var pulling_anchors := 0
	var core_surface_hit := _find_core_surface_contact()
	if not core_surface_hit.is_empty():
		support_center = core_surface_hit.position
		support_weight = 3.0
	for leg in legs:
		if leg.is_planted and leg.surface_normal.dot(surface_up) > 0.25:
			var pull_score: float = leg.get_pull_score(global_position, travel_intent, surface_up)
			var normal_weight: float = clampf(leg.surface_normal.dot(surface_up), 0.25, 1.0)
			support_center += leg.current_foot_global_pos * normal_weight
			support_weight += normal_weight
			pull_score_total += pull_score
			if pull_score > 0.28:
				pulling_anchors += 1
			leg.set_pull_load(pull_score * clampf(drive_strength, 0.45, 1.0))
		else:
			leg.set_pull_load(0.0)
	# During a corner transfer the old plane can temporarily be the only support.
	# It still constrains the body until enough new feet finish their steps.
	if support_weight < 1.5:
		support_center = Vector3.ZERO
		support_weight = 0.0
		for leg in legs:
			if leg.is_planted:
				support_center += leg.current_foot_global_pos
				support_weight += 1.0
	if support_weight <= 0.0:
		_pull_authority = move_toward(_pull_authority, 0.0, delta * 6.0)
		_smoothed_travel_velocity = _smoothed_travel_velocity.lerp(Vector3.ZERO, 1.0 - exp(-travel_velocity_response * delta))
		velocity = Vector3.ZERO
		return
	support_center /= support_weight
	var target_pull_authority := clampf(pull_score_total / 2.4, 0.0, 1.0)
	if pulling_anchors < 2:
		target_pull_authority *= 0.25
	_pull_authority = lerpf(_pull_authority, target_pull_authority, 1.0 - exp(-6.0 * delta))
	var raw_surface_coordinate := support_center.dot(surface_up)
	if not _surface_coordinate_ready:
		_smoothed_surface_coordinate = raw_surface_coordinate
		_surface_coordinate_ready = true
	else:
		_smoothed_surface_coordinate = lerpf(
			_smoothed_surface_coordinate,
			raw_surface_coordinate,
			1.0 - exp(-surface_height_response * delta)
		)
	_step_settle_amount = move_toward(_step_settle_amount, 0.0, step_settle_response * delta)
	var current_surface_height := global_position.dot(surface_up) - _smoothed_surface_coordinate
	var target_surface_height := hover_height - step_settle_sag * _step_settle_amount
	var attachment_velocity := surface_up * (target_surface_height - current_surface_height) * attachment_response
	var travel := travel_intent.slide(surface_up).normalized()
	var target_travel_velocity := travel * speed * drive_strength
	_smoothed_travel_velocity = _smoothed_travel_velocity.lerp(target_travel_velocity, 1.0 - exp(-travel_velocity_response * delta))
	var requested_velocity := (attachment_velocity + _smoothed_travel_velocity).limit_length(max_attachment_speed)
	velocity = velocity.lerp(requested_velocity, 1.0 - exp(-locomotion_response * delta))
	_update_reaching_lean(delta)


## Surface contact for the hidden locomotion sphere. Limb probes can reach across
## corners, but losing or replacing a visual anchor never removes body support.
func _find_core_surface_contact() -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}
	var probe_length := hover_height + core_surface_probe_margin
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position - surface_up.normalized() * probe_length,
		1
	)
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


## Two or more newly planted limbs can pull the body around an edge before its
## collision capsule reaches it. This is what makes floor/wall/ceiling transfers
## originate at the tentacles rather than at an invisible body collision.
func _update_anchor_surface_transition(travel_intent: Vector3) -> void:
	if _surface_lock_timer > 0.0 or travel_intent.length_squared() < 0.01:
		return
	var candidate_normal := Vector3.ZERO
	var candidate_count := 0
	for leg in legs:
		if not leg.is_planted:
			continue
		var normal: Vector3 = leg.surface_normal.normalized()
		var new_plane := normal.dot(surface_up) < 0.62
		var anchor_is_ahead := travel_intent.dot(normal) < -0.18
		if new_plane and anchor_is_ahead:
			candidate_normal += normal
			candidate_count += 1
	if candidate_count >= 2 and candidate_normal.length_squared() > 0.01:
		_transition_to_surface(candidate_normal.normalized())


func _update_reaching_lean(delta: float) -> void:
	var reaching_center := Vector3.ZERO
	var reaching_count := 0
	for leg in legs:
		if leg.is_stepping:
			reaching_center += leg.target_foot_global_pos
			reaching_count += 1
	var target_lean := Vector3.ZERO
	if reaching_count > 0:
		reaching_center /= float(reaching_count)
		var world_direction := (reaching_center - global_position).slide(surface_up).normalized()
		if world_direction.length_squared() > 0.01:
			var local_direction := global_basis.inverse() * world_direction
			target_lean = Vector3(-local_direction.z, 0.0, local_direction.x) * reaching_lean_radians
	_reaching_lean_local = _reaching_lean_local.lerp(target_lean, 1.0 - exp(-6.0 * delta))


func _update_surface_route(delta: float) -> void:
	_surface_route_cooldown -= delta
	_surface_route_remaining = maxf(_surface_route_remaining - delta, 0.0)
	# Walls already have a committed vertical destination. Route scans only decide
	# when a floor/ceiling crawl should break toward the chamber perimeter.
	if absf(surface_up.y) < 0.65:
		return
	if _surface_route_cooldown > 0.0 or _surface_route_remaining > 0.0:
		return
	_surface_route_cooldown = randf_range(surface_route_cooldown_min, surface_route_cooldown_max)
	var direction := _find_nearby_climbable_direction()
	if direction.length_squared() > 0.01:
		_surface_route_direction = direction
		_surface_route_remaining = randf_range(surface_route_duration_min, surface_route_duration_max)


func _find_nearby_climbable_direction() -> Vector3:
	var space := get_world_3d().direct_space_state
	var candidates: Array[Dictionary] = []
	for index in 16:
		var angle := TAU * float(index) / 16.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + direction * surface_route_scan_distance, 1)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var distance_value := global_position.distance_to(hit.position)
		if absf((hit.normal as Vector3).y) < 0.55 and distance_value > 5.0:
			candidates.append({"direction": direction, "distance": distance_value})
	if candidates.is_empty():
		return Vector3.ZERO
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var choice_index := randi_range(0, mini(2, candidates.size() - 1))
	return candidates[choice_index].direction


func _handle_surface_contacts() -> void:
	if locomotion_mode != LocomotionMode.ANCHORED or _surface_lock_timer > 0.0:
		return
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var normal := collision.get_normal().normalized()
		var is_new_plane := normal.dot(surface_up) < 0.48
		var moving_into_plane := _pre_move_velocity.dot(normal) < -0.15
		if is_new_plane and moving_into_plane:
			_transition_to_surface(normal)
			return


func _transition_to_surface(normal: Vector3) -> void:
	if normal.length_squared() < 0.01:
		return
	var previous_surface_up := surface_up
	surface_up = normal.normalized()
	if absf(surface_up.y) < 0.65:
		_wall_vertical_intent = -1.0 if previous_surface_up.dot(Vector3.DOWN) > 0.65 else 1.0
	_surface_coordinate_ready = false
	_surface_lock_timer = surface_transition_lock
	_surface_route_remaining = 0.0
	_surface_route_cooldown = randf_range(surface_route_cooldown_min, surface_route_cooldown_max)
	for leg in legs:
		leg.set_surface_direction(surface_up)
		if not leg.is_planted and not leg.is_stepping:
			leg.force_probe()


func _update_airborne(delta: float) -> void:
	velocity += Vector3.DOWN * airborne_gravity * delta
	if is_on_floor() or get_slide_collision_count() > 0:
		if get_slide_collision_count() > 0:
			surface_up = get_slide_collision(0).get_normal().normalized()
		_begin_recovery()


func _update_collapsed(delta: float) -> void:
	velocity += Vector3.DOWN * collapse_gravity * delta
	visual_root.rotate_x(delta * 1.8)
	visual_root.rotate_z(delta * 1.25)
	_recovery_timer -= delta
	if _recovery_timer <= 0.0 and is_on_floor() and not _defeated:
		_begin_recovery()


func _update_recovery(delta: float) -> void:
	_recovery_timer -= delta
	_recovery_probe_timer -= delta
	if _recovery_probe_timer <= 0.0:
		_recovery_probe_timer = 0.12
		var plant_instantly := _planted_leg_count() == 0
		for leg in legs:
			leg.set_surface_direction(surface_up)
			if not leg.is_planted and not leg.is_stepping:
				leg.force_probe(plant_instantly)
		_update_gait_permissions()

	var planted := _planted_leg_count()
	var core_supported := not _find_core_surface_contact().is_empty()
	if planted > 0 or core_supported:
		_apply_core_surface_motion(delta)
	else:
		# If every probe genuinely misses, falling communicates loss of support. The
		# old zero velocity here was the most literal source of floating.
		velocity += Vector3.DOWN * airborne_gravity * delta

	if core_supported and _recovery_timer <= 0.0:
		locomotion_mode = LocomotionMode.ANCHORED
		_reset_anchors()
		set_state(_combat_state)


## Kept as the debug/API entry point, but it is now an anchored muscular surge.
## The monster accelerates across its current surface without releasing every foot.
func jump_at(target: Vector3) -> void:
	if locomotion_mode != LocomotionMode.ANCHORED:
		return
	var planar := (target - global_position).slide(surface_up).normalized()
	if planar.length_squared() < 0.01:
		return
	_anchored_surge_direction = planar
	_anchored_surge_timer = 0.62


func collapse(expose_core := false) -> void:
	if locomotion_mode == LocomotionMode.COLLAPSED:
		return
	locomotion_mode = LocomotionMode.COLLAPSED
	_pull_authority = 0.0
	_smoothed_travel_velocity = Vector3.ZERO
	_surface_coordinate_ready = false
	set_state(GameManager.MonsterState.COLLAPSED)
	_recovery_timer = exposure_duration if expose_core else recovery_delay
	if expose_core:
		_core_exposed = true
		_exposure_timer = exposure_duration
		_exposure_damage_taken = 0.0
		SignalBus.monster_exposure_changed.emit(true, exposure_duration, _exposure_damage_remaining())
		SignalBus.monster_combat_message.emit("CORE EXPOSED — SHOOT THE CENTRAL EYE", true)
	for leg in legs:
		leg.release()
	SignalBus.monster_collapsed.emit()


func hitscan_hit(damage: float, _direction: Vector3, _hit_position: Vector3) -> void:
	take_damage(damage)


func hitscan_hit_typed(damage: float, damage_type: int, _direction: Vector3, _hit_position: Vector3) -> void:
	take_damage(damage, damage_type)


func projectile_hit(damage: float, _direction: Vector3) -> void:
	take_damage(damage)


func projectile_hit_typed(damage: float, damage_type: int, _direction: Vector3) -> void:
	take_damage(damage, damage_type)


func take_damage(amount: float, _damage_type := GameManager.ElementType.KINETIC) -> void:
	if _defeated or amount <= 0.0:
		return
	var applied_damage := amount * armored_body_damage_ratio
	health = clampf(health - applied_damage, 0.0, max_health)
	SignalBus.monster_health_changed.emit(health, max_health)
	_update_encounter_phase()
	if health <= 0.0:
		_defeated = true
		SignalBus.monster_defeated.emit()
		collapse()


func _update_encounter_phase() -> void:
	if max_health <= 0.0 or health <= 0.0:
		return
	var health_ratio := health / max_health
	var next_state := GameManager.MonsterState.ROAM
	if health_ratio <= nest_phase_ratio:
		next_state = GameManager.MonsterState.NEST
	elif health_ratio <= artillery_phase_ratio:
		next_state = GameManager.MonsterState.ARTILLERY
	if current_state == GameManager.MonsterState.COLLAPSED:
		_combat_state = next_state
		_state_profile = _profile_for_state(next_state)
	else:
		set_state(next_state)


func _on_anchor_hit(anchor_id: StringName, damage: float, _damage_type: int) -> void:
	if _defeated or _core_exposed or not _anchor_health.has(anchor_id) or _broken_anchors.has(anchor_id):
		return
	var required_type: int = _anchor_elements[anchor_id]
	var next_health := maxf(float(_anchor_health[anchor_id]) - damage, 0.0)
	_anchor_health[anchor_id] = next_health
	var broken := next_health <= 0.0
	if broken:
		_broken_anchors[anchor_id] = true
		SignalBus.monster_combat_message.emit("WEAKPOINT SEVERED — %d/%d" % [_broken_anchors.size(), anchors_required_for_collapse], true)
	else:
		SignalBus.monster_combat_message.emit("WEAKPOINT DAMAGED", true)
	SignalBus.monster_anchor_state_changed.emit(anchor_id, required_type, next_health, anchor_max_health, broken)
	if _broken_anchors.size() >= anchors_required_for_collapse:
		collapse(true)


func _on_eye_hit(damage: float, _damage_type: int) -> void:
	if _defeated or damage <= 0.0:
		return
	if not _core_exposed:
		take_damage(damage)
		return
	var applied_damage := minf(damage, _exposure_damage_remaining())
	if applied_damage <= 0.0:
		SignalBus.monster_combat_message.emit("THE WARD HAS SEALED — SURVIVE", false)
		return
	_exposure_damage_taken += applied_damage
	health = clampf(health - applied_damage, 0.0, max_health)
	SignalBus.monster_health_changed.emit(health, max_health)
	SignalBus.monster_exposure_changed.emit(true, _exposure_timer, _exposure_damage_remaining())
	_update_encounter_phase()
	if health <= 0.0:
		_defeated = true
		SignalBus.monster_defeated.emit()
		collapse()


func _on_mouth_hit(damage: float, damage_type: int) -> void:
	if _defeated or damage <= 0.0 or not _mouth_open:
		return
	# Elemental ammo is currently out of the combat loop. The open mouth remains a
	# high-value timing weakpoint, but the player's ordinary kinetic rounds work.
	var applied_damage := damage * mouth_damage_multiplier
	health = clampf(health - applied_damage, 0.0, max_health)
	SignalBus.monster_health_changed.emit(health, max_health)
	SignalBus.monster_combat_message.emit("THROAT WEAKPOINT STRUCK", true)
	_update_encounter_phase()
	if health <= 0.0:
		_defeated = true
		SignalBus.monster_defeated.emit()
		collapse()


func _on_mouth_exposure_changed(open: bool, element_type: int) -> void:
	_mouth_open = open
	_mouth_element = element_type
	if open:
		SignalBus.monster_combat_message.emit("HOLLOW THROAT EXPOSED — USE %s" % GameManager.ElementType.keys()[element_type], true)


func _update_exposure(delta: float) -> void:
	if not _core_exposed:
		return
	_exposure_timer = maxf(_exposure_timer - delta, 0.0)
	if _exposure_timer > 0.0:
		return
	_core_exposed = false
	SignalBus.monster_exposure_changed.emit(false, 0.0, 0.0)
	SignalBus.monster_combat_message.emit("CORE SEALED — BREAK THE GLOWING WEAKPOINTS", false)


func _exposure_damage_remaining() -> float:
	return maxf(max_health * max_health_per_exposure_ratio - _exposure_damage_taken, 0.0)


func _reset_anchors() -> void:
	_broken_anchors.clear()
	for anchor_id: StringName in _anchor_elements:
		_anchor_health[anchor_id] = anchor_max_health
		var element_type: int = _anchor_elements[anchor_id]
		SignalBus.monster_anchor_state_changed.emit(anchor_id, element_type, anchor_max_health, anchor_max_health, false)


func _begin_recovery() -> void:
	if locomotion_mode == LocomotionMode.RECOVERING:
		return
	locomotion_mode = LocomotionMode.RECOVERING
	_recovery_timer = 0.35
	_recovery_probe_timer = 0.0
	_surface_coordinate_ready = false
	_smoothed_travel_velocity = Vector3.ZERO
	for leg in legs:
		leg.set_surface_direction(surface_up)


func _update_surface_orientation(delta: float) -> void:
	if _surface_lock_timer <= 0.0:
		var normal_sum := Vector3.ZERO
		var compatible_anchors := 0
		for leg in legs:
			if leg.is_planted and leg.surface_normal.dot(surface_up) > 0.35:
				normal_sum += leg.surface_normal
				compatible_anchors += 1
		if compatible_anchors >= 2 and normal_sum.length_squared() > 0.01:
			var resolved_normal := normal_sum.normalized()
			surface_up = surface_up.slerp(resolved_normal, 1.0 - exp(-orientation_response * delta)).normalized()
			for leg in legs:
				leg.set_surface_direction(surface_up)

	# The body follows its own momentum and contact plane. Looking directly at the
	# player every frame made the entire anatomy behave like a camera-facing sprite.
	var travel_forward := _smoothed_travel_velocity.slide(surface_up)
	if _attack_motion_override and _attack_velocity.length_squared() > 0.25:
		travel_forward = _attack_velocity.slide(surface_up)
	if travel_forward.length_squared() > 0.5:
		var desired_forward := travel_forward.normalized()
		if _facing_direction.dot(desired_forward) < -0.82:
			desired_forward = (_facing_direction + desired_forward * 0.35).slide(surface_up).normalized()
		_facing_direction = _facing_direction.slerp(
			desired_forward,
			1.0 - exp(-travel_facing_response * delta)
		).normalized()
	else:
		_facing_direction = _facing_direction.slide(surface_up).normalized()
	if _facing_direction.length_squared() < 0.01:
		_facing_direction = (-global_basis.z).slide(surface_up).normalized()
	if _facing_direction.length_squared() < 0.01:
		_facing_direction = Vector3.FORWARD
	var target_basis := Basis.looking_at(_facing_direction, surface_up)
	global_basis = global_basis.slerp(
		target_basis,
		1.0 - exp(-orientation_response * 0.55 * delta)
	).orthonormalized()


func _on_leg_step_started(_leg: Node) -> void:
	pass


func _on_leg_step_finished(_leg: Node) -> void:
	_step_settle_amount = 1.0


func _update_gait_permissions(delta := 0.0) -> void:
	_gait_pause_timer = maxf(_gait_pause_timer - delta, 0.0)
	if _active_gait_group >= 0:
		var active_indices: Array = GAIT_GROUPS[_active_gait_group]
		var group_busy := false
		for index in active_indices:
			if index < legs.size() and (legs[index].is_stepping or legs[index].needs_step()):
				group_busy = true
				break
		if not group_busy:
			_gait_group_cursor = (_active_gait_group + 1) % GAIT_GROUPS.size()
			_active_gait_group = -1
			_gait_pause_timer = gait_transfer_pause

	if _active_gait_group < 0 and _gait_pause_timer <= 0.0:
		for offset in GAIT_GROUPS.size():
			var candidate_group := (_gait_group_cursor + offset) % GAIT_GROUPS.size()
			var candidate_indices: Array = GAIT_GROUPS[candidate_group]
			var needs_transfer := false
			for index in candidate_indices:
				if index < legs.size() and legs[index].needs_step():
					needs_transfer = true
					break
			if needs_transfer:
				_active_gait_group = candidate_group
				break

	var allowed_indices: Array = [] if _active_gait_group < 0 else GAIT_GROUPS[_active_gait_group]
	var allowed_count := 0
	for index in legs.size():
		var allowed := allowed_indices.has(index) and allowed_count < max_simultaneous_steps
		legs[index].can_step = allowed or legs[index].is_stepping
		if allowed and (legs[index].needs_step() or legs[index].is_stepping):
			allowed_count += 1


func _planted_leg_count() -> int:
	var count := 0
	for leg in legs:
		if leg.is_planted:
			count += 1
	return count


func _stepping_leg_count() -> int:
	var count := 0
	for leg in legs:
		if leg.is_stepping:
			count += 1
	return count


func _update_visual_deformation(delta: float) -> void:
	_visual_time += delta
	var ratio := clampf(velocity.length() / maxf(jump_speed, 0.01), 0.0, 1.0)
	var pull_pulse := maxf(sin(_scramble_phase), 0.0) * _pull_authority
	var stretch := ratio * squash_stretch_strength + pull_pulse * 0.08
	var breath := sin(_visual_time * 1.08) * 0.055
	var secondary_breath := sin(_visual_time * 0.63 + 1.7) * 0.018
	var target := _visual_base_scale * Vector3(
		1.0 - stretch * 0.4 + breath * 0.72,
		1.0 + stretch - breath * 0.38 + secondary_breath,
		1.0 - stretch * 0.4 + breath + secondary_breath * 0.35
	)
	if _attack_compression > 0.0:
		target *= Vector3(1.0 + _attack_compression * 0.4, 1.0 - _attack_compression * 0.45, 1.0 + _attack_compression * 0.25)
	visual_root.scale = visual_root.scale.lerp(target, 1.0 - exp(-squash_stretch_response * delta))
	var local_velocity := global_basis.inverse() * velocity
	var target_lunge := local_velocity.limit_length(max_attachment_speed) / maxf(max_attachment_speed, 0.01) * (_pull_authority * 0.16)
	_visual_lunge_offset = _visual_lunge_offset.lerp(target_lunge, 1.0 - exp(-5.0 * delta))
	visual_root.position = _visual_base_position + Vector3(0.0, sin(_visual_time * 0.83) * 0.055, 0.0) + _visual_lunge_offset
	var idle_rotation := _visual_base_rotation + Vector3(
		sin(_visual_time * 0.47) * 0.035,
		sin(_visual_time * 0.31 + 0.8) * 0.045,
		cos(_visual_time * 0.41 + 1.9) * 0.028
	)
	visual_root.rotation = visual_root.rotation.lerp(idle_rotation + _reaching_lean_local, 1.0 - exp(-3.2 * delta))


func _on_player_position_updated(position_value: Vector3) -> void:
	player_position = position_value


func _on_attack_motion_override_changed(enabled: bool) -> void:
	_attack_motion_override = enabled
	_update_gait_permissions()
	if not enabled:
		_attack_velocity = Vector3.ZERO


func _on_attack_velocity_requested(requested_velocity: Vector3) -> void:
	_attack_velocity = requested_velocity


func _on_attack_compression_requested(amount: float) -> void:
	_attack_compression = amount


func set_state(next_state: GameManager.MonsterState) -> void:
	if current_state == next_state:
		return
	if next_state != GameManager.MonsterState.COLLAPSED:
		_combat_state = next_state
		_state_profile = _profile_for_state(next_state)
	current_state = next_state
	SignalBus.monster_state_changed.emit(current_state)


func _profile_for_state(state: GameManager.MonsterState) -> RefCounted:
	match state:
		GameManager.MonsterState.ARTILLERY: return ARTILLERY_STATE.new()
		GameManager.MonsterState.NEST: return NEST_STATE.new()
	return ROAM_STATE.new()


func _update_debug_label() -> void:
	debug_label.text = "%s | %d PLANTED | %d REACHING | PULL %.0f%%\nSURFACE %s\n[J] SURGE  [K] COLLAPSE  [L] DEBUG VIEW" % [
		LocomotionMode.keys()[locomotion_mode],
		_planted_leg_count(),
		_stepping_leg_count(),
		_pull_authority * 100.0,
		str(surface_up).pad_decimals(2),
	]
