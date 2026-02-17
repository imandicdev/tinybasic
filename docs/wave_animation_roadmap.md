# Wave Animation Roadmap

Goal: richer enemy wave motion while keeping Tiny BASIC constraints (255 lines, integer-only math, current CALL API).

## Planned patterns

1. Side Entry + Patrol (current baseline)
- Enter from left or right edge to target `Z`.
- Patrol horizontally after entry.

2. Top-Left Arc Entry
- Spawn above view (`T=-16`).
- Move diagonally down-right to center.
- Transition to patrol at `U=80..140`.

3. Top-Right Arc Entry
- Spawn above view (`T=-16`).
- Move diagonally down-left to center.
- Transition to patrol at `U=80..140`.

4. Center Dive Formation
- 2 enemies break from formation and dive toward player lane.
- On missed shot or timeout, return to top row.

## Level progression

1. Level 1
- Side entry only.
- Single enemy bullet.
- Cooldown ~18 frames.

2. Level 2
- Side + top arc entries mixed by RNG.
- Single enemy bullet with occasional short volley.
- Cooldown ~10, burst cooldown ~4.

3. Level 3
- All entry types.
- Faster patrol and bullet speed.
- More frequent dives.

## HUD and pacing

- Keep HUD at scale 1 using `CALL 7` HUD mode (`mem[4]=254`).
- Keep level splash at 3 seconds using `CALL 7` level mode (`mem[4]=0`, `mem[7]='1'..'9'`).
- Always clear `mem[4]` before level splash call.

## Technical constraints to preserve

- No `AND` or `:` dependencies.
- Line numbers remain `1..255`.
- Avoid arithmetic overflow in RNG path by normalizing negative values before `%`-style reductions.
- Keep sprite coordinates in visible range before `POKE`.
