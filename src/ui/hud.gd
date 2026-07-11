extends CanvasLayer

@onready var health_bar: ProgressBar = $BossHealthPanel/Margin/VBox/HealthBar
@onready var player_health_bar: ProgressBar = $PlayerHealthPanel/Margin/VBox/HealthBar

func _ready() -> void:
	SignalBus.monster_health_changed.connect(_on_monster_health_changed)
	SignalBus.monster_defeated.connect(_on_monster_defeated)
	SignalBus.player_health_changed.connect(_on_player_health_changed)
	SignalBus.player_defeated.connect(_on_player_defeated)

func _exit_tree() -> void:
	if SignalBus.monster_health_changed.is_connected(_on_monster_health_changed):
		SignalBus.monster_health_changed.disconnect(_on_monster_health_changed)
	if SignalBus.monster_defeated.is_connected(_on_monster_defeated):
		SignalBus.monster_defeated.disconnect(_on_monster_defeated)
	if SignalBus.player_health_changed.is_connected(_on_player_health_changed):
		SignalBus.player_health_changed.disconnect(_on_player_health_changed)
	if SignalBus.player_defeated.is_connected(_on_player_defeated):
		SignalBus.player_defeated.disconnect(_on_player_defeated)

func _on_monster_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

func _on_monster_defeated() -> void:
	health_bar.value = 0.0

func _on_player_health_changed(current: float, maximum: float) -> void:
	player_health_bar.max_value = maximum
	player_health_bar.value = current

func _on_player_defeated() -> void:
	player_health_bar.value = 0.0
