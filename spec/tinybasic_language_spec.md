# Tiny BASIC Language Spec (draft)

This spec is derived from the PCC IL listing and will be refined as you provide AST rules. It is designed to match the IL control flow in `spec/pcc_il_listing_normalized.il` and the VM behavior.

## Program
- A program is a set of numbered lines with optional statements.
- Line numbers are integers 1..255.
- Lines are stored in sorted order by line number.
- Entering a line number with no statement deletes that line.

## Statements
The following statements are supported:

1. LET
- Syntax: `LET <var> = <expr>`
- Example: `LET A = 10`
- Semantics: evaluate expression, store into variable cell.

2. GOTO
- Syntax: `GOTO <expr>`
- Example: `GOTO 120`
- Semantics: evaluate expression, must be a valid existing line number.

3. GOSUB
- Syntax: `GOSUB <expr>`
- Example: `GOSUB 200`
- Semantics: push next line number onto gosub stack, then jump to target line.

4. RETURN
- Syntax: `RETURN`
- Semantics: pop from gosub stack; resume at next line after caller.

5. IF THEN
- Syntax: `IF <expr> <relop> <expr> THEN <statement>`
- Example: `IF A < 10 THEN PRINT A`
- Semantics: if condition true, execute the following statement on same line; else skip to next line.

6. INPUT
- Syntax: `INPUT <var> ( , <var> )*`
- Example: `INPUT A, B, C`
- Semantics: read integer values from input, store sequentially into variables.

7. PRINT
- Syntax: `PRINT ( <string> | <expr> ) ( , ( <string> | <expr> ) )*`
- Example: `PRINT "HELLO", A+1, "!"`
- Semantics: print items in sequence; commas advance to next output zone (8-col).

8. END
- Syntax: `END`
- Semantics: terminate program execution.

9. LIST
- Syntax: `LIST`
- Semantics: print all stored program lines in ascending order with line numbers.

10. RUN
- Syntax: `RUN`
- Semantics: begin execution from lowest numbered line.

11. CLEAR
- Syntax: `CLEAR`
- Semantics: clear all program lines and variables; return to prompt.
11a. CLS
- Syntax: `CLS`
- Semantics: clear the screen output; does not modify program.

12. SAVE
- Syntax: `SAVE \"file.bas\"`
- Semantics: write current program lines to file. If no extension is provided, `.bas` is appended.

13. LOAD
- Syntax: `LOAD \"file.bas\"`
- Semantics: clear current program and load lines from file. If no extension is provided, `.bas` is appended.

14. BYE
- Syntax: `BYE`
- Semantics: exit the interpreter.

15. DATA
- Syntax: `DATA <num>(, <num>)*`
- Semantics: store literal data for `READ`. Data lines are not executed.

16. READ
- Syntax: `READ <var>(, <var>)*`
- Semantics: sequentially read values from DATA into variables.

17. RESTORE
- Syntax: `RESTORE`
- Semantics: reset DATA read pointer to start.

18. POKE
- Syntax: `POKE <addr>, <value>`
- Semantics: write a byte (0..255) to sandboxed memory.
 - Memory size: 65536 bytes (addresses 0..65535)

19. PEEK
- Syntax: `PEEK(<addr>)` (expression)
- Semantics: read a byte from sandboxed memory.

20. CALL
- Syntax: `CALL <id>`
- Semantics: invoke a safe, whitelisted stub by id.

## Expressions
- Integers: signed, decimal, or hex with `&H` / `0x`
- Variables: `A`..`Z`
- Unary: `+`, `-`
- Binary: `+`, `-`, `*`, `/`
- Parentheses: `(` `)`
- PEEK: `PEEK(<expr>)` returns a byte from the sandboxed memory buffer

### Precedence
1. Parentheses
2. Unary + -
3. * /
4. + -

## Relational Operators
Supported operators:
- `=`  (equal)
- `<`  (less)
- `<=` (less or equal)
- `>`  (greater)
- `>=` (greater or equal)
- `<>` or `><` (not equal)

## Errors
VM reports numeric error codes:
1. Syntax error
2. Missing line
3. Line too large
4. Too many GOSUBs
5. RETURN without GOSUB
6. Expression too complex
7. Too many lines
8. Division by zero
9. Data out of range
10. Bad address
11. Invalid CALL

Format:
- `I ###` in direct mode
- `I ### AT ###` in program mode

## Notes
- Keyword boundary rules: `RUN`, `LIST`, `END`, `RETURN`, `CLEAR` must be standalone tokens; `LET` must not be followed by a digit (e.g., `LET1` is not `LET`).
- `GOTO` is parsed as `GO` + `TO` in IL, but the front-end should accept `GOTO` as a single keyword.

## CALL stubs
1. `CALL 1` — bytecode VM
   - Memory layout:
     - `mem[0..1]`: bytecode length (little-endian)
     - `mem[2..]`: bytecode
   - Opcodes:
     - `0x00` HALT
     - `0x01` OUT_CHAR <byte>
     - `0x02` OUT_NUM <byte>
     - `0x03` NEWLINE
     - `0x10` POKE <addr_lo> <addr_hi> <value>
     - `0x11` PEEK <addr_lo> <addr_hi> -> R0
     - `0x12` OUT_R0

2. `CALL 2` — sprite draw
   - GDI graphics window (320x200, scale x2)
   - Memory layout at `mem[0]`:
     - `mem[0]`: x
     - `mem[1]`: y
     - `mem[2]`: width
     - `mem[3]`: height
     - `mem[4..]`: width*height bytes (0..255 grayscale)
   - Draws grayscale pixels into a framebuffer and presents the window.
