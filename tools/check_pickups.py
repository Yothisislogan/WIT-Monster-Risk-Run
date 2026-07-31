#!/usr/bin/env python3
"""Regression test for Premium coin behaviour (scripts/rooms/premium.gd).

Mirrors that script's logic at 60 Hz against Room A geometry. It exists
because a shipped build had `_settled` never set to true, so every coin
applied gravity forever and fell out of the world ~0.8s after room load,
making all coins uncollectable. Keep this green when touching premium.gd.
"""
import math, sys

DT = 1.0 / 60.0
GRAVITY = 1400.0
MAX_FALL = 900.0
MAGNET_RADIUS = 130.0
MAGNET_SPEED = 900.0
COIN_RADIUS = 14.0
COLLECT_DIST = 26.0
PROBE_LEN = 40.0

# Room A ground: GroundLeft top y=600 spanning x 0..820
GROUND_TOP, GROUND_X0, GROUND_X1 = 600.0, 0.0, 820.0

def ground_below(x, y):
    """RayCast2D straight down, length PROBE_LEN, world layer only."""
    if GROUND_X0 <= x <= GROUND_X1 and y <= GROUND_TOP <= y + PROBE_LEN:
        return GROUND_TOP
    return None

class Coin:
    def __init__(self, x, y, old_behaviour=False):
        self.x, self.y = x, y
        self.vx = self.vy = 0.0
        self.falling = False
        self.dropped = False
        self.collect_delay = 0.0
        self.age = 0.0
        self.collected = False
        self.freed = False
        self.old = old_behaviour
        if old_behaviour:          # the shipped bug: _settled never set true
            self.falling = True

    def pop(self, ix, iy):
        self.vx, self.vy = ix, iy
        self.falling = True
        self.dropped = True
        self.collect_delay = 0.25

    def step(self, player):
        if self.collected or self.freed:
            return
        self.age += DT
        self.collect_delay = max(self.collect_delay - DT, 0.0)
        if self.dropped and self.age > 25.0:
            self.freed = True; return
        if not self.old and self.y > 1200.0:
            self.freed = True; return

        if self.collect_delay <= 0.0 and player is not None:
            dx, dy = player[0] - self.x, player[1] - self.y
            dist = math.hypot(dx, dy)
            if 0.0 < dist < MAGNET_RADIUS:
                step = min(MAGNET_SPEED * DT, dist)
                self.x += dx / dist * step
                self.y += dy / dist * step
                if dist < COLLECT_DIST:
                    self.collected = True
                return

        if self.falling:
            if self.old:
                self.vy += GRAVITY * DT              # no clamp, no probe
            else:
                self.vy = min(self.vy + GRAVITY * DT, MAX_FALL)
            self.vx += (0.0 - self.vx) * 0.0 if self.vx == 0 else 0.0
            self.vx = math.copysign(max(abs(self.vx) - 420.0 * DT, 0.0), self.vx)
            self.x += self.vx * DT
            self.y += self.vy * DT
            if not self.old and self.vy > 0.0:
                hit = ground_below(self.x, self.y)
                if hit is not None:
                    self.y = hit - COIN_RADIUS
                    self.vx = self.vy = 0.0
                    self.falling = False

fails = []

# 1. OLD behaviour: a hand-placed coin should NOT survive (reproduces the bug)
old = Coin(700.0, 470.0, old_behaviour=True)
for _ in range(int(3.0 / DT)):
    old.step(None)
print(f"1. shipped build, placed coin at y=470 -> y={old.y:.0f} after 3s "
      f"({'FELL OUT OF WORLD' if old.y > 900 else 'still there'})")
if old.y <= 900:
    fails.append("expected the old build to reproduce the falling bug")

# 2. NEW: hand-placed coin must stay exactly put
placed = Coin(700.0, 470.0)
for _ in range(int(10.0 / DT)):
    placed.step(None)
print(f"2. fixed, placed coin at y=470 -> y={placed.y:.0f} after 10s")
if abs(placed.y - 470.0) > 0.001 or placed.freed:
    fails.append("placed coin moved or despawned")

# 3. NEW: dropped coin arcs and lands on the ground
drop = Coin(360.0, 576.0)
drop.pop(110.0, -320.0)
landed_at = None
for i in range(int(5.0 / DT)):
    drop.step(None)
    if not drop.falling and landed_at is None:
        landed_at = (i * DT, drop.x, drop.y)
        break
if landed_at:
    print(f"3. fixed, dropped coin landed after {landed_at[0]:.2f}s at "
          f"({landed_at[1]:.0f}, {landed_at[2]:.0f}); ground top {GROUND_TOP:.0f}")
    if abs(landed_at[2] - (GROUND_TOP - COIN_RADIUS)) > 0.5:
        fails.append("dropped coin did not settle flush on the ground")
else:
    fails.append("dropped coin never landed")

# 4. NEW: a settled coin is collected when the player walks up to it
coin = Coin(700.0, 470.0)
collected_at = None
for i in range(int(4.0 / DT)):
    t = i * DT
    px = 500.0 + 360.0 * t          # player runs right at move_speed
    coin.step((px, 470.0))
    if coin.collected:
        collected_at = t
        break
print(f"4. fixed, walking player collected the coin at t={collected_at}s"
      if collected_at else "4. FAILED: player never collected the coin")
if collected_at is None:
    fails.append("player could not collect a placed coin")

# 5. NEW: no tunnelling at max fall speed
step_px = MAX_FALL * DT
print(f"5. max per-frame fall {step_px:.1f}px vs {PROBE_LEN:.0f}px probe "
      f"-> {'safe' if step_px < PROBE_LEN else 'CAN TUNNEL'}")
if step_px >= PROBE_LEN:
    fails.append("coin can tunnel through thin platforms")

if fails:
    print("\nFAIL"); [print(" -", f) for f in fails]; sys.exit(1)
print("\nAll coin checks passed.")
