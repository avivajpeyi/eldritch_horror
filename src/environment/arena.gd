extends Node3D

@export_category("Arena Scale")
@export var arena_radius := 48.0
@export var wall_height := 24.0
@export var ritual_radius := 20.0
@export var pillar_radius := 36.0
@export var upper_ring_height := 17.5

## Architecture stays cold and nearly neutral. Reserve saturated light for
## readable gameplay landmarks and the monster's attacks/weak points.
const STONE := Color("11141c")
const STONE_RAISED := Color("242733")
const STONE_EDGE := Color("45424b")
const STONE_WET := Color("181c26")
const RITUAL_GLOW := Color("d6b779")
const ABYSS := Color("07050d")

const SHRINE_COLORS := [Color("c73f52"), Color("4f9fd8"), Color("65c77d")]
const SHRINE_NAMES := ["Red Shrine", "Blue Shrine", "Green Shrine"]

var _flicker_lights: Array[OmniLight3D] = []
var _flicker_time := 0.0


func _ready() -> void:
	_build_atmosphere()
	_build_octagonal_chamber()
	_build_ceiling()
	_build_summoning_circle()
	_build_pillars()
	_build_broken_upper_ring()
	_build_elemental_shrines()
	_build_floor_breakup()


func _process(delta: float) -> void:
	# A tiny irregular pulse keeps static light sources from feeling like editor props.
	_flicker_time += delta
	for i in _flicker_lights.size():
		var pulse := 0.9 + sin(_flicker_time * (2.1 + i * 0.17) + i * 2.4) * 0.08
		_flicker_lights[i].light_energy = 2.2 * pulse


func _build_atmosphere() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = ABYSS
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("273346")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.85
	environment.glow_strength = 0.72
	environment.ssao_enabled = true
	environment.ssao_radius = 2.2
	environment.ssao_intensity = 2.1
	environment.fog_enabled = true
	environment.fog_light_color = Color("182235")
	environment.fog_light_energy = 0.55
	environment.fog_density = 0.009
	environment.fog_sky_affect = 0.22
	world.environment = environment
	add_child(world)

	# A pale ritual key light, blue upper fill, and warm rim give the central fight
	# space depth without flooding the chamber with a single purple value.
	_add_omni_light(Vector3(0, 7.0, 0), RITUAL_GLOW, 9.5, 32.0)
	_add_omni_light(Vector3(0, 20.0, -14.0), Color("7794be"), 5.5, 30.0)
	_add_omni_light(Vector3(-18.0, 7.0, -21.0), Color("a9514c"), 3.5, 20.0)
	for i in 4:
		var angle := TAU * float(i) / 4.0 + PI * 0.25
		_add_omni_light(Vector3(cos(angle) * 28.0, 7.0, sin(angle) * 28.0), Color("42587e"), 3.2, 22.0)


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
		var position := Vector3(cos(angle) * pillar_radius, 0.0, sin(angle) * pillar_radius)
		_add_cylinder(position + Vector3.UP * 0.65, 2.4, 1.3, STONE_EDGE, 8, true)
		_add_cylinder(position + Vector3.UP * wall_height * 0.5, 1.7, wall_height - 2.4, STONE_RAISED, 8, true)
		_add_cylinder(position + Vector3.UP * (wall_height - 0.65), 2.35, 0.65, STONE_EDGE, 8, true)
		# Warm, low-intensity glyphs read as ancient architecture, not ammo UI.
		var glyph_position := position + Vector3.UP * (wall_height * 0.4) - Vector3(cos(angle), 0.0, sin(angle)) * 1.68
		_add_box(glyph_position, Vector3(0.11, 5.4, 0.36), RITUAL_GLOW, -angle, false, true)
		_add_box(glyph_position + Vector3.UP * 4.7, Vector3(0.11, 0.62, 0.9), RITUAL_GLOW, -angle, false, true)


func _build_broken_upper_ring() -> void:
	# Traversable fragments connect the pillars without creating one safe continuous ledge.
	for i in 8:
		if i == 2 or i == 6:
			continue
		var angle := TAU * (float(i) + 0.5) / 8.0
		var length := 14.5 if i % 3 else 10.8
		_add_box(
			Vector3(cos(angle) * pillar_radius, upper_ring_height, sin(angle) * pillar_radius),
			Vector3(3.5, 0.8, length + 3.0),
			STONE_EDGE,
			-angle
		)


func _build_elemental_shrines() -> void:
	# These deliberately match the three ammo elements in the design document. They
	# are presentation-only for now, so future AmmoPool Area3Ds can be attached here
	# without changing the arena's lighting or silhouette.
	var shrine_angles := [PI * 0.08, PI * 0.75, PI * 1.42]
	for i in shrine_angles.size():
		var angle: float = shrine_angles[i]
		var position := Vector3(cos(angle) * (arena_radius - 8.0), 0.0, sin(angle) * (arena_radius - 8.0))
		var color: Color = SHRINE_COLORS[i]
		var shrine := Node3D.new()
		shrine.name = SHRINE_NAMES[i]
		shrine.position = position
		add_child(shrine)
		_add_cylinder_to(shrine, Vector3(0, 0.4, 0), 3.0, 0.8, STONE_EDGE, 8)
		_add_cylinder_to(shrine, Vector3(0, 0.84, 0), 2.1, 0.16, color, 32, false, true)
		for rune in 4:
			var rune_angle := TAU * float(rune) / 4.0
			var rune_position := Vector3(cos(rune_angle) * 2.4, 0.9, sin(rune_angle) * 2.4)
			_add_box_to(shrine, rune_position, Vector3(0.25, 0.08, 0.82), color, -rune_angle, false, true)
		var light := _add_omni_light(position + Vector3.UP * 1.7, color, 3.0, 13.0)
		_flicker_lights.append(light)


func _build_floor_breakup() -> void:
	# Radial slab seams and small, raised fragments make the long routes legible
	# while keeping the central combat circle clean for projectile readability.
	for i in 16:
		var angle := TAU * float(i) / 16.0 + PI / 16.0
		var distance := 28.0 + float(i % 3) * 3.2
		var size := Vector3(1.7 + float(i % 2) * 0.65, 0.12, 6.5 + float(i % 4) * 0.9)
		_add_box(
			Vector3(cos(angle) * distance, 0.14, sin(angle) * distance),
			size,
			STONE_RAISED,
			-angle + PI * 0.5,
			false
		)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var position := Vector3(cos(angle) * 23.0, 0.15, sin(angle) * 23.0)
		_add_box(position, Vector3(5.8, 0.1, 0.52), STONE_WET, -angle, false)


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


func _add_box_to(parent: Node3D, position: Vector3, size: Vector3, color: Color, rotation_y := 0.0, collision_enabled := true, emissive := false) -> void:
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
	parent.add_child(root)


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


func _add_cylinder_to(parent: Node3D, position: Vector3, radius: float, height: float, color: Color, sides: int, collision_enabled := true, emissive := false) -> void:
	var root: Node3D = StaticBody3D.new() if collision_enabled else Node3D.new()
	root.position = position
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = sides
	cylinder.material = _material(color, emissive)
	mesh.mesh = cylinder
	root.add_child(mesh)
	if collision_enabled:
		var collision := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collision.shape = shape
		root.add_child(collision)
	parent.add_child(root)


func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 4.5
	return material


func _add_omni_light(position: Vector3, color: Color, energy: float, range_value: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = true
	add_child(light)
	return light
