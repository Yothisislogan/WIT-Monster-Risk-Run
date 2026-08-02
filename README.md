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
- **Boss abilities and combinations**: Flame Draft (a piercing blast that
  ignites) and Impact Dash (an armoured charge), absorbed from bosses and kept
  permanently. Hold both and MELTDOWN CHARGE makes the dash ignite
- **Aiming**: hold up, or down in mid-air, to angle a shot; otherwise a capped
  assist leans it toward the nearest peril inside a forward cone
- Coverage meter and boss ability meter HUD
- One hazard (Heat Vent) with a telegraphed warn-then-burst cycle
- **The Claim Map**: a branching run of three acts and 18 sites, generated from
  a seed and saved with the run. Route choice is risk selection — Peril Zones,
  High-Risk Zones, the Adjuster's Office, Claim Events, Senior Adjusters and a
  guaranteed Salvage Yard before each act's Catastrophe
- Five handcrafted room modules dealt per act without replacement, each with an
  optional double-jump-only treasure route
- Bounce pads (ground pound them for a super launch), breakable crates,
  Premium coin pickups with magnet collection, and moving platforms
- Two enemy types: Toaster Trooper (patrol) and Ember Imp (flying, telegraphed
  dive that can be cancelled by shooting it)
- Falling in a pit costs Coverage and drops you back on solid ground instead
  of ending the run
- One temporary upgrade pickup (Umbrella Coverage — blocks one hit)
- Save and resume after every completed site (versioned JSON save; the map is
  rebuilt from its seed so a save from an older build still opens)
- **Gesture touch controls**: no on-screen buttons at all. The left of the
  screen is a floating stick that only draws while a thumb is on it; the right
  is a gesture surface — tap to jump, swipe to dash or unleash, hold to charge,
  two fingers to pause
- Auto-pause on focus loss / app backgrounding
- **8-bit chiptune soundtrack**: a distinct theme per Risk Zone plus a victory
  cue, crossfaded between rooms
- **24 synthesised sound effects** with a pooled player, retrigger guards and
  rising-pitch chains for coin runs and stomp streaks
- **Policy Cards**: a data-driven catalogue of cards and Exclusions, choose one
  of three after every room
- **Risk Meter**: rises with reckless choices, scales enemies and payouts, and
  spawns elite perils
- **Deductibles**: Low / Standard / High chosen at run start
- **Two bosses**, deliberately opposite fights: the Inferno Adjuster is a
  ground bruiser you punish by stomping a stunned body; the Actuary never
  lands, and its beam, falling liabilities and outward rings all ask where you
  are in the air
- **WIT Headquarters**: Case Files earned every run, won or lost, spent on
  permanent upgrades — most of which unlock cards and Exclusions into the pool
  rather than raising a number. Twelve named Case Files to earn
- Title screen, settings covering the §22 accessibility options, one-time
  contextual hints, a pause inventory, and save-and-quit

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
| Swap ability | Tab          | Left shoulder     |

Every pause overlay, the card offer, the Claim Map and the Headquarters screen
hand focus to a control, so the whole game is playable on a pad.

### Touch gestures

There are no on-screen buttons. Buttons cost the thing a phone has least of,
and on a landscape platformer they sit exactly where the action is.

| Gesture (right of screen) | Action |
| --- | --- |
| Tap | Jump — tap again in mid-air to double jump |
| Swipe ← / → | Dash that way, regardless of facing |
| Swipe ↑ | Equipped boss ability |
| Swipe ↓ | Ground pound in the air; Monster Munch on the ground |
| Hold | Charge a shot, released when you lift |
| Two-finger tap | Pause |

The left of the screen is a floating movement stick that anchors wherever your
thumb lands and only draws while held. Tapping the ability readout in the HUD
swaps which ability SPECIAL fires. Auto-fire is the default on touch, because a
hold means "charge" there and the basic weapon needs no gesture of its own.

On desktop and controller the touch layer stays hidden entirely.

## Project layout

```
docs/               Design documents (GAME_DESIGN.md is the source of truth)
tools/              Generators and static checkers (see below)
scenes/             Godot scenes (player, enemies, hazards, rooms, ui)
scripts/
  autoload/         Singletons: Events (signal bus), GameManager, SaveManager
  player/           Player controller, camera rig
  weapons/          Projectiles and object pool
  enemies/          Enemy base class + concrete enemies
  hazards/          Environmental hazards
  rooms/            Room base, pickups
  map/              Claim Map generation and traversal
  sites/            Shop, rest and Claim Event content
  meta/             WIT Headquarters and Case Files
  ui/               HUD, touch controls, map screen, site panel
assets/             Art and audio (placeholders during prototyping)
```

## Music

The soundtrack is synthesised from scratch — no sample libraries. `tools/generate_music.py`
implements an NES-style chip: two pulse channels (variable duty), a quantised
triangle bass and a 15-bit LFSR noise channel for drums. Each Risk Zone gets its
own key, tempo and character:

| Track | Level | Key | BPM | Character |
| --- | --- | --- | --- | --- |
| `blaze_borough` | 1. Blaze Borough | A minor | 150 | Heroic, driving |
| `crashway_5000` | 2. Crashway 5000 | E minor | 168 | Fastest, relentless |
| `storm_surge_harbor` | 3. Storm Surge Harbor | D minor | 132 | Rolling, moody |
| `cyber_city` | 4. Cyber City | B minor | 160 | Staccato, glitchy |
| `liability_land` | 5. Liability Land | C major | 145 | Bouncy, carnival |
| `boss_theme` | boss encounters | — | 172 | Urgent |
| `claim_victory` | end-of-run cue | C major | 150 | Short fanfare |
| `claim_denied` | defeat cue | A minor | 104 | Falling, slower |

Output is 8-bit 22050 Hz mono (~2.8 MB total) — genuinely 8-bit samples, which
suits the style and halves the web download. Rendering is deterministic, so
regenerating produces byte-identical files:

```
python3 tools/generate_music.py
```

To change a theme, edit its entry in `TRACKS` (melodies use a compact
`Note:sixteenths` notation) and re-run. Tracks loop seamlessly: a 4 ms fade at
each end lands the loop point on silence so the seam does not click.

## Checkers

There is no Godot binary in this environment and none in CI beyond the export
step, so nothing here can be playtested or even compiled locally. These run
instead, on every push, and every one of them was verified by deliberately
reintroducing the bug it is meant to catch:

```
python3 tools/check_references.py    # autoload/class members actually exist
python3 tools/check_scenes.py        # .tscn structure, $Node and %Unique paths, connections
python3 tools/check_signals.py       # every Events emit and handler matches its declaration
python3 tools/check_inputs.py        # every input action referenced is declared
python3 tools/check_gestures.py      # gesture thresholds cannot overlap
python3 tools/check_movement.py      # the air-jump budget cannot be exceeded
python3 tools/check_aim.py           # aim assist stays mild; the flyer is hittable
python3 tools/check_map.py           # 4000 Claim Maps: connected, no dead ends, paced
python3 tools/check_sites.py         # every site option is complete and does something
python3 tools/check_meta.py          # Headquarters pays out without power creep
python3 tools/check_reachability.py  # every room: spawn -> exit is traversable
python3 tools/check_pickups.py       # coin physics regression
python3 tools/check_economy.py       # Monte Carlo of the Risk/reward economy
```

The pattern is that each one models a rule the game is meant to obey and
asserts a property of it, rather than restating the code. `check_map.py`
generates four thousand maps because a seed that produces a dead end makes a
run unfinishable, which is the worst possible bug to find by playing.
`check_economy.py` simulates full runs across every deductible and two skill
profiles; when the run length tripled it was what showed the death rate going
from 18% to 99%.

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
