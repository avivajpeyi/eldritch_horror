class_name SwarmEye
extends CharacterBody3D
## Lightweight flying enemy. Neighbour state is shared only through SignalBus,
## keeping flock steering independent of scene-tree references or navigation.

@export_category("Flight")
@export var cruise_speed := 8.5
@export var chase_speed := 12.0
@export var acceleration := 14.0
@export var neighbour_radius := 8.0
@export var separation_radius := 2.1
@export var wall_probe_distance := 4.5
@export_category("Behaviour")
@export var chase_duration_min := 1.6
@export var chase_duration_max := 3.2
@export var roam_duration_min := 2.2
@export var roam_duration_max := 4.8
@export var contact_damage := 9.0
@export var attack_range := 1.45
@export var attack_cooldown := 1.4
@export_category("Durability")
@export var max_health := 35.0

var target_position := Vector3.ZERO
var health := 0.0

var _member_id := 0
var _neighbours: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _wander_direction := Vector3.FORWARD
var _wander_timer := 0.0
var _behaviour_timer := 0.0
var _attack_timer := 0.8
var _publish_timer := 0.0
var _chasing := false
var _orbit_phase := 0.0


func _ready() -> void:
	_member_id = get_instance_id()
	_rng.seed = _member_id * 7919
	health = max_health
	_orbit_phase = _rng.randf_range(0.0, TAU)
	_wander_direction = _random_direction()
	_behaviour_timer = _rng.randf_range(roam_duration_min, roam_duration_max)
	add_to_group("Enemies")
	add_to_group("eye_swarm")
	SignalBus.player_position_updated.connect(_on_player_position)
	SignalBus.eye_swarm_member_updated.connect(_on_member_updated)
	SignalBus.eye_swarm_member_removed.connect(_on_member_removed)
	_publish_state()


func _exit_tree() -> void:
	SignalBus.eye_swarm_member_removed.emit(_member_id)
	if SignalBus.player_position_updated.is_connected(_on_player_position):
		SignalBus.player_position_updated.disconnect(_on_player_position)
	if SignalBus.eye_swarm_member_updated.is_connected(_on_member_updated):
		SignalBus.eye_swarm_member_updated.disconnect(_on_member_updated)
	if SignalBus.eye_swarm_member_removed.is_connected(_on_member_removed):
		SignalBus.eye_swarm_member_removed.disconnect(_on_member_removed)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	var steering := _swarm_steering()
	steering += _goal_steering() * (1.55 if _chasing else 0.72)
	steering += _wander_direction * (0.18 if _chasing else 0.68)
	steering += _wall_avoidance() * 3.4
	var target_speed := chase_speed if _chasing else cruise_speed
	var desired_velocity := steering.normalized() * target_speed
	velocity = velocity.lerp(desired_velocity, 1.0 - exp(-acceleration * delta))
	move_and_slide()
	_resolve_collisions()
	_face_velocity(delta)
	_try_attack()
	_publish_timer -= delta
	if _publish_timer <= 0.0:
		_publish_timer = 0.08
		_publish_state()


func take_damage(amount: float, _damage_type := GameManager.ElementType.KINETIC) -> void:
	if amount <= 0.0:
		return
	health -= amount
	if health <= 0.0:
		SignalBus.minion_destroyed.emit()
		queue_free()


func hitscan_hit(damage: float, _direction: Vector3, _position: Vector3) -> void:
	take_damage(damage)


func hitscan_hit_typed(damage: float, damage_type: int, _direction: Vector3, _position: Vector3) -> void:
	take_damage(damage, damage_type)


func projectile_hit(damage: float, _direction: Vector3) -> void:
	take_damage(damage)


func projectile_hit_typed(damage: float, damage_type: int, _direction: Vector3) -> void:
	take_damage(damage, damage_type)


func _update_timers(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)
	_behaviour_timer -= delta
	_wander_timer -= delta
	_orbit_phase += delta * (0.7 + fmod(float(_member_id), 7.0) * 0.025)
	if _behaviour_timer <= 0.0:
		_chasing = not _chasing
		_behaviour_timer = (
			_rng.randf_range(chase_duration_min, chase_duration_max)
			if _chasing
			else _rng.randf_range(roam_duration_min, roam_duration_max)
		)
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(0.55, 1.25)
		_wander_direction = (_wander_direction * 0.55 + _random_direction() * 0.45).normalized()


func _swarm_steering() -> Vector3:
	var center := Vector3.ZERO
	var average_velocity := Vector3.ZERO
	var separation := Vector3.ZERO
	var count := 0
	for state: Dictionary in _neighbours.values():
		var neighbour_position: Vector3 = state["position"]
		var offset := neighbour_position - global_position
		var distance_value := offset.length()
		if distance_value <= 0.001 or distance_value > neighbour_radius:
			continue
		center += neighbour_position
		average_velocity += state["velocity"] as Vector3
		count += 1
		if distance_value < separation_radius:
			separation -= offset.normalized() * (1.0 - distance_value / separation_radius)
	if count == 0:
		return Vector3.ZERO
	center /= float(count)
	average_velocity /= float(count)
	var cohesion := (center - global_position).normalized()
	var alignment := average_velocity.normalized()
	return cohesion * 0.42 + alignment * 0.34 + separation * 2.2


func _goal_steering() -> Vector3:
	if _chasing:
		return (target_position + Vector3.UP * 1.2 - global_position).normalized()
	var orbit_radius := 7.0 + fmod(float(_member_id), 5.0) * 0.7
	var orbit_height := 2.4 + fmod(float(_member_id), 4.0) * 0.65
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
		var query := PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + direction * wall_probe_distance,
			1
		)
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
	var target_basis := Basis.looking_at(velocity.normalized(), Vector3.UP)
	global_basis = global_basis.slerp(target_basis, 1.0 - exp(-8.0 * delta)).orthonormalized()


func _try_attack() -> void:
	if _attack_timer > 0.0:
		return
	var offset := target_position - global_position
	if offset.length() > attack_range:
		return
	SignalBus.player_damage_requested.emit(
		contact_damage,
		global_position,
		offset.normalized() * 5.0 + Vector3.UP * 1.5
	)
	_attack_timer = attack_cooldown
	_chasing = false
	_behaviour_timer = _rng.randf_range(1.4, 2.2)
	velocity = -offset.normalized() * cruise_speed


func _publish_state() -> void:
	SignalBus.eye_swarm_member_updated.emit(_member_id, global_position, velocity)


func _on_member_updated(member_id: int, position_value: Vector3, velocity_value: Vector3) -> void:
	if member_id == _member_id:
		return
	_neighbours[member_id] = {"position": position_value, "velocity": velocity_value}


func _on_member_removed(member_id: int) -> void:
	_neighbours.erase(member_id)


func _on_player_position(position_value: Vector3) -> void:
	target_position = position_value


func _random_direction() -> Vector3:
	return Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.45, 0.45),
		_rng.randf_range(-1.0, 1.0)
	).normalized()
