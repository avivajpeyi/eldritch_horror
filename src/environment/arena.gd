extends Node3D

@export_category("Arena Scale")
@export var arena_radius := 30.0
@export var wall_height := 14.0
@export var ritual_radius := 13.0

const STONE := Color("171522")
const STONE_RAISED := Color("29243a")
const STONE_EDGE := Color("3b3150")
const RITUAL_GLOW := Color("8b3dba")
const ABYSS := Color("07050d")


func _ready() -> void:
	_build_atmosphere()
	_build_octagonal_chamber()
	_build_ceiling()
	_build_summoning_circle()
	_build_pillars()
	_build_broken_upper_ring()


func _build_atmosphere() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = ABYSS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("302447")
	environment.ambient_light_energy = 0.64
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	world.environment = environment
	add_child(world)

	_add_omni_light(Vector3(0, 6.0, 0), RITUAL_GLOW, 11.0, 24.0)
	# Cool fill defines wet black forms; the dim red side light separates limbs.
	_add_omni_light(Vector3(0, 11.5, -9.0), Color("7184a8"), 6.2, 19.0)
	_add_omni_light(Vector3(-9.0, 5.0, -12.0), Color("8c273d"), 3.0, 12.0)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		_add_omni_light(Vector3(cos(angle) * 17.0, 4.0, sin(angle) * 17.0), Color("4b3578"), 4.0, 13.0)


func _build_octagonal_chamber() -> void:
	# Broad octagonal floor: roughly four times the old playable footprint.
	_add_cylinder(Vector3(0, -0.65, 0), arena_radius, 1.3, STONE, 8, true)
	_add_cylinder(Vector3(0, 0.03, 0), arena_radius - 0.8, 0.12, Color("201c2d"), 8, false)

	var side_length := 2.0 * arena_radius * tan(PI / 8.0)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var wall_position := Vector3(cos(angle), 0.0, sin(angle)) * arena_radius
		_add_box(
			wall_position + Vector3.UP * wall_height * 0.5,
			Vector3(0.9, wall_height, side_length + 0.7),
			STONE,
			-angle
		)


func _build_ceiling() -> void:
	# A heavy lid closes the room while layered bosses keep the center from reading flat.
	_add_cylinder(Vector3(0, wall_height + 0.65, 0), arena_radius, 1.3, Color("0f0d18"), 8, true)
	_add_cylinder(Vector3(0, wall_height - 0.04, 0), arena_radius - 0.9, 0.12, STONE_RAISED, 8, false)
	_add_cylinder(Vector3(0, wall_height - 0.18, 0), ritual_radius + 4.0, 0.28, STONE_EDGE, 64, false)
	_add_cylinder(Vector3(0, wall_height - 0.38, 0), ritual_radius + 1.2, 0.22, Color("21192e"), 64, false)
	_add_ritual_ring_at_height(ritual_radius + 2.7, 0.12, wall_height - 0.51)
	_add_ritual_ring_at_height(ritual_radius - 0.2, 0.08, wall_height - 0.51)


func _build_summoning_circle() -> void:
	# A stepped central altar gives the ritual a readable gameplay landmark.
	_add_cylinder(Vector3(0, 0.12, 0), ritual_radius + 1.4, 0.24, STONE_EDGE, 64, true)
	_add_cylinder(Vector3(0, 0.27, 0), ritual_radius + 0.8, 0.18, STONE_RAISED, 64, true)
	_add_cylinder(Vector3(0, 0.39, 0), ritual_radius, 0.12, Color("211a2c"), 64, true)

	_add_ritual_ring(ritual_radius + 0.95, 0.16)
	_add_ritual_ring(ritual_radius - 0.25, 0.11)
	_add_ritual_ring(ritual_radius * 0.58, 0.09)
	_add_ritual_ring(2.25, 0.12)

	# Eight radial sigil spokes and an offset inner star suggest an active seal.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		_add_glowing_bar(angle, 6.6, 0.13, 7.0)
		_add_glowing_bar(angle + PI / 8.0, 3.9, 0.09, 3.0)

	for i in 5:
		var angle := TAU * float(i) / 5.0 - PI * 0.5
		var next_angle := TAU * float((i + 2) % 5) / 5.0 - PI * 0.5
		var from := Vector3(cos(angle) * 4.7, 0.52, sin(angle) * 4.7)
		var to := Vector3(cos(next_angle) * 4.7, 0.52, sin(next_angle) * 4.7)
		_add_line_between(from, to, 0.11, RITUAL_GLOW)


func _build_pillars() -> void:
	for i in 8:
		var angle := TAU * (float(i) + 0.5) / 8.0
		var position := Vector3(cos(angle) * 22.5, 0.0, sin(angle) * 22.5)
		_add_cylinder(position + Vector3.UP * 0.45, 1.65, 0.9, STONE_EDGE, 8, true)
		_add_cylinder(position + Vector3.UP * 7.05, 1.15, 12.3, STONE_RAISED, 8, true)
		_add_cylinder(position + Vector3.UP * 13.35, 1.6, 0.45, STONE_EDGE, 8, true)
		# Vertical violet glyph cut makes the columns visible in the gloom.
		var glyph_position := position + Vector3.UP * 5.5 - Vector3(cos(angle), 0.0, sin(angle)) * 1.13
		_add_box(glyph_position, Vector3(0.08, 3.5, 0.25), RITUAL_GLOW, -angle, false, true)


func _build_broken_upper_ring() -> void:
	# Traversable fragments connect the pillars without creating one safe continuous ledge.
	for i in 8:
		if i == 2 or i == 6:
			continue
		var angle := TAU * (float(i) + 0.5) / 8.0
		var length := 9.2 if i % 3 else 6.8
		_add_box(
			Vector3(cos(angle) * 22.5, 10.25, sin(angle) * 22.5),
			Vector3(2.4, 0.55, length + 2.0),
			STONE_EDGE,
			-angle
		)


func _add_ritual_ring(radius: float, thickness: float) -> void:
	_add_ritual_ring_at_height(radius, thickness, 0.52)


func _add_ritual_ring_at_height(radius: float, thickness: float, height: float) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.position.y = height
	var torus := TorusMesh.new()
	torus.inner_radius = radius - thickness
	torus.outer_radius = radius + thickness
	torus.rings = 64
	torus.ring_segments = 8
	torus.material = _material(RITUAL_GLOW, true)
	mesh_instance.mesh = torus
	add_child(mesh_instance)


func _add_glowing_bar(angle: float, distance: float, width: float, length: float) -> void:
	var center := Vector3(cos(angle), 0.0, sin(angle)) * distance
	_add_box(center + Vector3.UP * 0.5, Vector3(width, 0.045, length), RITUAL_GLOW, -angle, false, true)


func _add_line_between(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var midpoint := (from + to) * 0.5
	var delta := to - from
	_add_box(midpoint, Vector3(width, 0.045, delta.length()), color, -atan2(delta.z, delta.x) + PI * 0.5, false, true)


func _add_box(position: Vector3, size: Vector3, color: Color, rotation_y := 0.0, collision_enabled := true, emissive := false) -> void:
	var root: Node3D = StaticBody3D.new() if collision_enabled else Node3D.new()
	root.position = position
	root.rotation.y = rotation_y
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color, emissive)
	mesh.mesh = box
	root.add_child(mesh)
	if collision_enabled:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		root.add_child(collision)
	add_child(root)


func _add_cylinder(position: Vector3, radius: float, height: float, color: Color, sides: int, collision_enabled: bool) -> void:
	var root: Node3D = StaticBody3D.new() if collision_enabled else Node3D.new()
	root.position = position
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = sides
	cylinder.material = _material(color)
	mesh.mesh = cylinder
	root.add_child(mesh)
	if collision_enabled:
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collision.shape = shape
		root.add_child(collision)
	add_child(root)


func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.5
	return material


func _add_omni_light(position: Vector3, color: Color, energy: float, range_value: float) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = true
	add_child(light)
