# WIT Monster: Risk Run

A mobile-first, side-scrolling action roguelite starring the We Insure Things Monster.
Built with **Godot 4.x** (GDScript), landscape orientation, touch-first controls with
full controller support.

This repository currently contains the **Phase 1 / MVP movement prototype** described in
[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) (see sections 26, 28, and 32):

- WIT Monster movement: run, variable-height jump, dash, wall cling, wall jump
- Mobile-friendly input buffering (jump buffer, coyote time, dash buffer, landing attack buffer)
- Base weapon: tap-to-shoot projectile, hold-to-charge piercing shot (pooled projectiles)
- Coverage meter (health) HUD
- One enemy (Toaster Trooper) and one hazard (Heat Vent)
- Room-to-room transition with two handcrafted test rooms
- One temporary upgrade pickup (Umbrella Coverage — blocks one hit)
- Save and resume after every completed room (versioned JSON save)
- Touch controls (floating virtual stick + action buttons) and controller/keyboard
  through the same input action layer
- Auto-pause on focus loss / app backgrounding

## Getting started

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build, not .NET).
2. Open the project: `godot -e --path .` or import `project.godot` from the Godot
   project manager.
3. Run the main scene (`scenes/main.tscn`) with F5, or export to an Android/iOS device
   to test touch controls.

### Default keyboard/controller mapping (development)

| Action  | Keyboard          | Controller        |
| ------- | ----------------- | ----------------- |
| Move    | A/D or arrows     | Left stick / dpad |
| Jump    | Space / W         | A (bottom)        |
| Attack  | J (hold = charge) | X (left)          |
| Dash    | K / Shift         | B (right)         |
| Special | L                 | Y (top)           |
| Pause   | Esc               | Start             |

On touch devices the virtual controls appear automatically; on desktop they stay hidden.

## Project layout

```
docs/               Design documents (GAME_DESIGN.md is the source of truth)
scenes/             Godot scenes (player, enemies, hazards, rooms, ui)
scripts/
  autoload/         Singletons: Events (signal bus), GameManager, SaveManager
  player/           Player controller, camera rig
  weapons/          Projectiles and object pool
  enemies/          Enemy base class + concrete enemies
  hazards/          Environmental hazards
  rooms/            Room base, pickups
  ui/               HUD, touch controls
assets/             Art and audio (placeholders during prototyping)
```

## Design pillars (do not drift)

1. Mobile-first action-platforming
2. Build-your-own Policy Card combinations
3. Risk-versus-reward deductible and exclusion choices
4. Interactive disasters with humorous claim reports

The primary development priority: **make moving, jumping, dashing, and attacking with
the WIT Monster feel excellent on a phone before building the rest of the game.**

## Development rules

- Feature branches + pull requests; code review required for core systems
- Gameplay logic stays separate from presentation
- No hardcoded upgrade values — use data-driven resources
- Tune all movement/buffer constants on a physical phone before adding content
