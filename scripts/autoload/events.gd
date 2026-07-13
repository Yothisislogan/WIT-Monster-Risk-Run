extends Node
## Global signal bus. Gameplay systems emit here; UI and presentation listen.
## Keeps gameplay logic decoupled from visuals (see docs/GAME_DESIGN.md §30).

# Player / coverage
signal coverage_changed(current: int, maximum: int)
signal player_damaged(amount: int, source: String)
signal player_died(cause: String)
signal shield_changed(active: bool)
signal charge_changed(ratio: float)
signal ability_energy_changed(current: float, maximum: float)

# Economy / upgrades
signal currency_changed(amount: int)
signal upgrade_gained(upgrade_id: String)

# Run / room flow
signal room_started(room_path: String)
signal room_completed(room_path: String)
signal run_started
signal run_ended(claim_report: Dictionary)
