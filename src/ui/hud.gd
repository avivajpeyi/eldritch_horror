extends CanvasLayer

@onready var enemy_health_bar: ProgressBar = $EnemyHealth/Panel/Margin/VBox/HealthBar
@onready var enemy_health_value: Label = $EnemyHealth/Panel/Margin/VBox/Header/Value
@onready var player_health_bar: ProgressBar = $PlayerStats/Panel/Margin/VBox/HealthBar
@onready var player_health_value: Label = $PlayerStats/Panel/Margin/VBox/HealthHeader/Value
@onready var ammo_value: Label = $PlayerStats/Panel/Margin/VBox/AmmoRow/Value
@onready var end_screen: Control = $EndScreen
@onready var end_title: Label = $EndScreen/Center/Panel/Margin/VBox/Title
@onready var end_summary: Label = $EndScreen/Center/Panel/Margin/VBox/Summary
@onready var restart_button: Button = $EndScreen/Center/Panel/Margin/VBox/RestartButton
@onready var quit_button: Button = $EndScreen/Center/Panel/Margin/VBox/QuitButton

var _encounter_finished := false


func _ready() -> void:
	SignalBus.monster_health_changed.connect(_on_monster_health_changed)
	SignalBus.monster_defeated.connect(_on_monster_defeated)
	SignalBus.player_health_changed.connect(_on_player_health_changed)
	SignalBus.player_ammo_changed.connect(_on_player_ammo_changed)
	SignalBus.player_defeated.connect(_on_player_defeated)
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	end_screen.hide()


func _exit_tree() -> void:
	if SignalBus.monster_health_changed.is_connected(_on_monster_health_changed):
		SignalBus.monster_health_changed.disconnect(_on_monster_health_changed)
	if SignalBus.monster_defeated.is_connected(_on_monster_defeated):
		SignalBus.monster_defeated.disconnect(_on_monster_defeated)
	if SignalBus.player_health_changed.is_connected(_on_player_health_changed):
		SignalBus.player_health_changed.disconnect(_on_player_health_changed)
	if SignalBus.player_ammo_changed.is_connected(_on_player_ammo_changed):
		SignalBus.player_ammo_changed.disconnect(_on_player_ammo_changed)
	if SignalBus.player_defeated.is_connected(_on_player_defeated):
		SignalBus.player_defeated.disconnect(_on_player_defeated)


func _on_monster_health_changed(current: float, maximum: float) -> void:
	enemy_health_bar.max_value = maximum
	enemy_health_bar.value = current
	enemy_health_value.text = "%d / %d" % [ceili(current), ceili(maximum)]


func _on_monster_defeated() -> void:
	enemy_health_bar.value = 0.0
	enemy_health_value.text = "0"
	_show_end_screen(false)


func _on_player_health_changed(current: float, maximum: float) -> void:
	player_health_bar.max_value = maximum
	player_health_bar.value = current
	player_health_value.text = "%d / %d" % [ceili(current), ceili(maximum)]


func _on_player_ammo_changed(in_magazine: int, reserve: int) -> void:
	ammo_value.text = "%02d  /  %03d" % [in_magazine, reserve]


func _on_player_defeated() -> void:
	player_health_bar.value = 0.0
	player_health_value.text = "0"
	_show_end_screen(true)


func _show_end_screen(player_lost: bool) -> void:
	if _encounter_finished:
		return
	_encounter_finished = true
	end_title.text = "YOU DIED" if player_lost else "ENEMY DEFEATED"
	end_summary.text = "The arena claims another body." if player_lost else "The horror has been put down."
	end_screen.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	restart_button.grab_focus()


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().quit()
