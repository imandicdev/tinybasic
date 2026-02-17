# tinybasic

TinyBASIC interpreter and IL virtual machine in Zig 0.15.x.

Author: Ilija Mandic

## What This Project Is

- A line-numbered TinyBASIC interpreter.
- A stack-based IL VM runtime.
- A Win32/GDI runtime layer for graphics and input built-ins.

## Historical Basis

The IL model follows the Tiny BASIC IL listing published in *People's Computer Company* (September 1975), pages 15-18.

Important distinction:
- IL here is a virtual instruction set executed by this VM.
- It is not raw CPU machine code.
- The original listing was hosted on Intel Intellec 8 / MOD 80 (8080-era) systems.

Reference files:
- `spec/pcc_il_listing_normalized.il`
- `spec/pcc_il_notes.md`
- `spec/tinybasic_language_spec.md`

## Main Source Files

- `src/il.zig`: IL assembler and opcode/operand resolution.
- `src/il_vm.zig`: VM execution engine and runtime behavior.
- `src/lexer.zig`, `src/parser.zig`, `src/ast.zig`, `src/semantic.zig`: BASIC front-end.
- `src/win32_gdi.zig`: Win32/GDI graphics backend.
- `src/main.zig`: CLI entry point and mode dispatch.

## Build

```powershell
zig build
zig-out/bin/tinybasic
```

On Windows, the binary is `zig-out/bin/tinybasic.exe`.

## Scope

This repository is the interpreter/VM project.

The separate BAS-to-NASM transpiler lives in `bastoasm`.

## Repository Policy

- Public BASIC examples in this repo stay minimal.
- Advanced/private game BAS files are excluded by `.gitignore`.
