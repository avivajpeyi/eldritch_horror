# eldritch_horror

**Game Design Document & Memory File: Project Colossus Slime**

---

## 1. Game Concept Overview

* **Genre:** Action / Boss-Rush FPS / Physics Puzzle
* **Core Premise:** The player faces off against a singular, massive, procedurally animated eldritch slime monster in an ancient ritual chamber. The fight relies on information gathering, positioning, and color-coded environmental mechanics rather than brute-force shooting.

---

## 2. The Octagonal Ritual Arena

* **Layout:** An octagonal chamber featuring a massive glowing **Summoning Sigil** carved into the floor at the exact center.
* **Verticality:** Monolithic black brutalist pillars stand at each of the octagon's vertices, connected halfway up by a broken, shattered stone catwalk ring. This layout gives the player high ground and provides the boss with a geometric framework to traverse.
* **Environmental Aesthetics:** Cosmic horror/occult theme. Dark, wet masonry etched with shifting runes.
* **The Resource Pools:** Three distinct elemental fonts sit at fixed locations around the arena perimeter:
* **Red Pool:** A sacrificial brazier of hellish fire.
* **Blue Pool:** A font of dark, churning void water crackling with localized lightning.
* **Green Pool:** A bubbling cistern of corrosive, ancient ichor.



---

## 3. The Player & Combat Mechanics

* **Character Controller:** A highly responsive 3D character controller utilizing mobility tools like dashes or a grappling hook to navigate the arena's vertical rings and dodge sweeping attacks.
* **The Weapon (Prismatic Harpoon):** * Fires unlimited baseline kinetic spikes, highly effective for clearing small minion swarms but useless against the boss's armored areas.
* To damage the boss or its limbs, the player must run through one of the three colored elemental pools to "charge" their harpoon with **Red**, **Blue**, or **Green** energy. The gun can only hold one charged shot at a time, forcing constant movement across the map.


* **The Visual Rule:** Every interactive weak point is a giant, blinking, organic **Eye**. If it has a color glow, the player must match their harpoon element to that color to damage it.

---

## 4. The Colossus Boss Design & Engineering

### Aesthetic

The monster is an apex cosmic entity composed of a central core of jagged **obsidian shards** suspended in a vortex of black, glistening tar. Its legs are coiling **shadow-tendrils** that bleed into the stone architecture upon contact, opening up weeping eyes along the pillars where they anchor.

### The Technical Movement Trick

The monster's movement decouples visual animation from true spatial navigation:

1. **The Core** acts as an invisible floating drone (`CharacterBody3D` or `RigidBody3D`) that hovers dynamically through the room's 3D coordinate space based on states, ignoring traditional 2D NavMeshes.
2. **The Legs** are procedural, rule-based systems. `RayCast3D` nodes shoot outward from the core to find walls, pillars, or floors.
3. **The Step Rule:** If the core moves too far away from an existing leg's anchor point, that leg detaches, casts forward in the direction of travel, snaps to a new surface intersection point, and smoothly interpolates (Lerps) its mesh to that new position. This creates the illusion of organic climbing.

---

## 5. Boss State Machine & Gameplay Loop

```
               ┌──────────────────────┐
               │   1. Roam & Stalk    │
               │  (High mobility,     │
               │   terrain scaling)   │
               └──────────┬───────────┘
                          │
            Player gets   │   Shield active /
            close / Hurt  │   Tension high
                          ▼
 ┌────────────────────────┴────────────────────────┐
 │                                                 │
 ▼                                                 ▼
┌──────────────────────┐                  ┌──────────────────────┐
│  2. Artillery Anchor │                  │  3. The Nest (Hide)  │
│ (Fixed point, heavy  │                  │ (Ceiling vanish,     │
│  ranged bombardment) │                  │  eyeball minions)    │
└──────────┬───────────┘                  └──────────┬───────────┘
           │                                         │
           └──────────────────┬──────────────────────┘
                              │ All legs severed /
                              │ Core compromised
                              ▼
                   ┌──────────────────────┐
                   │   4. The Collapse    │
                   │ (Grounded, vulnerable│
                   │  DPS strike phase)   │
                   └──────────────────────┘

```

### State Details

* **Stage 1: Roam & Stalk:** The core aggressively hovers along the walls and pillars, lashing out with tendrils if the player approaches. The leg anchors glow specific colors; players must run to the corresponding pool, match their ammo, and shoot the leg eyes to weaken its hold. When legs are unanchored, they whip through the air using a sine-wave function, and the core stretches or squashes dynamically based on its velocity vector.
* **Stage 2: Artillery Anchor:** The monster bridges itself tightly between pillars, locks in place, and builds a **Blue Slime Barrier** over its core. It hurls heavy debris and acid at the player. The loop requires the player to fetch Blue ammo to pop the shield, then sprint to the Red pool to shoot the exposed core.
* **Stage 3: The Nest:** The core retreats completely into the ceiling shadows and drops organic sacs that hatch into **miniature, single-eyeball slime spiders**. The player must harvest **Green Ammo** to cause chain-reaction explosions across the swarm, inflicting psychic feedback damage that forces the boss back down.
* **Stage 4: The Collapse:** Once structural integrity fails (e.g., threshold of legs severed), gravity is re-applied to the core, crashing it violently into the floor. The monster lies paralyzed for 8–10 seconds, exposing its central nucleus for maximum, unmitigated player DPS before resetting back to Stage 1.




## File structure


src/
└── entities/
    ├── player/
    ├── minions/
    └── monster/                   # Updated from 'colossus'
        ├── monster_core.tscn      # The main flying body
        ├── monster_core.gd
        ├── components/
        │   ├── leg_anchor.gd
        │   └── slime_tendril.gd
        └── states/
            ├── state_roam.gd
            └── state_artillery.gd




