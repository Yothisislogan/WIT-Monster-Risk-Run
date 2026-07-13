# WIT Monster: Risk Run

## Mobile-First Game Development Outline

## 1. Project Summary

**WIT Monster: Risk Run** is a mobile-first, side-scrolling action roguelite featuring the We Insure Things Monster.

The game combines:

* Fast platforming and ranged combat
* Roguelite runs with randomized rooms and upgrades
* Boss abilities that change movement and combat
* Insurance-inspired systems presented through humor
* Short sessions designed for mobile play
* Optional deeper progression for repeat players

The game should be inspired by the responsiveness and stage structure of classic action-platformers, but it must have its own visual identity, control system, mechanics, level design, and progression.

The first release will include five primary levels, five bosses, one final stage, permanent progression, randomized room layouts, touch controls, and controller support.

---

# 2. Design Goals

## Primary goals

1. Make the WIT Monster immediately fun to control.
2. Build around mobile screens and touch input first.
3. Keep combat readable on small displays.
4. Support short play sessions without weakening longer runs.
5. Give every run meaningful choices.
6. Create humor through gameplay, animation, enemies, and claim reports.
7. Make insurance themes entertaining rather than educational or corporate.
8. Allow the game to expand with new levels, bosses, characters, and policy cards.

## Player experience

The player should feel:

* Fast
* Powerful
* Slightly reckless
* Rewarded for experimentation
* Tempted to take unnecessary risks
* Curious about new upgrades and combinations
* Motivated to attempt another run after losing

---

# 3. Target Platforms

## Initial platforms

* iOS
* Android

## Secondary support

* Tablets
* Bluetooth controllers
* Desktop development builds
* Potential future PC release

## Screen orientation

Use **landscape orientation only** during gameplay.

Menus may remain landscape for consistency.

## Target devices

The initial release should run acceptably on mid-range mobile devices released within the previous five years.

## Performance targets

* Target 60 frames per second
* Minimum acceptable performance: stable 30 frames per second
* Native resolution scaling
* Adjustable effects quality
* Fast loading between rooms
* Low battery and thermal impact where possible

---

# 4. Recommended Technology

## Preferred engine

**Godot 4.x**

Reasons:

* Strong 2D support
* Good mobile export workflow
* Open source
* No engine royalty
* Lightweight runtime
* Suitable for custom touch controls
* Good scene and node structure for modular rooms
* Easier long-term control for an independent project

## Acceptable alternative

**Unity**

Use Unity only if the development team has materially more experience with it or requires a specific third-party tool that Godot cannot support.

## Suggested technical stack

* Engine: Godot 4.x
* Language: GDScript or C#
* Save data: Local JSON or Godot resource files
* Cloud saves: Apple Game Center and Google Play Games in a later phase
* Analytics: Privacy-conscious event tracking
* Crash reporting: Platform-native or lightweight third-party reporting
* Version control: GitHub
* Continuous builds: GitHub Actions or engine-specific build pipeline

---

# 5. Core Game Loop

Each run follows this structure:

1. Player selects a starting policy.
2. Player chooses one of the available Risk Zones.
3. Player completes randomized combat and platforming rooms.
4. Player collects currency, Policy Cards, healing, and temporary upgrades.
5. Player encounters shops, challenges, rescue rooms, and claim events.
6. Player defeats the level boss.
7. Player absorbs the boss ability.
8. Player chooses the next Risk Zone.
9. Defeating all five bosses unlocks the final stage.
10. The player either defeats the final boss or loses the run.
11. The run ends with a humorous claim report.
12. The player spends permanent currency at WIT Headquarters.
13. The next run begins with additional options unlocked.

## Intended run length

* Early failed run: 5–15 minutes
* Average run: 20–35 minutes
* Complete run: 35–50 minutes
* Individual room: 20 seconds to 2 minutes
* Boss fight: 2–4 minutes

The game should save after every completed room so a mobile player can close the app and resume later.

---

# 6. Touch Control Design

Touch controls are a core game system, not an adaptation added after development.

## Default control layout

### Left side

A floating virtual movement pad.

Functions:

* Move left
* Move right
* Crouch or drop through platforms
* Optional upward input for ladders or interaction

The movement control should support two modes:

1. Floating thumbstick
2. Fixed left and right directional buttons

Players may choose their preferred mode.

### Right side

Primary action buttons:

* Attack
* Jump
* Dash
* Boss ability or special attack

Optional secondary button:

* Monster Munch
* Interact
* Weapon switch

## Recommended default arrangement

* Large jump button in the lower-right area
* Attack button slightly above and to the left of jump
* Dash button closer to the center of the screen
* Special ability button above attack
* Weapon-switch gesture or smaller button near the special ability

## Touch interaction requirements

* Buttons must be repositionable
* Button size must be adjustable
* Button opacity must be adjustable
* Haptic feedback must be optional
* Inputs must support multiple simultaneous touches
* Jump and attack must register together
* Directional movement must continue while other buttons are pressed
* Touch targets must remain large enough for smaller phones
* Critical action buttons must not sit near system gesture zones

## Input buffering

Implement generous mobile-friendly input buffering.

Suggested values:

* Jump input buffer: approximately 120–180 milliseconds
* Coyote time: approximately 100–150 milliseconds
* Dash buffer: approximately 100 milliseconds
* Attack buffering near landing: approximately 100 milliseconds

These values should be tuned through testing.

## Gesture controls

Gestures should supplement buttons, not replace them.

Possible gestures:

* Swipe up on weapon icon to change boss ability
* Hold attack to charge
* Hold jump for higher jump
* Swipe down on movement area to drop through a platform
* Double-tap direction for an optional dash setting

Do not require complex gestures during intense combat.

## Auto-aim

Mobile combat should use limited aim assistance.

Recommended system:

* Default projectile direction follows player facing
* Mild vertical correction toward nearby enemies
* Optional stronger aim assist in accessibility settings
* Lock-on should not remove player control
* Bosses should have generous target zones

## Controller support

Bluetooth and wired controller support should be included during development, even though touch is the primary input method.

---

# 7. Player Character

## WIT Monster base abilities

The WIT Monster begins with:

* Run
* Jump
* Variable jump height
* Ranged attack
* Dash
* Wall cling
* Wall jump
* Belly bounce or ground pound
* Monster Munch
* One equipped boss ability

## Movement requirements

Movement must feel responsive before full content production begins.

Prioritize:

* Quick acceleration
* Predictable air control
* Minimal landing delay
* Short but powerful dash
* Forgiving ledge detection
* Clear wall-cling behavior
* Strong visual and audio feedback

## Base weapon

The base weapon should be simple and reliable.

Suggested behavior:

* Tap attack for a quick projectile
* Hold attack to charge
* Release for a stronger shot
* Charged shot penetrates light enemies
* Charging should not prevent running or jumping

## Monster Munch

The Monster can consume weakened enemies or special projectiles.

Possible results:

* Restore a small amount of Coverage
* Gain temporary armor
* Gain elemental damage
* Gain a short hover
* Reveal hidden objects
* Charge the boss ability meter

Only one temporary Munch trait may be active at a time.

## Coverage meter

Health is represented as **Coverage**.

When Coverage reaches zero, the run ends unless the player has a revival effect.

Coverage UI must be:

* Large
* Easy to read
* Visible without covering gameplay
* Colorblind-safe
* Supported by sound and animation cues

---

# 8. Deductible System

At the start of each run, the player selects a deductible.

## Low Deductible

* More starting Coverage
* More healing
* Easier enemy scaling
* Lower permanent rewards

## Standard Deductible

* Balanced difficulty
* Standard rewards

## High Deductible

* Reduced starting Coverage
* Less healing
* Stronger enemies
* Better upgrade quality
* Increased permanent currency
* Access to certain high-risk rooms

The deductible creates a clear difficulty selection without using traditional labels such as Easy, Normal, and Hard.

---

# 9. Policy Card System

Policy Cards are the primary temporary upgrades during a run.

## Card categories

* Attack
* Defense
* Movement
* Boss ability
* Monster Munch
* Companion
* Economy
* Catastrophe
* Utility

## Example cards

### Bundled Up

Gain increased defense while two or more boss abilities have been collected.

### Replacement Cost

Revive once with partial Coverage.

### Claims-Free Discount

Complete several rooms without taking damage to increase attack power.

### Multi-Policy Discount

Each different weapon type increases overall damage.

### Roadside Assistance

Periodically summon a tow truck attack.

### Business Interruption

Time briefly slows after taking major damage.

### Umbrella Coverage

Block one large hit after a cooldown.

## Card selection

After major rooms, the player chooses one of three Policy Cards.

Mobile selection requirements:

* Cards must be readable without scrolling
* Important effects must fit in one or two short sentences
* Icons must clearly communicate category
* Long-press or information button may display details
* Players must be able to compare a new card with current cards

## Policy capacity

The player has a limited number of active Policy Card slots.

Possible initial capacity:

* Six standard card slots
* Two endorsement slots
* One exclusion slot

Capacity can be expanded through permanent progression.

---

# 10. Exclusion System

Exclusions are powerful upgrades with meaningful drawbacks.

Examples:

### Rocket Boots

Gain an additional air dash, but electrical damage increases.

### Aggressive Adjusting

Boss abilities deal more damage but consume more energy.

### Cheap Premium

Receive a random positive effect and a random negative effect at the start of each level.

### Actual Cash Value

Earn additional currency, but healing restores less Coverage.

Exclusions should be optional and visually distinct from normal cards.

The downside must always be disclosed before selection, though the game may humorously place part of the explanation in fine print.

---

# 11. Risk Meter

The Risk Meter increases when the player:

* Selects dangerous routes
* Accepts exclusions
* Completes optional challenges
* Skips safety devices
* Opens suspicious containers
* Chains rooms without healing
* Chooses high-risk claim responses

Higher risk creates:

* More elite enemies
* Increased enemy speed
* Additional environmental hazards
* Better rewards
* Rare Policy Cards
* Alternate boss attacks
* Secret rooms
* Special endings

The Risk Meter should be visible but not visually dominant.

---

# 12. Initial Five Levels

Each level should use modular rooms assembled in a randomized order.

A run should not procedurally generate individual platforms at runtime. Developers should build handcrafted room modules and randomize their sequence, enemy placement, hazards, rewards, and modifiers.

## Level 1: Blaze Borough

Theme:

* Residential fires
* Construction fires
* Kitchens
* Rooftops
* Sewers
* Sprinkler systems

Primary hazards:

* Spreading flames
* Smoke
* Collapsing platforms
* Explosive tanks
* Heat vents

Boss:

**Inferno Adjuster**

Boss ability:

**Flame Draft**

Shoots a fire blast that ignites enemies and melts specific barriers.

## Level 2: Crashway 5000

Theme:

* Futuristic highways
* Moving vehicles
* Tunnels
* Junkyards
* Repair shops

Primary hazards:

* Traffic
* Oil slicks
* Falling signs
* Moving platforms
* Vehicle collisions

Boss:

**Collision King**

Boss ability:

**Impact Dash**

A high-damage dash that breaks cracked walls and armor.

## Level 3: Storm Surge Harbor

Theme:

* Flooded streets
* Rooftops
* Shipping docks
* Storm drains
* Ships

Primary hazards:

* Rising water
* Wind
* Lightning
* Floating debris
* Unstable platforms

Boss:

**Catastrophe Kraken**

Boss ability:

**Surge Shield**

Creates a rotating water shield that blocks projectiles and damages nearby enemies.

## Level 4: Cyber City

Theme:

* Digital streets
* Server tunnels
* Glitching buildings
* Security systems
* Data streams

Primary hazards:

* Disappearing platforms
* Security lasers
* Fake upgrades
* Control disruption
* Teleport traps

Boss:

**Ransom Wraith**

Boss ability:

**Glitch Shot**

Jumps between enemies and disables shields, traps, and machines.

## Level 5: Liability Land

Theme:

* Broken amusement park
* Unsafe food court
* Roller coasters
* Haunted attractions
* Crowded public areas

Primary hazards:

* Slippery floors
* Falling signs
* Runaway rides
* Civilian protection events
* Malfunctioning attractions

Boss:

**Baron Blame**

Boss ability:

**Blame Bounce**

Reflects projectiles and increases their return damage.

---

# 13. Final Stage

## The Exclusion Zone

The Exclusion Zone becomes available after the five primary bosses are defeated.

The stage includes:

* Challenges requiring collected boss abilities
* Remixed versions of previous hazards
* Elite enemy combinations
* Mini-boss encounters
* Sections influenced by the player's Risk Meter
* A final confrontation with The Fine Print

## Final boss

**The Fine Print**

First form:

* Contract-based attacks
* Moving exclusion zones
* Ability locks
* Tiny-text projectiles
* Policy Card disruption

Final form:

**The Uninsurable**

A giant catastrophe creature combining elements from all five levels.

---

# 14. Boss Ability Combinations

Boss abilities should interact with each other.

Examples:

### Flame Draft + Surge Shield

Creates a damaging steam cloud.

### Impact Dash + Flame Draft

Turns the dash into a flaming impact attack.

### Glitch Shot + Blame Bounce

Reflected projectiles seek their original attacker.

### Surge Shield + Glitch Shot

Electrifies the shield and damages nearby enemies.

### Impact Dash + Surge Shield

Creates a short tidal-wave attack.

The first release does not need every possible combination. Begin with five to eight designed combinations.

---

# 15. Room Types

Each level should contain multiple room categories.

## Combat room

Defeat all enemies to continue.

## Traversal room

Complete a platforming challenge.

## Hazard room

Survive or disable an environmental catastrophe.

## Rescue room

Protect or rescue civilians.

## Claim event room

Choose between multiple responses with different risks and rewards.

## Shop room

Purchase healing, cards, rerolls, or temporary boosts.

## Mini-boss room

Fight an elite enemy for a strong reward.

## Safety inspection room

Fix hazards for a reward or ignore them and accept increased risk.

## Coverage gap room

Temporarily lose an ability category.

## Secret room

Requires exploration, a boss ability, or a Monster Munch trait.

---

# 16. Enemy Design

Enemies should be readable on small screens.

## Enemy design requirements

* Strong silhouettes
* Limited visual clutter
* Clearly telegraphed attacks
* Distinct sound effects
* Predictable behavior patterns
* Limited projectile counts
* High contrast against backgrounds
* Minimal use of tiny enemies

## Enemy roles

Each level should include:

* Basic melee enemy
* Basic ranged enemy
* Flying enemy
* Armored enemy
* Hazard-generating enemy
* Support enemy
* Elite variant
* Mini-boss

## Example enemies

* Toaster Troopers
* Ember Imps
* Tire Spiders
* Tow Truck Titans
* Lightning Gulls
* Flood Fish
* Spam Cannons
* Password Pirates
* Slip-and-Fall Slimes
* Lawsuit Launchers

---

# 17. Mobile-Friendly Level Design

## Screen readability

* Avoid placing hazards beneath the touch controls
* Keep the player away from the extreme lower corners
* Use wider platforms than a traditional console platformer
* Limit blind jumps
* Show off-screen danger indicators
* Use camera look-ahead in the movement direction
* Slow the camera during precision platforming sections
* Avoid excessive screen shake
* Allow screen shake to be disabled

## Checkpoints

Each completed room functions as a checkpoint.

If the app closes:

* Resume at the start of the current room
* Preserve collected upgrades and resources
* Do not reroll the room to exploit rewards

## Pause behavior

The game should automatically pause when:

* The app loses focus
* A phone call arrives
* The device is locked
* The player opens a system notification
* A controller disconnects

---

# 18. WIT Headquarters

WIT Headquarters is the permanent progression hub.

## Headquarters areas

### Agency Desk

Purchase permanent unlocks.

### Claims Lab

Review enemies, bosses, hazards, and discovered combinations.

### Training Room

Practice movement, weapons, and touch-control layouts.

### Monster Closet

Equip cosmetic items, skins, hats, and color variations.

### Break Room

Interact with characters and view humorous dialogue.

### Risk Map

Start runs and select deductible, character, and modifiers.

## Permanent progression

Permanent upgrades should mainly unlock options rather than create endless stat inflation.

Examples:

* New Policy Cards
* New starting weapons
* New room types
* New shops
* New companions
* New Monster Munch traits
* New exclusions
* New difficulty modifiers
* New cosmetic items
* Alternate boss forms

---

# 19. Claim Report

At the end of every run, generate a humorous claim summary.

Display:

* Cause of loss
* Final level reached
* Rooms completed
* Bosses defeated
* Most-used weapon
* Damage taken
* Civilians rescued
* Enemies consumed
* Total estimated property damage
* Final Risk Meter
* Claim status

Example:

**Cause of loss:** Struck by flaming roller-coaster debris.
**Contributing factor:** Insured ignored four warning signs.
**Claim status:** Under review.
**Estimated property damage:** $4,821,400.

The claim report should be formatted so the player can capture and share it.

A later update may add direct social sharing.

---

# 20. Art Direction

## Visual style

* High-quality 2D cartoon or pixel-inspired art
* Bold outlines
* Strong silhouettes
* Expressive character animation
* Bright environments
* Clear visual hierarchy
* Minimal realistic detail
* Large, readable effects
* WIT blue used consistently in the Monster and interface

The game should not look like a corporate branded application.

## Character animation priorities

The Monster needs expressive animations for:

* Idle
* Run
* Jump
* Fall
* Dash
* Wall cling
* Attack
* Charged attack
* Taking damage
* Monster Munch
* Boss ability use
* Victory
* Defeat
* Reading fine print
* Reacting to dangerous upgrades

---

# 21. Audio Direction

## Music

Each level should have:

* Main stage theme
* High-risk variation
* Boss theme
* Victory cue

Music should be energetic and loop cleanly.

## Sound effects

Prioritize:

* Jump
* Dash
* Attack
* Charged attack
* Damage
* Coverage warning
* Policy selection
* Risk increase
* Boss ability use
* Enemy attack telegraphs
* Room completion

## Haptics

Use optional haptic feedback for:

* Dash
* Charged shot
* Major damage
* Boss defeat
* Policy selection
* Risk Meter increase

Do not vibrate continuously during combat.

---

# 22. Accessibility

Required options:

* Repositionable controls
* Adjustable control size
* Adjustable control opacity
* Left-handed layout
* Aim assist settings
* Reduced screen shake
* Reduced flashing
* Colorblind-safe indicators
* Larger text mode
* Subtitle support
* Separate music and effect volume
* Haptic disable option
* Hold or toggle options for charge attacks
* Simplified dash control
* Optional auto-fire
* Optional invulnerability assist
* Game speed reduction option

Accessibility options should not reduce permanent rewards.

---

# 23. User Interface

## HUD

The gameplay HUD should include:

* Coverage meter
* Boss ability meter
* Equipped ability icon
* Risk Meter
* Currency
* Optional active Policy Card indicators

Avoid displaying every active effect at all times.

## Menus

Menus must support:

* Touch
* Controller
* Large tap targets
* Minimal nested navigation
* Fast restart
* Fast resume
* Clear confirmation before deleting save data

## Inventory screen

The player should be able to pause and view:

* Current Policy Cards
* Active exclusions
* Boss abilities
* Current Monster Munch trait
* Companion
* Level progress
* Current stats

---

# 24. Save System

Save locally after:

* Every completed room
* Every boss defeat
* Every Headquarters purchase
* Every settings change
* Every unlocked achievement

Maintain separate data for:

* Permanent profile
* Active run
* Settings
* Statistics
* Unlocks

Use save versioning so future updates can migrate older save data.

---

# 25. Monetization

Recommended approach:

## Preferred

* Paid premium game
* One-time purchase
* No advertisements
* No energy system
* No pay-to-win upgrades

## Alternative

* Free initial download
* First level available for free
* One-time purchase unlocks the full game

## Future optional purchases

Only consider:

* Cosmetic skin packs
* Soundtrack
* Expansion levels
* Additional playable characters

Do not sell Policy Cards, permanent stats, revives, or run currency.

---

# 26. MVP Scope

The first internal playable prototype should include:

* One test environment
* WIT Monster movement
* Touch controls
* Base weapon
* Dash
* Wall jump
* Coverage meter
* One enemy
* One hazard
* One room transition
* One temporary upgrade
* Save and resume
* Controller support

## Vertical slice

The vertical slice should include:

* Blaze Borough
* Five to eight room modules
* Three basic enemies
* One elite enemy
* One mini-boss
* Inferno Adjuster boss fight
* Flame Draft ability
* Five Policy Cards
* One exclusion
* Risk Meter
* One shop
* One claim event
* Basic Headquarters
* End-of-run claim report
* Finished touch controls
* Representative art and audio

The vertical slice should be used to determine whether the full game should proceed.

---

# 27. Full Initial Release Scope

Recommended initial release:

* One playable character
* Five full levels
* One final stage
* Five primary bosses
* One final boss with two forms
* Five boss abilities
* Five to eight ability combinations
* Approximately 40 Policy Cards
* Approximately 10 exclusions
* Five mini-bosses
* Six to eight enemy types per level
* One Headquarters hub
* Three deductible settings
* One companion system
* Approximately six companions
* Daily challenge framework prepared but not necessarily enabled
* Local achievements
* Cloud save support if schedule permits
* Touch and controller support

---

# 28. Development Phases

## Phase 1: Movement prototype

Build:

* Touch controls
* Character movement
* Jumping
* Dash
* Wall interaction
* Camera
* Base attack

Do not proceed until movement feels good on a physical phone.

## Phase 2: Combat prototype

Build:

* Enemy framework
* Damage system
* Coverage meter
* Projectiles
* Monster Munch
* Basic boss ability
* Hit effects
* Haptics

## Phase 3: Roguelite framework

Build:

* Room sequencing
* Randomized encounter system
* Policy Cards
* Exclusions
* Risk Meter
* Rewards
* Save and resume

## Phase 4: Vertical slice

Complete Blaze Borough with polished mobile gameplay.

## Phase 5: Content production

Build the remaining four Risk Zones and the final stage.

## Phase 6: Headquarters and progression

Complete permanent upgrades, unlocks, statistics, cosmetics, and training.

## Phase 7: Optimization and accessibility

Test on multiple device sizes and performance classes.

## Phase 8: Beta testing

Run:

* Internal testing
* Small closed mobile beta
* Wider external beta
* Crash and performance testing
* Touch-layout testing
* Difficulty balancing

## Phase 9: Release preparation

Complete:

* Store listings
* Privacy policy
* Age rating
* Achievements
* Device compatibility checks
* Marketing screenshots
* Trailer
* Support documentation

---

# 29. Technical Architecture

Suggested high-level systems:

* Game manager
* Run manager
* Room manager
* Input manager
* Touch control manager
* Player controller
* Weapon system
* Boss ability system
* Policy Card system
* Exclusion system
* Risk Meter system
* Enemy base class
* Boss base class
* Damage and status system
* Reward manager
* Shop system
* Save manager
* Audio manager
* Haptic manager
* Analytics manager
* Accessibility manager
* UI manager

Use data-driven resources for:

* Policy Cards
* Enemies
* Boss abilities
* Exclusions
* Rooms
* Rewards
* Level modifiers

Designers should be able to add cards and enemies without rewriting core systems.

---

# 30. Coding Requirements

* Keep gameplay logic separate from visual presentation
* Use reusable enemy and room components
* Avoid hardcoding upgrade values
* Create centralized input actions
* Support touch and controller through the same input layer
* Use object pooling for projectiles and common effects
* Limit physics calculations on inactive rooms
* Pause processing for off-screen enemies
* Profile performance on real devices frequently
* Add automated tests for save migration and upgrade calculations
* Maintain documented data formats
* Use feature branches and pull requests
* Require code review for core systems

---

# 31. Mobile Testing Requirements

Test on:

* Small iPhone
* Large iPhone
* Small Android phone
* Large Android phone
* Tablet
* Lower-performance Android device
* Device with display notch
* Device using system gesture navigation
* Device with Bluetooth controller

Test scenarios:

* Rapid multi-touch input
* Phone interruption
* App backgrounding
* Low battery mode
* Audio interruption
* Controller disconnect
* Device rotation attempt
* Long suspended session
* Save corruption recovery
* Thermal throttling
* Low storage

---

# 32. Prototype Acceptance Criteria

The first prototype is successful when:

1. The Monster feels responsive on a physical phone.
2. Players can move, jump, dash, and attack simultaneously.
3. Touch controls do not obscure major hazards.
4. The game holds a stable frame rate on a mid-range device.
5. Players understand the Coverage meter without explanation.
6. A player can complete the test room using only touch controls.
7. The game resumes correctly after being closed.
8. A new player can begin playing without a lengthy tutorial.
9. Test players voluntarily replay the prototype.
10. The Monster's personality is visible through animation alone.

---

# 33. Vertical Slice Acceptance Criteria

The vertical slice is successful when:

1. Blaze Borough can be completed from start to boss.
2. Room order changes between runs.
3. Policy selections create noticeably different builds.
4. The Risk Meter creates meaningful temptation.
5. Inferno Adjuster is readable and fair on a phone screen.
6. Flame Draft changes combat and exploration.
7. The player can pause, close, and resume without losing progress.
8. Touch controls remain comfortable through a 20-minute session.
9. The claim report feels funny and shareable.
10. Players understand that the game is connected to We Insure Things without feeling like they are playing an advertisement.

---

# 34. Features to Avoid During Initial Development

Do not add these before the vertical slice is proven:

* Online multiplayer
* PvP
* Large open world
* Procedurally generated individual platforms
* Complex equipment crafting
* User-generated levels
* Live service battle pass
* Real-money consumables
* Online leaderboards
* Voice acting for every character
* More than one playable character
* More than five initial levels
* Large narrative cinematics

These may be considered after the core game is proven.

---

# 35. Core Identity

The game's four defining systems should remain:

1. **Mobile-first action-platforming**
2. **Build-your-own Policy Card combinations**
3. **Risk-versus-reward deductible and exclusion choices**
4. **Interactive disasters with humorous claim reports**

The WIT Monster must feel like a real game character, not a company logo placed inside a generic platformer.

The primary development priority is simple:

**Make moving, jumping, dashing, and attacking with the WIT Monster feel excellent on a phone before building the rest of the game.**
