class_name MonsterLegAnchor
extends Node3D
## One independent spider leg. It owns surface probing and visual resolution only.

signal step_started(leg: MonsterLegAnchor)
signal step_finished(leg: MonsterLegAnchor)

@export var max_leg_length := 8.2
@export var step_threshold := 1.35
@export var step_height := 0.8
@export var step_duration := 0.34
@export var upper_radius := 0.68
@export var lower_radius := 0.085
@export var knee_lift := 1.75
@export var probe_spread := 1.3
@export var curl_amount := 0.82
@export var idle_twitch := 0.18
@export var curve_sections := 9
@export_range(4, 6) var muscle_strands := 5
@export_range(6, 16) var tube_sides := 7
@export var bundle_radius := 0.62
@export var strand_radius := 0.19
@export var braid_turns := 2.25

@onready var raycast: RayCast3D = $RayCast3D
@onready var foot_marker: Marker3D = $Marker3D
@onready var leg_mesh: MeshInstance3D = $MeshInstance3D
var mesh := ArrayMesh.new()
static var _shared_anchor_normal: ImageTexture

var current_foot_global_pos := Vector3.ZERO
var target_foot_global_pos := Vector3.ZERO
var surface_normal := Vector3.UP
var is_stepping := false
var is_planted := false
var can_step := true
var _step_elapsed := 0.0
var _step_origin := Vector3.ZERO
var _motion_time := 0.0
var _phase_offset := 0.0

func _ready() -> void:
	_phase_offset = float(get_index()) * 1.91
	leg_mesh.mesh = mesh
	_create_anchor_decal()
	raycast.enabled = true
	raycast.force_raycast_update()
	if raycast.is_colliding():
		_set_initial_foot(raycast.get_collision_point(), raycast.get_collision_normal())
	else:
		_set_initial_foot(raycast.to_global(raycast.target_position), Vector3.UP)

func _physics_process(delta: float) -> void:
	_motion_time += delta
	if is_stepping:
		_update_step(delta)
	elif is_planted:
		_probe_for_step()
	else:
		current_foot_global_pos = current_foot_global_pos.lerp(global_position, 1.0 - exp(-8.0 * delta))
	foot_marker.global_position = current_foot_global_pos
	_align_foot()
	_draw_jointed_leg()

func _set_initial_foot(point: Vector3, normal: Vector3) -> void:
	current_foot_global_pos = point
	target_foot_global_pos = point
	surface_normal = normal.normalized()
	is_planted = true

func _probe_for_step() -> void:
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return
	var candidate := raycast.get_collision_point()
	var overstretched := global_position.distance_to(current_foot_global_pos) > max_leg_length
	var target_shifted := current_foot_global_pos.distance_to(candidate) > step_threshold
	if can_step and (overstretched or target_shifted):
		request_step(candidate, raycast.get_collision_normal())

func request_step(point: Vector3, normal: Vector3) -> void:
	if is_stepping or not can_step:
		return
	is_stepping = true
	is_planted = false
	_step_elapsed = 0.0
	_step_origin = current_foot_global_pos
	target_foot_global_pos = point
	surface_normal = normal.normalized()
	step_started.emit(self)

func release() -> void:
	is_stepping = false
	is_planted = false
	can_step = false

func enable_planting() -> void:
	can_step = true
	raycast.force_raycast_update()
	if raycast.is_colliding():
		request_step(raycast.get_collision_point(), raycast.get_collision_normal())

func force_probe() -> bool:
	can_step = true
	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return false
	request_step(raycast.get_collision_point(), raycast.get_collision_normal())
	return true

func set_surface_direction(normal: Vector3) -> void:
	if normal.length_squared() < 0.01:
		return
	var local_normal := global_basis.inverse() * normal.normalized()
	var outward := Vector3(raycast.target_position.x, 0.0, raycast.target_position.z).normalized()
	raycast.target_position = outward * 4.8 - local_normal * 5.6

func _update_step(delta: float) -> void:
	_step_elapsed += delta
	var t := clampf(_step_elapsed / maxf(step_duration, 0.01), 0.0, 1.0)
	var smooth_t := t * t * (3.0 - 2.0 * t)
	current_foot_global_pos = _step_origin.lerp(target_foot_global_pos, smooth_t)
	current_foot_global_pos += surface_normal * sin(t * PI) * step_height
	if t >= 1.0:
		current_foot_global_pos = target_foot_global_pos
		is_stepping = false
		is_planted = true
		step_finished.emit(self)

func _align_foot() -> void:
	if surface_normal.length_squared() < 0.01:
		return
	var forward := global_basis.z.slide(surface_normal).normalized()
	if forward.length_squared() < 0.01:
		forward = Vector3.FORWARD.slide(surface_normal).normalized()
	foot_marker.global_basis = Basis.looking_at(forward, surface_normal)

func _draw_jointed_leg() -> void:
	var hip := Vector3.ZERO
	var foot := to_local(current_foot_global_pos)
	var outward := foot.normalized()
	var body_up := to_local(global_position + global_basis.y) - to_local(global_position)
	var side := outward.cross(body_up).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	var twitch := sin(_motion_time * 2.3 + _phase_offset) * idle_twitch
	var knee := foot * 0.28 + body_up.normalized() * (knee_lift + twitch) + outward * probe_spread
	var ankle := foot * 0.72 - body_up.normalized() * (knee_lift * 0.5) + side * (curl_amount + twitch)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stretch_ratio := clampf(foot.length() / maxf(max_leg_length, 0.01), 0.0, 1.0)
	var tension_scale := lerpf(1.0, 0.58, smoothstep(0.55, 1.0, stretch_ratio))
	_draw_muscle_trunk(tool, hip, knee, ankle, foot, tension_scale)
	for strand in muscle_strands:
		_draw_braided_strand(tool, hip, knee, ankle, foot, strand, tension_scale)
	mesh.clear_surfaces()
	tool.commit(mesh)

func _draw_muscle_trunk(tool: SurfaceTool, hip: Vector3, knee: Vector3, ankle: Vector3, foot: Vector3, tension_scale: float) -> void:
	# A heavy root projects beyond the mantle before separating into strands. The
	# subtle pulse is geometry motion, so it remains visible even in flat lighting.
	var pulse := 1.0 + sin(_motion_time * 2.15 + _phase_offset) * 0.07
	var shoulder := _cubic_bezier(hip, knee, ankle, foot, 0.105)
	var split := _cubic_bezier(hip, knee, ankle, foot, 0.22)
	var root_radius := upper_radius * tension_scale * pulse
	_add_tube_section(tool, hip, shoulder, root_radius, root_radius * 0.86)
	_add_tube_section(tool, shoulder, split, root_radius * 0.86, maxf(strand_radius * 1.7, root_radius * 0.58))

func _draw_braided_strand(tool: SurfaceTool, hip: Vector3, knee: Vector3, ankle: Vector3, foot: Vector3, strand: int, tension_scale: float) -> void:
	var previous_center := hip
	var previous_radius := strand_radius * 1.15 * tension_scale
	for section in curve_sections:
		var t := float(section + 1) / float(curve_sections)
		var center := _braided_center(hip, knee, ankle, foot, strand, t)
		var taper := pow(maxf(1.0 - t, 0.025), 0.72)
		var tension_taper := lerpf(1.0, 0.42, t * (1.0 - tension_scale))
		var muscle_radius := strand_radius * taper * tension_taper * tension_scale
		var radius := lerpf(muscle_radius, lower_radius, smoothstep(0.84, 1.0, t))
		_add_tube_section(tool, previous_center, center, previous_radius, radius)
		previous_center = center
		previous_radius = radius

func _braided_center(hip: Vector3, knee: Vector3, ankle: Vector3, foot: Vector3, strand: int, t: float) -> Vector3:
	var center := _cubic_bezier(hip, knee, ankle, foot, t)
	var ahead := _cubic_bezier(hip, knee, ankle, foot, minf(t + 0.025, 1.0))
	var tangent := (ahead - center).normalized()
	if tangent.length_squared() < 0.01:
		tangent = (foot - hip).normalized()
	var normal := tangent.cross(Vector3.UP)
	if normal.length_squared() < 0.01:
		normal = tangent.cross(Vector3.RIGHT)
	normal = normal.normalized()
	var binormal := tangent.cross(normal).normalized()
	var strand_phase := TAU * float(strand) / float(muscle_strands)
	var twist := t * TAU * braid_turns + strand_phase + _motion_time * 0.72 + _phase_offset
	var envelope := sin(PI * clampf(t * 1.08, 0.0, 1.0))
	var writhing := sin(_motion_time * 1.45 + t * 7.0 + strand_phase) * 0.055 * t
	var offset_radius := (bundle_radius + writhing) * envelope
	return center + (normal * cos(twist) + binormal * sin(twist)) * offset_radius

func _cubic_bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var inverse := 1.0 - t
	return inverse * inverse * inverse * a + 3.0 * inverse * inverse * t * b + 3.0 * inverse * t * t * c + t * t * t * d

func _add_tube_section(tool: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float) -> void:
	var direction := (b - a).normalized()
	if direction.length_squared() < 0.01:
		return
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var binormal := direction.cross(side).normalized()
	for ring in tube_sides:
		var next := (ring + 1) % tube_sides
		var angle_a := TAU * float(ring) / tube_sides
		var angle_b := TAU * float(next) / tube_sides
		var normal_a := side * cos(angle_a) + binormal * sin(angle_a)
		var normal_b := side * cos(angle_b) + binormal * sin(angle_b)
		var a0 := a + normal_a * radius_a
		var a1 := a + normal_b * radius_a
		var b0 := b + normal_a * radius_b
		var b1 := b + normal_b * radius_b
		_add_triangle(tool, a0, b0, b1, normal_a, normal_a, normal_b)
		_add_triangle(tool, a0, b1, a1, normal_a, normal_b, normal_b)

func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	tool.set_normal(na); tool.add_vertex(a)
	tool.set_normal(nb); tool.add_vertex(b)
	tool.set_normal(nc); tool.add_vertex(c)

func _create_anchor_decal() -> void:
	if _shared_anchor_normal == null:
		_shared_anchor_normal = _build_ligament_normal()
	var decal := Decal.new()
	decal.name = "FleshAnchorDecal"
	decal.position = Vector3(0.0, -0.08, 0.0)
	decal.rotation.x = PI * 0.5
	decal.size = Vector3(1.65, 1.65, 0.85)
	decal.texture_normal = _shared_anchor_normal
	decal.modulate = Color(0.38, 0.018, 0.025, 0.78)
	add_child(decal)

func _build_ligament_normal() -> ImageTexture:
	const SIZE := 64
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var uv := Vector2(float(x), float(y)) / SIZE - Vector2(0.5, 0.5)
			var radius_value := uv.length()
			var angle := atan2(uv.y, uv.x)
			var radial_fiber := sin(angle * 13.0 + radius_value * 42.0) * exp(-radius_value * 2.8)
			var nx := cos(angle) * radial_fiber * 0.72
			var ny := sin(angle) * radial_fiber * 0.72
			var normal := Vector3(nx, ny, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, clampf(1.0 - radius_value * 1.7, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
