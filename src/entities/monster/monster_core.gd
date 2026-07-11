extends CharacterBody3D

enum LocomotionMode { ANCHORED, AIRBORNE, COLLAPSED, RECOVERING }

const SLIME_CORE_SHADER: Shader = preload("res://src/shaders/slime_core.gdshader")
const MONSTER_FLESH_GROUP := &"monster_flesh"
const MONSTER_LIMB_FLESH_GROUP := &"monster_limb_flesh"

@export_category("Anchored Locomotion")
@export var speed := 2.8
@export var steering_acceleration := 5.0
@export var stopping_distance := 4.0
@export var hover_height := 2.2
@export var orientation_response := 4.5
@export_category("Jump")
@export var jump_speed := 10.0
@export var jump_arc := 7.0
@export var jump_cooldown := 6.5
@export var airborne_gravity := 14.0
@export_category("Collapse")
@export var collapse_gravity := 20.0
@export var recovery_delay := 1.4
@export_category("Organic Motion")
@export var squash_stretch_strength := 0.25
@export var squash_stretch_response := 8.0
@export_category("Flesh Shader")
@export var flesh_base_color := Color(0.12, 0.012, 0.025, 1.0)
@export var flesh_vein_color := Color(0.34, 0.006, 0.012, 1.0)
@export var flesh_edge_glow_color := Color(0.62, 0.006, 0.025, 1.0)
@export_range(0.0, 8.0) var flesh_pulse_speed := 2.15
@export_range(0.0, 0.5) var flesh_distortion_strength := 0.22
@export_range(0.0, 5.0) var flesh_edge_emission_strength := 1.2
@export_category("Boss Health")
@export var max_health := 1000.0

var current_state: GameManager.MonsterState = GameManager.MonsterState.ROAM
var locomotion_mode := LocomotionMode.ANCHORED
var player_position := Vector3.ZERO
var surface_up := Vector3.UP
var _jump_timer := 3.0
var _recovery_timer := 0.0
var _step_group := 0
var health := 0.0
var _defeated := false
var _visual_time := 0.0
var _visual_base_position := Vector3.ZERO
var _traversal_timer := 4.5
var _attack_motion_override := false
var _attack_velocity := Vector3.ZERO
var _attack_compression := 0.0
var _scramble_phase := 0.0
var _swing_phase := 0.0
var _slime_core_material: ShaderMaterial

@onready var debug_label: Label3D = $DebugLabel
@onready var visual_root: Node3D = $VisualRoot
@onready var legs: Array[Node] = $Legs.get_children()
@onready var attack_controller: Node = $AttackController

func _ready() -> void:
	_visual_base_position = visual_root.position
	health = max_health
	add_to_group("Enemies")
	distribute_slime_material()
	SignalBus.player_position_updated.connect(_on_player_position_updated)
	for leg in legs:
		leg.step_finished.connect(_on_leg_step_finished)
	_update_gait_permissions()
	SignalBus.monster_state_changed.emit(current_state)
	SignalBus.monster_health_changed.emit(health, max_health)
	attack_controller.motion_override_changed.connect(_on_attack_motion_override_changed)
	attack_controller.velocity_requested.connect(_on_attack_velocity_requested)
	attack_controller.visual_compression_requested.connect(_on_attack_compression_requested)

## Creates one material per monster, then shares it across every explicitly tagged
## flesh surface. Core CSG lobes are included alongside MeshInstance3D tubes, while
## untagged eye and cornea meshes retain their own readable materials.
func distribute_slime_material() -> void:
	_slime_core_material = ShaderMaterial.new()
	_slime_core_material.shader = SLIME_CORE_SHADER
	_slime_core_material.set_shader_parameter("base_color", flesh_base_color)
	_slime_core_material.set_shader_parameter("vein_color", flesh_vein_color)
	_slime_core_material.set_shader_parameter("edge_glow_color", flesh_edge_glow_color)
	_slime_core_material.set_shader_parameter("pulse_speed", flesh_pulse_speed)
	_slime_core_material.set_shader_parameter("distortion_strength", flesh_distortion_strength)
	_slime_core_material.set_shader_parameter("edge_emission_strength", flesh_edge_emission_strength)
	# A phase unique to this monster keeps multiple monsters from pulsing in lockstep;
	# all meshes belonging to this monster still share precisely the same phase.
	var pulse_phase := fmod(float(get_instance_id()) * 0.61803398875, TAU)
	_slime_core_material.set_shader_parameter("pulse_phase", pulse_phase)

	for node in get_tree().get_nodes_in_group(MONSTER_FLESH_GROUP):
		if not is_ancestor_of(node) or not (node is GeometryInstance3D):
			continue
		var geometry := node as GeometryInstance3D
		geometry.material_override = _slime_core_material
		var displacement_multiplier := 0.38 if node.is_in_group(MONSTER_LIMB_FLESH_GROUP) else 1.0
		geometry.set_instance_shader_parameter("displacement_multiplier", displacement_multiplier)

func _exit_tree() -> void:
	if SignalBus.player_position_updated.is_connected(_on_player_position_updated):
		SignalBus.player_position_updated.disconnect(_on_player_position_updated)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("monster_jump"):
		jump_at(player_position)
	elif event.is_action_pressed("monster_collapse"):
		collapse()

func _physics_process(delta: float) -> void:
	attack_controller.update_attack(delta, global_position, surface_up.dot(Vector3.DOWN) > 0.65)
	if _attack_motion_override:
		velocity = _attack_velocity
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
	move_and_slide()
	_update_visual_deformation(delta)
	_update_debug_label()

func _update_anchored(delta: float) -> void:
	_update_surface_orientation(delta)
	# Hunt along the current surface plane; never pull away from a wall or ceiling
	# merely because the player is standing on a different plane.
	var offset := (player_position - global_position).slide(surface_up)
	if surface_up.dot(Vector3.DOWN) > 0.65:
		# A constrained pendulum cadence: forward momentum peaks below the virtual
		# anchor and lifts the core at each end of the arc.
		_swing_phase += delta * 1.7
		var travel := offset.normalized()
		var swing_speed := speed * (1.15 + absf(cos(_swing_phase)) * 1.5)
		var lift := sin(_swing_phase * 2.0) * 1.8
		velocity = velocity.move_toward(travel * swing_speed + Vector3.UP * lift, steering_acceleration * delta)
	elif surface_up.dot(Vector3.UP) > 0.65 and offset.length() > stopping_distance:
		# Ground scramble moves in violent contractions instead of a smooth glide.
		_scramble_phase += delta * 3.4
		var contraction := clampf(sin(_scramble_phase) * 1.8, 0.18, 1.0)
		velocity = velocity.move_toward(offset.normalized() * speed * (0.65 + contraction * 2.4), steering_acceleration * 2.0 * delta)
	elif offset.length() > stopping_distance:
		velocity = velocity.move_toward(offset.normalized() * speed, steering_acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, steering_acceleration * delta)
	_traversal_timer -= delta
	if _traversal_timer <= 0.0:
		_traversal_timer = randf_range(7.0, 10.0)
		if _try_ceiling_ambush():
			return
	_jump_timer -= delta
	if _jump_timer <= 0.0 and global_position.distance_to(player_position) < 16.0:
		jump_at(player_position)

func _update_airborne(delta: float) -> void:
	velocity -= surface_up * airborne_gravity * delta
	if is_on_floor() or get_slide_collision_count() > 0:
		if get_slide_collision_count() > 0:
			surface_up = get_slide_collision(0).get_normal().normalized()
		_begin_recovery()

func _update_collapsed(delta: float) -> void:
	velocity += Vector3.DOWN * collapse_gravity * delta
	visual_root.rotate_x(delta * 1.8)
	visual_root.rotate_z(delta * 1.25)
	_recovery_timer -= delta
	if _recovery_timer <= 0.0 and is_on_floor():
		_begin_recovery()

func _update_recovery(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, steering_acceleration * 2.0 * delta)
	_recovery_timer -= delta
	if _recovery_timer <= 0.0 and _planted_leg_count() >= 3:
		locomotion_mode = LocomotionMode.ANCHORED
		set_state(GameManager.MonsterState.ROAM)
		_jump_timer = jump_cooldown

func jump_at(target: Vector3) -> void:
	if locomotion_mode != LocomotionMode.ANCHORED:
		return
	var planar := (target - global_position).slide(surface_up).normalized()
	velocity = planar * jump_speed + surface_up * jump_arc
	locomotion_mode = LocomotionMode.AIRBORNE
	for leg in legs:
		leg.release()
	_jump_timer = jump_cooldown

func _try_ceiling_ambush() -> bool:
	if surface_up.dot(Vector3.UP) < 0.65:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position, global_position + Vector3.UP * 13.0, 1)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var target: Vector3 = hit.position
	velocity = (target - global_position).normalized() * jump_speed * 1.75
	locomotion_mode = LocomotionMode.AIRBORNE
	for leg in legs:
		leg.release()
	return true

func collapse() -> void:
	if locomotion_mode == LocomotionMode.COLLAPSED:
		return
	locomotion_mode = LocomotionMode.COLLAPSED
	set_state(GameManager.MonsterState.COLLAPSED)
	_recovery_timer = recovery_delay
	for leg in legs:
		leg.release()
	SignalBus.monster_collapsed.emit()

func hitscan_hit(damage: float, _direction: Vector3, _hit_position: Vector3) -> void:
	take_damage(damage)

func projectile_hit(damage: float, _direction: Vector3) -> void:
	take_damage(damage)

func take_damage(amount: float, _damage_type := GameManager.ElementType.KINETIC) -> void:
	if _defeated or amount <= 0.0:
		return
	health = clampf(health - amount, 0.0, max_health)
	SignalBus.monster_health_changed.emit(health, max_health)
	if health <= 0.0:
		_defeated = true
		SignalBus.monster_defeated.emit()
		collapse()

func _begin_recovery() -> void:
	locomotion_mode = LocomotionMode.RECOVERING
	_recovery_timer = 0.75
	for leg in legs:
		leg.set_surface_direction(surface_up)
		leg.force_probe()

func _update_surface_orientation(delta: float) -> void:
	var normal_sum := Vector3.ZERO
	var planted := 0
	for leg in legs:
		if leg.is_planted:
			normal_sum += leg.surface_normal
			planted += 1
	if planted >= 2 and normal_sum.length_squared() > 0.01:
		surface_up = normal_sum.normalized()
		for leg in legs:
			leg.set_surface_direction(surface_up)
	var forward := (player_position - global_position).slide(surface_up).normalized()
	if forward.length_squared() < 0.01:
		forward = -global_basis.z.slide(surface_up).normalized()
	var target_basis := Basis.looking_at(forward, surface_up)
	global_basis = global_basis.slerp(target_basis, 1.0 - exp(-orientation_response * delta)).orthonormalized()

func _on_leg_step_finished(_leg: Node) -> void:
	_step_group = (_step_group + 1) % 5
	_update_gait_permissions()

func _update_gait_permissions() -> void:
	for index in legs.size():
		# Five staggered phases keep eight tentacles planted while the other two reach.
		legs[index].can_step = index % 5 == _step_group

func _planted_leg_count() -> int:
	var count := 0
	for leg in legs:
		if leg.is_planted:
			count += 1
	return count

func _update_visual_deformation(delta: float) -> void:
	_visual_time += delta
	var ratio := clampf(velocity.length() / maxf(jump_speed, 0.01), 0.0, 1.0)
	var stretch := ratio * squash_stretch_strength
	var breath := sin(_visual_time * 1.35) * 0.025
	var target := Vector3(1.0 - stretch * 0.4 + breath, 1.0 + stretch - breath * 0.5, 1.0 - stretch * 0.4 + breath)
	if _attack_compression > 0.0:
		target *= Vector3(1.0 + _attack_compression * 0.4, 1.0 - _attack_compression * 0.45, 1.0 + _attack_compression * 0.25)
	visual_root.scale = visual_root.scale.lerp(target, 1.0 - exp(-squash_stretch_response * delta))
	visual_root.position = _visual_base_position + Vector3(0.0, sin(_visual_time * 0.83) * 0.055, 0.0)

func _on_player_position_updated(position: Vector3) -> void:
	player_position = position

func _on_attack_motion_override_changed(enabled: bool) -> void:
	_attack_motion_override = enabled
	if not enabled:
		_attack_velocity = Vector3.ZERO

func _on_attack_velocity_requested(requested_velocity: Vector3) -> void:
	_attack_velocity = requested_velocity

func _on_attack_compression_requested(amount: float) -> void:
	_attack_compression = amount

func set_state(next_state: GameManager.MonsterState) -> void:
	if current_state == next_state:
		return
	current_state = next_state
	SignalBus.monster_state_changed.emit(current_state)

func _update_debug_label() -> void:
	debug_label.text = "%s | %d ANCHORS\n[J] JUMP  [K] COLLAPSE" % [
		LocomotionMode.keys()[locomotion_mode], _planted_leg_count()
	]
