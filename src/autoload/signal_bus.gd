# signal_bus.gd (Autoload Singleton)
extends Node

# Global Event Hooks for decoupled feature cross-talk
signal ammo_changed(new_type)         # Emitted by ammo pools, caught by player/UI
signal monster_state_changed(new_state) # Emitted by monster FSM, caught by arena/UI
signal minion_destroyed()             # Emitted by spiders, caught by monster Nest state
signal monster_collapsed()            # Emitted when monster drops to the floor
