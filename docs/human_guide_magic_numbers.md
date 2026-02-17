# TinyBASIC Game Memory Guide (Human Version)

This document explains the "magic numbers" in the BAS game and how they map to the Zig VM and WinAPI backend.

## 1. Big Picture

The BASIC program talks to a 64KB byte memory array in the VM.

- VM memory: `mem[0..65535]` in `src/il_vm.zig:347`
- `POKE addr,val` writes one byte into that array in `src/il_vm.zig:925`
- `PEEK(addr)` reads one byte in `src/il_vm.zig:945`

Important detail:

- `POKE 0,x` is special.
- It sets a full integer `draw_x` (not only byte 0) in `src/il_vm.zig:933`.
- That is why X can be larger than 255 for drawing.

## 2. CALL Numbers (Your mini API)

`CALL n` is dispatched in `src/il_vm.zig:955`.

- `CALL 2` = draw sprite (`execSpriteDraw`) at `src/il_vm.zig:1159`
- `CALL 4` = keyboard state (`execKeyState`) at `src/il_vm.zig:1279`
- `CALL 5` = sleep/timing (`execSleep`) at `src/il_vm.zig:1289`
- `CALL 6` = clear frame (`execGdiClear`) at `src/il_vm.zig:1321`
- `CALL 7` = draw text/HUD/level splash (`execTextDraw`) at `src/il_vm.zig:1195`

## 3. Memory Layout Used By Your Game

These addresses are conventions used by `examples/chain_invaders/game_main.bas`.

- `1000..1063` = ship sprite bytes (8x8)
- `1100..1163` = enemy sprite bytes (8x8)
- `2200..2204` = alive flags for 5 enemies (1 alive, 0 dead)
- `8..12` = HUD values for `CALL 7` HUD mode
- `0..6` = command parameters for draw/input/sleep/text calls

This layout is not forced by BASIC syntax.
It is a design contract between your BAS program and your VM.

## 4. DATA Numbers: What They Mean

Example:

`10 DATA 8,8`

- first number = width
- second number = height

Then 64 values follow for 8x8 pixels.

- `0` means black pixel
- `255` means white pixel
- middle values like `64`, `128`, `200` are grayscale shades

These values are copied into RAM with:

- `READ A`
- `POKE 1000+I,A` for ship
- `POKE 1100+I,A` for enemy

See lines in your BAS:

- `examples/chain_invaders/game_main.bas:23`
- `examples/chain_invaders/game_main.bas:30`

## 5. How Sprite Draw Works (CALL 2)

Before `CALL 2`, program must fill these registers:

- `POKE 0,X` = x
- `POKE 1,Y` = y
- `POKE 2,W` = width
- `POKE 3,H` = height
- `POKE 4..` = pixel bytes (W*H bytes)

Then `CALL 2` draws.

See `src/il_vm.zig:1169` and `src/il_vm.zig:1181`.

## 6. How Keyboard Works (CALL 4)

Pattern:

- `POKE 0,37` then `CALL 4` checks Left arrow
- VM writes result to `mem[1]`
- `PEEK(1)=1` means key pressed

Used lines:

- `examples/chain_invaders/game_main.bas:131`
- `examples/chain_invaders/game_main.bas:132`

## 7. How Timing Works (CALL 5)

Sleep uses 16-bit milliseconds:

- `ms = mem[0] + 256*mem[1]`

So:

- `POKE 0,16`
- `POKE 1,0`
- `CALL 5`

means roughly 16 ms frame delay.

Code: `src/il_vm.zig:1290`

## 8. Why `IF PEEK(2200+I)=0 THEN LET I=0` Exists

Line: `examples/chain_invaders/game_main.bas:161`

Human meaning:

- `2200+I` accesses enemy `I` alive flag.
- If chosen enemy is dead (`0`), fallback to enemy `0`.

So this line is "pick shooter I; if dead, use a known slot".

Related alive/dead writes:

- `POKE 2200+I,1` at spawn (`examples/chain_invaders/game_main.bas:110`)
- `POKE 2200+I,0` when hit (`examples/chain_invaders/game_main.bas:194`)

## 9. HUD and Level Text (CALL 7)

`CALL 7` has modes:

- `mem[4]=254` => HUD mode (`SCORE/LIVES/LEVEL`)
- `mem[4]=0` => level splash mode (uses `mem[7]` as ASCII digit)
- otherwise => generic text draw (`addr,len,shade,scale`)

Implementation: `src/il_vm.zig:1209`

## 10. Relation To WinAPI

Your BASIC does not call WinAPI directly.
Your VM wraps WinAPI and exposes tiny CALL numbers.

Main mappings:

- window create: `CreateWindowExA` in `src/win32_gdi.zig:90`, used at `src/win32_gdi.zig:189`
- correct client size: `AdjustWindowRectEx` at `src/win32_gdi.zig:141` and `src/win32_gdi.zig:186`
- frame present: `StretchBlt` at `src/win32_gdi.zig:121` and `src/win32_gdi.zig:303`
- keyboard: `GetAsyncKeyState` at `src/win32_gdi.zig:140` and `src/win32_gdi.zig:399`
- sleep: `Sleep` at `src/win32_gdi.zig:142` and `src/win32_gdi.zig:404`

So your BAS numbers are not random.
They are a compact hardware-like interface you designed on top of WinAPI.

## 11. Practical Rule To Avoid Future Confusion

When adding a new feature, always define:

- CALL id
- input memory addresses
- output memory addresses
- valid value ranges

Then write it in one table first, and code second.
