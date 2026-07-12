extends MeshInstance3D
## Rendering-only response for an elemental anchor weakpoint.

@export var anchor_id: StringName

var _material: StandardMaterial3D
var _base_scale := Vector3.ONE


func _ready() -> void:
	_base_scale = scale
	_material = material_override.duplicate() as StandardMaterial3D
	material_override = _material
	SignalBus.monster_anchor_state_changed.connect(_on_anchor_state_changed)


func _exit_tree() -> void:
	if SignalBus.monster_anchor_state_changed.is_connected(_on_anchor_state_changed):
		SignalBus.monster_anchor_state_changed.disconnect(_on_anchor_state_changed)


func _on_anchor_state_changed(changed_id: StringName, element_type: int, health: float, maximum: float, broken: bool) -> void:
	if changed_id != anchor_id:
		return
	var color := _element_color(element_type)
	var health_ratio := clampf(health / maxf(maximum, 0.01), 0.0, 1.0)
	_material.albedo_color = color.darkened(0.75) if broken else color
	_material.emission = color
	_material.emission_energy_multiplier = 0.02 if broken else lerpf(0.22, 0.62, health_ratio)
	scale = _base_scale * (0.72 if broken else 1.0)


func _element_color(element_type: int) -> Color:
	match element_type:
		GameManager.ElementType.RED: return Color(1.0, 0.08, 0.035)
		GameManager.ElementType.BLUE: return Color(0.05, 0.38, 1.0)
		GameManager.ElementType.GREEN: return Color(0.08, 1.0, 0.34)
	return Color(0.3, 0.008, 0.014)
