# Agent Instructions: Project Monster Slime

You are an expert game developer specializing in Godot 4.x (GDScript). You adhere strictly to component-based, decoupled design patterns, emphasizing scannability, optimization, and strict feature boundaries.

---

## 1. Core Architectural Rules

* **No Direct Cross-Node Referencing:** To avoid tight coupling, features must communicate via the global Event Bus (`SignalBus`). For example, an ammo pool must never look for the Player node; it must emit a signal to the `SignalBus`.
* **Decoupled Rendering:** Visual elements (shaders, mesh generation, scale manipulation) must be decoupled from spatial physics logic. The `monster_core` moves conceptually as an independent body; the limbs dynamically resolve their transforms to visually match it.
* **Static Asset Boundaries:** Code, scenes, and internal resources live in `src/`. All raw, immutable binaries (Blender files, textures, sound libraries) live in `assets/`.

---

## 2. Directory Tree Mapping

Maintain this project layout implicitly when writing scripts or instantiating scenes:

```text
my_monster_game/
├── assets/                  # Global immutable raw data
│   ├── materials/           # Shared environment/actor spatial materials
│   ├── shaders/             # Vertex displacement, screen-space metaballs
│   └── sounds/              # Audio arrays and stems
└── src/                     # Code & runtime scene definitions
    ├── autoload/            # Global persistent nodes
    │   ├── game_manager.gd  # Rules, scores, type enums
    │   └── signal_bus.gd    # Event Bus singleton
    ├── entities/            # Core actors
    │   ├── player/          # Kinematic controller & harpoon tools
    │   ├── minions/         # Eyeball spiders (NavMesh agents)
    │   └── monster/         # FSM core body and procedural limbs
    │       ├── components/  # Raycast steps & mesh-drawing logic
    │       └── states/      # State isolation scripts
    ├── environment/         # Octagonal arena & interactive structures
    │   └── ammo_pools/      # Trigger zones for elemental pooling
    └── ui/                  # HUD, reticles, state overlays


3. Global Singletons & Communication Protocols

SignalBus (Autoload)
GDScript

```
extends Node

signal ammo_changed(new_type: int)        # Emitted by ammo pools
signal monster_state_changed(new_state: int) # Emitted by monster core FSM
signal minion_destroyed()                 # Emitted by eyeball spiders
signal monster_collapsed()                # Emitted when core loses anchorage
```


Type Registries (GameManager)


GDScript

```
extends Node

enum ElementType { KINETIC, RED, BLUE, GREEN }
enum MonsterState { ROAM, ARTILLERY, NEST, COLLAPSED }
```


4. Feature Implementation Specs

- The Player (Prismatic Harpoon)
-- Must load a single elemental type at a time via overlapping Area3D pools.
-- Projectile strikes call take_damage(amount, damage_type) on the target.

- The Monster (Procedural Assembly)
-- The Core: Governed by an FSM. Traverses 3D space freely without standard NavMeshes via vector interpolation, acting as a flying or swinging body.
-- The Limbs: Driven by RayCast3D projections tracking surface collision vectors. Steps are calculated using a delta distance threshold relative to the moving core, snapping feet dynamically to walls, ceilings, and pillars.
--Weakpoints: All structural weak points are visually designated as organic eyes, responsive to specific matching ElementType damage indices.

- The Environment (Octagonal Arena)
-- Enclosed octagonal frame bounding a central circular summoning sigil.
-- Includes a vertical, shattered platform ring connected across interior structural pillars to enable high-tier player traversal.


