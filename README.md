# PrapsLib 2.0

Advanced GeckoLib-like animation engine for the **Luanti (Minetest) 5.17+** game engine.

PrapsLib completely replaces the standard Luanti bone animation limitations, allowing developers to create highly dynamic, multi-layered, and procedurally animated entities with full glTF 2.0 and server-authoritative multiplayer support.

## 🔥 Key Features

* **Multi-layered Animations & Blending:** Play multiple clips simultaneously (e.g., walking + attacking) with smooth crossfading.
* **State Machine:** Unity/Godot-style graph for automated state transitions based on speeds, ground detection, and custom triggers.
* **Inverse Kinematics (IK):** Built-in 2-bone analytic solver and FABRIK algorithm for procedural limb movement (e.g., spider legs dynamically adapting to voxel terrain).
* **Molang Expressions:** Run math expressions directly inside JSON animation files (`query.anim_time`, ternaries, custom queries).
* **Server-Authoritative Sync:** Full network synchronization with lag compensation and sequence tracking.

## 🚀 Quick Start

1. Add `prapslib` to your mod's `mod.conf` dependencies.
2. Export your model from **Blockbench as glTF (.glb)** with **Model Export Scale = 1.6**.
3. Register the entity in `on_activate`:

```lua
prapslib.register_entity(self.object)
prapslib.register_entity_data("mymod", "mymod:goblin")

self._machine = prapslib.sm.create_locomotion(self.object, {
    idle = "idle", walk = "walk", run = "run", jump = "jump"
})
```

4. Update parameters in `on_step`:

```lua
local vel = self.object:get_velocity()
local speed = math.sqrt(vel.x^2 + vel.z^2)
self._machine:set_float("speed", speed)
```

## 📜 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
