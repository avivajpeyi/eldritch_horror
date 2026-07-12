class_name SwarmEye
extends CharacterBody3D
## A readable flying threat. Eyes flock through SignalBus and request one of a
## limited number of attack slots, so the swarm surrounds without dog-piling.

enum BehaviourState { ORBIT, TELEGRAPH, DIVE, RECOVER }

@export_category("Flight")
@export var cruise_speed := 4.0
@export var dive_speed := 8.5
@export var acceleration := 8.0
@export var neighbour_radius := 8.0
@export var separation_radius := 2.4
@export var wall_probe_distance := 4.5
@export_category("Attack")
@export var telegraph_duration := 0.85
@export var dive_duration := 1.15
@export var recovery_duration := 1.8
@export var contact_damage := 16.0
@export var attack_range := 1.65
@export var request_interval_min := 0.45
@export var request_interval_max := 0.9
@export_category("Durability")
@export var max_health := 1.0

var target_position := Vector3.ZERO
var health := 0.0

var _member_id := 0
var _neighbours: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _state := BehaviourState.ORBIT
var _state_timer := 0.0
var _request_timer := 1.0
var _spawn_grace := 1.0
var _slot_requested := false
var _owns_attack_slot := false
var _locked_target := Vector3.ZERO
var _orbit_phase := 0.0
var _publish_timer := 0.0
var _base_model_scale := Vector3.ONE

@onready var model_root: Node3D = $ModelRoot
@onready var eye_glow: OmniLight3D = $EyeGlow
@onready var death_burst: GPUParticles3D = $DeathBurst


func _ready() -> void:
	_member_id = get_instance_id()
	_rng.seed = _member_id * 7919
	health = max_health
	_orbit_phase = _rng.randf_range(0.0, TAU)
	_request_timer = _rng.randf_range(request_interval_min, request_interval_max)
	_base_model_scale = model_root.scale
	add_to_group("Enemies")
	add_to_group("eye_swarm")
	SignalBus.player_position_updated.connect(_on_player_position)
	SignalBus.eye_swarm_member_updated.connect(_on_member_updated)
	SignalBus.eye_swarm_member_removed.connect(_on_member_removed)
	SignalBus.eye_swarm_attack_slot_granted.connect(_on_attack_slot_granted)
	_publish_state()


func _exit_tree() -> void:
	_release_attack_slot()
	SignalBus.eye_swarm_member_removed.emit(_member_id)
	if SignalBus.player_position_updated.is_connected(_on_player_position):
		SignalBus.player_position_updated.disconnect(_on_player_position)
	if SignalBus.eye_swarm_member_updated.is_connected(_on_member_updated):
		SignalBus.eye_swarm_member_updated.disconnect(_on_member_updated)
	if SignalBus.eye_swarm_member_removed.is_connected(_on_member_removed):
		SignalBus.eye_swarm_member_removed.disconnect(_on_member_removed)
	if SignalBus.eye_swarm_attack_slot_granted.is_connected(_on_attack_slot_granted):
		SignalBus.eye_swarm_attack_slot_granted.disconnect(_on_attack_slot_granted)


func _physics_process(delta: float) -> void:
	_spawn_grace = maxf(_spawn_grace - delta, 0.0)
	_request_timer -= delta
	_state_timer -= delta
	_orbit_phase += delta * (0.62 + fmod(float(_member_id), 7.0) * 0.02)

	_update_state()
	var steering := _swarm_steering()
	steering += _goal_steering() * 1.65
	steering += _wall_avoidance() * 3.4
	var target_speed := dive_speed if _state == BehaviourState.DIVE else cruise_speed
	if _state == BehaviourState.TELEGRAPH:
		target_speed *= 0.42
	var desired_velocity := steering.normalized() * target_speed
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-acceleration * delta))
	move_and_slide()
	_resolve_collisions()
	_face_velocity(delta)
	_update_warning_visual()
	_try_dive_hit()

	_publish_timer -= delta
	if _publish_timer <= 0.0:
		_publish_timer = 0.1
		_publish_state()


func take_damage(amount: float, _damage_type := GameManager.ElementType.KINETIC) -> void:
	if amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		SignalBus.minion_destroyed.emit()
		_spawn_death_burst()
		queue_free()


## Detaches the burst emitter so it can finish playing after this eye is
## freed, then frees itself once the one-shot particles finish.
func _spawn_death_burst() -> void:
	var burst_position := global_position
	death_burst.get_parent().remove_child(death_burst)
	get_tree().current_scene.add_child(death_burst)
	death_burst.global_position = burst_position
	death_burst.emitting = true
	death_burst.finished.connect(death_burst.queue_free)


func hitscan_hit(damage: float, _direction: Vector3, _position: Vector3) -> void:
	take_damage(damage)


func hitscan_hit_typed(damage: float, damage_type: int, _direction: Vector3, _position: Vector3) -> void:
	take_damage(damage, damage_type)


func projectile_hit(damage: float, _direction: Vector3) -> void:
	take_damage(damage)


func projectile_hit_typed(damage: float, damage_type: int, _direction: Vector3) -> void:
	take_damage(damage, damage_type)


func _update_state() -> void:
	match _state:
		BehaviourState.ORBIT:
			if _spawn_grace <= 0.0 and _request_timer <= 0.0 and not _slot_requested:
				_slot_requested = true
				SignalBus.eye_swarm_attack_slot_requested.emit(_member_id)
				_request_timer = _rng.randf_range(request_interval_min, request_interval_max)
		BehaviourState.TELEGRAPH:
			_locked_target = target_position + Vector3.UP * 0.9
			if _state_timer <= 0.0:
				_state = BehaviourState.DIVE
				_state_timer = dive_duration
		BehaviourState.DIVE:
			if _state_timer <= 0.0:
				_begin_recovery()
		BehaviourState.RECOVER:
			if _state_timer <= 0.0:
				_state = BehaviourState.ORBIT
				_request_timer = _rng.randf_range(request_interval_min, request_interval_max)


func _swarm_steering() -> Vector3:
	var center := Vector3.ZERO
	var average_velocity := Vector3.ZERO
	var separation := Vector3.ZERO
	var count := 0
	for neighbour_state: Dictionary in _neighbours.values():
		var neighbour_position: Vector3 = neighbour_state["position"]
		var offset := neighbour_position - global_position
		var distance_value := offset.length()
		if distance_value <= 0.001 or distance_value > neighbour_radius:
			continue
		center += neighbour_position
		average_velocity += neighbour_state["velocity"] as Vector3
		count += 1
		if distance_value < separation_radius:
			separation -= offset.normalized() * (1.0 - distance_value / separation_radius)
	if count == 0:
		return Vector3.ZERO
	center /= float(count)
	average_velocity /= float(count)
	return (center - global_position).normalized() * 0.35 + average_velocity.normalized() * 0.28 + separation * 2.5


func _goal_steering() -> Vector3:
	if _state == BehaviourState.DIVE:
		return (_locked_target - global_position).normalized()
	if _state == BehaviourState.RECOVER:
		var retreat := (global_position - target_position).normalized()
		return (retreat + Vector3.UP * 0.35).normalized()
	var orbit_radius := 8.5 + fmod(float(_member_id), 4.0) * 0.85
	var orbit_height := 2.8 + fmod(float(_member_id), 3.0) * 0.8
	var orbit_offset := Vector3(cos(_orbit_phase), 0.0, sin(_orbit_phase)) * orbit_radius
	var orbit_target := target_position + Vector3.UP * orbit_height + orbit_offset
	return (orbit_target - global_position).normalized()


func _wall_avoidance() -> Vector3:
	if get_world_3d() == null:
		return Vector3.ZERO
	var forward := velocity.normalized()
	if forward.length_squared() < 0.01:
		forward = (target_position - global_position).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD
	var directions: Array[Vector3] = [
		forward,
		forward.rotated(Vector3.UP, 0.52),
		forward.rotated(Vector3.UP, -0.52),
		(forward + Vector3.UP * 0.42).normalized(),
		(forward + Vector3.DOWN * 0.42).normalized(),
	]
	var avoidance := Vector3.ZERO
	var space := get_world_3d().direct_space_state
	for direction in directions:
		var query := PhysicsRayQueryParameters3D.create(global_position, global_position + direction * wall_probe_distance, 1)
		query.exclude = [get_rid()]
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var distance_ratio := global_position.distance_to(hit.position) / wall_probe_distance
		avoidance += (hit.normal as Vector3) * (1.0 - clampf(distance_ratio, 0.0, 1.0))
	return avoidance


func _resolve_collisions() -> void:
	for index in get_slide_collision_count():
		var normal := get_slide_collision(index).get_normal()
		velocity = velocity.slide(normal) + normal * 2.5


func _face_velocity(delta: float) -> void:
	if velocity.length_squared() < 0.1:
		return
	var forward := velocity.normalized()
	var facing_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.96 else global_basis.y
	var target_basis := Basis.looking_at(forward, facing_up)
	global_basis = global_basis.slerp(target_basis, 1.0 - exp(-7.0 * delta)).orthonormalized()


func _try_dive_hit() -> void:
	if _state != BehaviourState.DIVE:
		return
	var offset := target_position - global_position
	if offset.length() > attack_range:
		return
	SignalBus.player_damage_requested.emit(
		contact_damage,
		global_position,
		offset.normalized() * 7.0 + Vector3.UP * 1.8
	)
	_begin_recovery()


func _begin_recovery() -> void:
	_state = BehaviourState.RECOVER
	_state_timer = recovery_duration
	_slot_requested = false
	_release_attack_slot()


func _release_attack_slot() -> void:
	if not _owns_attack_slot:
		return
	_owns_attack_slot = false
	SignalBus.eye_swarm_attack_slot_released.emit(_member_id)


func _update_warning_visual() -> void:
	var warning := _state == BehaviourState.TELEGRAPH
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.022)
	var scale_multiplier := 1.0 + pulse * 0.22 if warning else 1.0
	model_root.scale = model_root.scale.lerp(_base_model_scale * scale_multiplier, 0.28)
	eye_glow.light_energy = lerpf(0.45, 3.2, pulse) if warning else (1.4 if _state == BehaviourState.DIVE else 0.45)
	eye_glow.light_color = Color(1.0, 0.8, 0.35) if warning else Color(1.0, 0.03, 0.13)


func _publish_state() -> void:
	SignalBus.eye_swarm_member_updated.emit(_member_id, global_position, velocity)


func _on_attack_slot_granted(member_id: int) -> void:
	if member_id != _member_id or _state != BehaviourState.ORBIT:
		return
	_slot_requested = false
	_owns_attack_slot = true
	_state = BehaviourState.TELEGRAPH
	_state_timer = telegraph_duration
	_locked_target = target_position + Vector3.UP * 0.9


func _on_member_updated(member_id: int, position_value: Vector3, velocity_value: Vector3) -> void:
	if member_id != _member_id:
		_neighbours[member_id] = {"position": position_value, "velocity": velocity_value}


func _on_member_removed(member_id: int) -> void:
	_neighbours.erase(member_id)


func _on_player_position(position_value: Vector3) -> void:
	target_position = position_value
