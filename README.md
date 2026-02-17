# tinybasic

TinyBASIC interpreter, IL VM, and Win32/GDI runtime implemented in Zig 0.15.x.

## Author

- Ilija Mandic

## Project Purpose

- Build a practical, modern TinyBASIC system in Zig using an IL-based execution model.
- Learn and teach compiler/interpreter internals through real implementation, not toy-only examples.
- Keep the codebase constrained and understandable while still supporting advanced workflows (graphics, input, tooling).

## Architecture

- Execution model: stack-based IL interpreter VM.
- Runtime: line-numbered BASIC program store + IL control flow dispatcher.
- Memory model: 64KB VM memory buffer for `POKE`/`PEEK`/bytecode and graphics stubs.
- Graphics/input: Win32/GDI-backed built-ins exposed via IL (`BCALL`/runtime calls).

## IL Basis

- Primary historical source: *People's Computer Company* (September 1975), pages 15-18.
- Project references:
  - `spec/pcc_il_listing_normalized.il`
  - `spec/pcc_il_notes.md`
  - `spec/tinybasic_language_spec.md`

## Main Components

- `src/il.zig`: IL assembler and opcode/label resolution.
- `src/il_vm.zig`: IL virtual machine execution engine.
- `src/parser.zig`, `src/lexer.zig`, `src/ast.zig`, `src/semantic.zig`: BASIC front-end pipeline.
- `src/win32_gdi.zig`: Win32/GDI graphics integration.
- `src/main.zig`: CLI entry points and runtime orchestration.

## Scope

- This repository is the interpreter + VM implementation.
- BAS-to-NASM transpilation is a separate project: `bstoasm`.

## Build

```powershell
cd D:\programiranje\Zig\tinybasic
..\zig-x86_64-windows-0.15.1\zig.exe build
.\zig-out\bin\tinybasic.exe
```

## Notes

- Public BASIC examples are intentionally minimal in this repository.
- Advanced/private game BAS sources are kept out of version control by `.gitignore` policy.
