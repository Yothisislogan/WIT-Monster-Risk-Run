# WIT Monster: Risk Run

A mobile-first, side-scrolling action roguelite starring the We Insure Things Monster.
Built with **Godot 4.x** (GDScript), landscape orientation, touch-first controls with
full controller support.

This repository currently contains the **MVP prototype** described in
[docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) (see sections 26, 28, and 32), plus the first
Phase 2/3 systems:

- WIT Monster movement: run, variable-height jump, **double jump**, dash,
  wall cling, wall jump, **ground pound**
- Mobile-friendly input buffering (jump buffer, coyote time, dash buffer, landing attack buffer)
- Base weapon: tap-to-shoot projectile, hold-to-charge piercing shot (pooled projectiles)
- **Stomping**: land on an enemy to damage it and bounce; hold jump for a
  higher bounce, and a stomp refunds your double jump so you can chain
- **Adjuster's Streak**: chained takedowns multiply Premiums, and a single
  hit ends the streak
- Monster Munch: weakened enemies (tinted green) can be consumed to restore
  Coverage and charge the boss ability meter
- Flame Draft boss ability: spends ability energy to fire a piercing blast
  that ignites enemies (burn damage over time)
- Coverage meter and boss ability meter HUD
- One hazard (Heat Vent) with a telegraphed warn-then-burst cycle
- Three handcrafted room modules shuffled into a randomized sequence each run,
  each with an optional double-jump-only treasure route
- Bounce pads (ground pound them for a super launch), breakable crates,
  Premium coin pickups with magnet collection, and moving platforms
- Two enemy types: Toaster Trooper (patrol) and Ember Imp (flying, telegraphed
  dive that can be cancelled by shooting it)
- Falling in a pit costs Coverage and drops you back on solid ground instead
  of ending the run
- One temporary upgrade pickup (Umbrella Coverage — blocks one hit)
- Save and resume after every completed room (versioned JSON save; the shuffled
  room sequence is saved so resuming never re-rolls a room)
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
| Munch   | E                 | Right shoulder    |
| Pound   | Down + Jump (in air) | Down + A       |
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

## Movement budget (level design contract)

Levels are built against these numbers from `scripts/player/player.gd`. If you
retune the jump, re-run `python3 tools/check_reachability.py` before shipping rooms —
it parses every room scene and BFS's the platform graph to prove the exit is
reachable from the spawn.

| Quantity | Value |
| --- | --- |
| Single jump rise | 136px |
| Double jump rise | 249px |
| Flat gap, single jump | ~240px |
| Flat gap, double jump | ~400px |
| Dash distance | ~125px |

Required paths use 86-110px rises and <=220px gaps. Optional treasure routes
are allowed to need the double jump.

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
