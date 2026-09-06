# School Escape - Architecture Documentation

## 1. Technology Stack

- **Engine**: Godot 4.7.2
- **Language**: GDScript only (no C#)
- **Renderer**: Forward+ (configured in project.godot)
- **Physics**: Jolt Physics (configured in project.godot)
- **Multiplayer**: Godot built-in multiplayer (Synchronized/Authoritative model)
- **Input**: Godot InputMap

---

## 2. Project Structure

Clean root-level layout. No nested `project/` directory.

```
game/
├── project.godot
├── docs/
│   ├── architecture.md
│   ├── game-design.md
│   └── development.md
├── scenes/
│   ├── player/
│   ├── characters/
│   ├── levels/
│   ├── interactables/
│   ├── props/
│   └── ui/
├── scripts/
│   ├── player/
│   ├── characters/
│   ├── interaction/
│   ├── ai/
│   ├── objectives/
│   ├── multiplayer/
│   └── core/
├── resources/
│   ├── characters/
│   ├── levels/
│   ├── items/
│   └── objectives/
├── assets/
│   ├── models/
│   ├── textures/
│   ├── materials/
│   ├── animations/
│   └── audio/
├── shaders/
└── tests/
```

*Structure is kept flat and understandable. Adjust only if a strong architectural reason exists.*

---

## 3. Player Architecture

**Player uses `CharacterBody3D`** (not `RigidBody3D`).

```
Player
├── CharacterBody3D
│   ├── CollisionShape3D
│   ├── Visuals (MeshInstance3D)
│   ├── CameraRig
│   │   └── Camera3D
│   ├── InteractionDetector
│   └── et cetera for gameplay components
```

**Physics props** (chairs, boxes, books, etc.) use `RigidBody3D`:

```
PhysicsProp
├── RigidBody3D
│   ├── CollisionShape3D
│   ├── Visuals/Mesh
│   └── Interaction-related nodes/components if needed
```

*Reason: Player is directly controlled by gameplay code, so `CharacterBody3D` handles movement, gravity, jumping, and collision naturally. Props use `RigidBody3D` for physical simulation.*

---

## 4. Physics Configuration

| Body Type | Godot Node | Usage |
|-----------|------------|-------|
| **Player** | `CharacterBody3D` | Directly controlled by gameplay code |
| **Physics props** | `RigidBody3D` | Physical objects, pushable, throwable |
| **Static geometry** | `StaticBody3D` | Level floor, walls, immovable objects |
| **Kinematic** | `CharacterBody3D` | Moving platforms, elevators, moving entities with direct scripted movement. Body type chosen on a per-object basis: CharacterBody3D for script-driven movement, StaticBody3D for immovable, RigidBody3D for physics-simulated props. |
| **Trigger zones** | `Area3D` | Detection zones (e.g., teacher sight, pickups) |

**Jolt Physics settings** (via project.godot):
- `3d/physics_engine="Jolt Physics"`
- Gravity: `9.81 m/s²` downward
- Broadphase: `SAHDBroadphase` (moderate scene complexity)

**Collision layers** (bitmask, logical groups):

| Layer | Bit | Purpose |
|-------|-----|---------|
| Player | 1 | Player character body |
| Environment | 2 | Static level geometry |
| Interactable | 4 | Doors, keys, items, props |
| NPC / Guard | 8 | Teacher, guard bodies |
| UI / Raycast | 16 | Optional raycast layers |

*Layer masks are assigned in project settings or per-node. Keep masks minimal and explicit.*

---

## 5. Input System

Use Godot's **InputMap**. Do NOT use UI action names (`ui_left`, `ui_right`, etc.) for gameplay movement.

**Custom gameplay actions**:

| Action Name | Purpose |
|-------------|---------|
| `move_forward` | Forward movement input |
| `move_backward` | Backward movement input |
| `move_left` | Left movement input |
| `move_right` | Right movement input |
| `jump` | Jump input |
| `interact` | Interact / use action |
| `hide` | Hide / crouch action |
| `swap_item` | Swap held item |

*Actions are defined in Project Settings → Input Map. Each action can have multiple keyboard/mouse/gamepad bindings. Input processing occurs in the player script per frame.*

---

## 6. Multiplayer Architecture

**Core principle: simple, maintainable 2-player co-op foundation** that can extend to 3–4 players later without rewriting.

### Host- authoritative Model

- **Host**: Authoritative game state. Drives physics simulation and validates all gameplay changes.
- **Clients**: Receive replicated state from the host. Run local rendering with input prediction that can be evaluated for necessity after playtesting.

### Player Spawning

- When a player joins, the host spawns a `Player` CharacterBody3D for that client.
- Player name/color distinguishes the two players.
- Spawn point selected from defined `SpawnLocation` nodes in the level.

### Input & State Replication

- Clients send relevant input (e.g., move, jump, interact) to the host.
- Host processes input, advances simulation, and replicates authoritative gameplay state (player positions, states, interactable status) to all connected peers.
- Clients render the replicated state. Local visual prediction may be applied for responsiveness, but can be turned off or adjusted based on playtesting results.

### RPC Usage

- Use Godot's `[rpc]` keyword for remote procedure calls.
- Functions that change gameplay state should be host-authoritative: the host is the single source of truth.
- Functions for UI, effects, or non-critical information may run on any peer.

### Synchronization (V1 — simple, reliable)

| What | Synchronized How |
|------|-------------------|
| Player position/rotation | Host-driven; replicated to all peers each physics tick |
| Player state (alive, hiding, carrying) | RPC from host; replicated state |
| Interactable state (door open/closed, key picked up) | RPC from host; or scene sync if using auto-replicated nodes |
| Objective progress | RPC from host |

### Joining / Leaving / Disconnecting

- **Joining**: Client connects → host sends initial authoritative state (player positions, level layout) → client spawns and follows replicated state.
- **Leaving**: Peer disconnects → other players continue; if host disconnects, game round ends or a new host is selected.
- **Disconnect**: Cleanup of owned nodes; state preservation for re-joining considered for later phases.

### Level State Consistency

- Level geometry is static; level description sent once at connection or loaded additively.
- Dynamic state (positions, states of interactables, objectives) is synchronized per RPC from the host.

### Future Expansion (3–4 Players)

- Architecture uses peer IDs to identify connected players.
- Host tracks connected peers; up to 4 players supported by design.
- No hardcoded "2-player only" logic; iterate over connected peers for systems that scale.

*Do NOT build the multiplayer implementation now. This document outlines the contract for future implementation. Keep networking logic in dedicated scripts under `scripts/multiplayer/`. Prediction and interpolation can be evaluated after initial playtesting shows whether they are necessary for comfortable gameplay.*

---

## 7. Interaction System

Reusable architecture for environmental interaction.

### Detection Flow (RayCast3D-based)

1. **Camera** emits a `RayCast3D` each frame (or per input tick).
2. If the ray intersects an `Interactable` → `RayCast3D.is_colliding()` is true and the collider is an interactable.
3. The interaction detector calculates distance and determines if the player is within range.
4. UI subscribes → shows context prompt (e.g., "E to Open Door").
5. Player presses **interact** → player script calls `interactable.interact(player)`.
6. Interactable performs its action (door opens, key picked up, lever pulled, etc.).

*Area3D may still be used later for trigger/proximity systems (e.g., "player is near a door"), but it should not be the primary interaction detector. The RayCast3D approach provides deterministic, frame-accurate interaction triggering.*

### Interaction Contract

Each interactable inherits from a base script or follows the same pattern:

```gdscript
# Base interactable pattern (attached as a script to a Node3D)
func interact(player):
    """Called when player interacts. Override in each subclass."""
    pass

func get_interact_range() -> float:
    """Range within which the player can interact (for fallback/proximity checks)."""
    pass

func get_interact_prompt() -> String:
    """Prompt text shown in UI."""
    pass
```

### Example Interactables

| Interactable | Description |
|--------------|-------------|
| `Door` | Opens/closes when interacted. May require a key. |
| `Window` | Can be climbed through or broken. |
| `KeyItem` | Pickupable. Adds to player inventory. |
| `Button` | Toggles state (opens door, triggers event). |
| `Lever` | Toggles state, may have animation. |
| `Box` | Can be pushed, climbed on, used as step. |
| `Pickup` | Collectible (health, item, etc.). |

*Keep components lightweight. Do NOT create an artificial ECS or component framework. Use normal Godot Nodes + scripts + signals.*

---

## 8. Level Architecture

Levels are **modular scenes**, not one giant scene.

### Level Structure

Each level scene contains:

```
Level_Classroom
├── StaticBody3D / CollisionShape3D (floor/walls)
│   └── Visuals
├── PlayerSpawnPoints (Marker3D nodes, named "SpawnP1", "SpawnP2")
├── Interactables (doors, windows, buttons, keys, etc.)
│   ├── Door
│   ├── KeyItem
│   └── ...
├:: Area3D zones (teacher sight, trigger volumes)
├:: NPC / Guard bodies
└:: Lighting, environment, audio
```

### Reusability

- **Room** scenes can be instanced as building blocks.
- **Template** levels (classroom, hallway, office) are prefabs.
- Each level is independent; multiplayer sync runs on a per-level basis.

### Future Levels

- New levels are added as new scene files under `scenes/levels/`.
- No modification to core systems required to add a new level.

---

## 9. Game Flow

Simple, practical flow from boot to gameplay:

1. **Bootstrap** → `Main.tscn` loads as root scene (initializes autoloads, singletons if needed).
2. **Main Menu / Lobby** → Player hosts or joins a session, selects settings.
3. **Multiplayer session** → Connected peers; host authority active.
4. **Level** → Host loads level scene; peers receive state; gameplay begins.
5. **Objectives / Gameplay** → Players cooperate to escape, solve puzzles, avoid teachers.
6. **Level completion** → Trigger → next level loads or results screen.
7. **Next level / Results** → Progression flow.

*Keep implementation lightweight. Do not build systems that are not yet required.*

---

## 10. Core Scripts Organization

Scripts grouped by feature, flat within `scripts/`:

```
scripts/
├── player/
│   ├── player.gd          # Movement, camera, interaction input
│   └── player_state.gd    # Local state (alive, carrying, etc.)
├── characters/
│   ├── npc.gd             # AI behavior for teachers/guards
│   └── guard.gd           #
├── interaction/
│   ├── interactable.gd    # Base interactable contract
│   ├── door.gd            # Door implementation
│   ├── key_item.gd        # Pickup implementation
│   └── button.gd          # Button implementation
├── multiplayer/
│   ├── network_manager.gd # Host/client setup
│   └── state_replication.gd  # Simple state replication (introduced at multiplayer milestone)
├── objectives/
│   ├── objective_manager.gd
│   └── escape_objective.gd
└── core/
    ├── game_manager.gd    # Global game state
    └── input_map.gd       # Input action definitions (mappings for InputMap)
```

*No unnecessary abstraction layers. Each script solves a specific, real problem. Add scripts only when a real requirement appears — networking scripts are introduced only when the multiplayer milestone is implemented.*

---

## 11. Collision Layer Organization (Summary)

| Layer | Bit | Name | Purpose |
|-------|-----|------|---------|
| 1 | 1 | Player | Player CharacterBody3D |
| 2 | 2 | Environment | StaticBody3D level geometry |
| 4 | 4 | Interactable | Doors, keys, items, physics props |
| 8 | 8 | NPC / Guard | Teacher and guard bodies |
| 16 | 16 | UI / Raycast | Optional raycasts, UI collision |

*Masks are assigned per-Node in the editor. Typical player mask: `1 | 2 | 4 | 8` (collides with environment, interactables, NPCs). Adjust as needed per game design.*

---

## 12. Initial Development Milestones

Ordered implementation sequence. Do not skip or reorder arbitrarily.

### Milestone 1: Player Prototype
- CharacterBody3D player scene
- WASD / gamepad movement (local, no physics networking yet)
- Mouse camera rotation
- Gravity and jump
- Collision with environment
- **Goal**: Walk around a blank room

### Milestone 2: Small Test Room
- Floor, walls, simple geometry
- StaticBody3D level enclosure
- Basic physics props (boxes) using RigidBody3D
- **Goal**: Player can navigate a room and push boxes

### Milestone 3: Interaction System
- Base `Interactable` script contract
- First interactable (e.g., simple Door)
- Interaction detector in player
- UI prompt system
- **Goal**: Player can open/close first door

### Milestone 4: Physics / Environment Interaction
- Push/pull physics props
- Box stacking / stepping
- Object throwing (if applicable)
- **Goal**: Meaningful physics-based gameplay

### Milestone 5: Basic 2-Player Multiplayer Foundation
- Host / client setup (Godot multiplayer API)
- Player spawning with authority
- Input/state replication using simple host-authoritative networking
- **Goal**: Two players can both move in a level, host is authoritative

### Milestone 6: Interaction + Multiplayer
- Interactables synced between peers
- Door opens on both screens when host interacts
- **Goal**: First co-op interaction moment

### Milestone 7: Guards / AI Basic
- Teacher patrol logic
- Line-of-sight detection
- Hiding mechanics
- **Goal**: Avoidance gameplay loop

### Milestone 8: Objectives & Progression
- Escape objective tracking
- Level completion trigger
- Next level flow
- **Goal**: End-to-end playable slice

*After milestone 8, iterate toward first full vertical slice, then expand levels, polish, and expand player count to 3–4.*

---

## 13. What Is NOT Implemented Yet (Intentionally)

- No ECS framework
- No custom physics wrapper beyond Godot/Jolt config
- No giant InputManager singleton (use InputMap + per-player scripts)
- No giant dependency-injection framework
- No over-engineered networking (keep to host/basic RPC for V1)
- No generic "useful later" components (build only what is needed)
- No preset UI framework (use Godot CanvasLayer nodes as needed)
- No shader graph or post-processing beyond Forward+ baseline

---

## Naming Conventions (useful defaults)

- **Scenes**: PascalCase, ending in `.tscn` (e.g., `Player.tscn`, `Door.tscn`)
- **Scripts**: snake_case, ending in `.gd` (e.g., `player.gd`, `interactable.gd`)
- **Resources**: PascalCase, ending in `.tres` if used
- **Node names**: camelCase or descriptive lower_case (consistent within each scene)
- **Input actions**: snake_case lowercase (e.g., `move_forward`, `interact`)
- **Signals**: lowercase with underscore separator (e.g., `interactable_entered`)
- **Functions/Variables**: lowercase with underscore if multiword, or camelCase (pick one and stay consistent)
