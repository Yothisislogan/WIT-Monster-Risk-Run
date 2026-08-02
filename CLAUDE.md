# WIT Monster: Risk Run — working notes

## Workflow

- **Merge to `main`.** Work on a feature branch, then merge it into `main` and
  push. This is the default for this project; no need to ask each time.
  Pushing `main` deploys to GitHub Pages via `.github/workflows/deploy-web.yml`.
- `docs/GAME_DESIGN.md` is the spec. Cite section numbers in comments.

## The constraint everything else follows from

**There is no Godot binary in this environment.** Nothing can be run,
playtested, or even compiled. The only verification is static: the checkers in
`tools/`, which either parse the GDScript and scene text or re-implement a rule
in Python and assert properties of it.

So: **every checker must be verified by deliberately reintroducing the bug it
is meant to catch.** A checker that has never failed is not known to work. Two
of the existing ones were silently useless when first written — `check_aim.py`
read its own bounds from the source it was checking, and `check_signals.py`
lost whole functions to an apostrophe in a comment.

Prefer binding a checker to the GDScript constants rather than restating them.
A "keep these in sync by hand" note is how the Risk damping curve came to exist
in the model and not in the game.

One more thing only CI can do: `godot --headless --import` in the build job is
the single place a `.gd` file is ever *parsed*. Everything in `tools/` reads
source as text. A green local run does not mean the game loads.

Run them all before committing:

```
for t in references godot_api scenes signals inputs gestures movement aim \
         map sites meta reachability pickups economy text_fit; do python3 tools/check_$t.py || break; done
```

## Architecture rules the codebase actually follows

- Gameplay emits on the `Events` bus; UI listens. No UI logic in gameplay
  scripts, no gameplay logic in UI.
- Content is **data**, not branches. `CardDb`, `Abilities`, `LevelData`,
  `SiteDb` and `Headquarters` are the models: adding content is adding a
  dictionary entry.
- Pool anything spawned repeatedly (`scripts/weapons/projectile_pool.gd`).
- Typed vars, tabs, and `##` doc comments that explain *why* and cite a design
  section — not what the next line already says.

## Level design contract

Rooms are built against the jump budget in the header of
`scripts/player/player.gd` (single rise 143px, double 261px).
`tools/check_reachability.py` proves every room's exit is reachable;
`tools/check_movement.py` proves the budget cannot be exceeded, which is what
makes the first proof mean anything.
