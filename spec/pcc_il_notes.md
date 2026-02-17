# PCC Tiny BASIC IL Spec Notes (pages 15-18)

Source PDF: `D:\Downloads\1975-09 Peoples Computer Company.pdf`
Extracted text: `D:\programiranje\Zig\_tmp_pcc_1975_09_p15_18.txt`

These notes are transcribed from pages 15–18 plus the user-supplied IL listing.

## Language/Design Context (page 15-16)
- Variables are integer only; no arrays, no floating point.
- Line numbers 1..255 stored in a single byte.
- Program stored as raw text lines in `PGM` array; line buffer `LBUF` for input.
- Errors reported as `I mmm AT nnn` (or `I mmm` in direct mode).

## IL Instruction Set (page 17 + IL listing)

Mnemonic | Summary
---|---
`TST lbl, 'string'` | Delete leading blanks. If string matches BASIC line at cursor, advance cursor and execute next IL instruction; else jump to `lbl`.
`CALL lbl` | Call IL subroutine at `lbl`; push return address on control stack.
`RTN` | Return to IL address on control stack.
`DONE` | If cursor (after trimming blanks) is not at carriage return, report syntax error.
`JMP lbl` | Jump to IL label.
`PRS` | Print characters from BASIC text until closing quote; error on CR. Advance cursor past closing quote.
`PRN` | Print number popped from expression stack (AESTK).
`SPC` | Print spaces to next zone.
`NLINE` | Output CRLF.
`NXT` | If direct mode (line number 0) return to line collection; else go to next sequential line.
`XFER` | Test value at top of AE stack to be within range. If not, error. If so, attempt to position cursor at that line; if it exists, begin interpretation there; if not, error. (User-confirmed.)
`SAV` | Push current line number onto GOSUB stack; overflow -> error.
`RSTR` | Pop GOSUB stack into current line number; empty -> error.
`CMPR` | Compare AESTK(SP) vs AESTK(SP-2) per relation in AESTK(SP-1); if false, perform `NXT`.
`INNUM` | Read a number from terminal; push on expression stack.
`FIN` | Return to the line collect routine.
`ERR` | Report syntax error and return to line collect.
`ADD` | Replace top two stack elements by sum.
`SUB` | Replace top two stack elements by difference.
`NEG` | Replace top of stack by its negative.
`MUL` | Replace top two elements by product. (Listing uses `MPY`.)
`DIV` | Replace top two elements by quotient.
`STORE` | Store top of stack into variable indexed by value below it; pop both.
`TSTV lbl` | If variable (letter) present, push its index on stack; else jump to `lbl`.
`TSTN lbl` | If number present, push its value on stack; else jump to `lbl`.
`IND` | Replace top of stack with value of variable indexed by it.
`LST` | List program area.
`INIT` | Global initialization.
`GETLINE` | Input a line to `LBUF`. (Listing uses `GETLN`.)
`TSTL lbl` | After trimming blanks, look for line number. Error if invalid; jump to `lbl` if not present.
`INSRT` | Insert line after deleting any line with same number.
`XINIT` | Per-statement initialization; empties expression stack.
`LIT n` | Push literal numeric value onto AESTK. (Used in RELOP.)

### Macro mnemonics in IL listing
The listing uses these macro spellings; treat them as aliases:
- `ICALL` -> `CALL`
- `IJMP` -> `JMP`
- `HOP` -> `JMP`
- `MPY` -> `MUL`
- `GETLN` -> `GETLINE`

## Relational Operators (RELOP)
The listing encodes:
- `0` = `=`
- `1` = `<`
- `2` = `<=`
- `3` = `<>` (also `><`)
- `4` = `>`
- `5` = `>=`

## TODO (Spec Cleanup)
1. Verify any ambiguous labels or operands from the page images.
2. Normalize the IL listing into a single-line instruction format (done in `spec/pcc_il_listing_normalized.il`).
