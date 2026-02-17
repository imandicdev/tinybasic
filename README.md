# tinybasic

TinyBASIC interpreter, IL VM, and Win32/GDI runtime implemented in Zig 0.15.x.

## Author

- Ilija Mandic

## Project Purpose

- Build a practical, modern TinyBASIC system in Zig using an IL-based execution model.
- Learn and teach compiler/interpreter internals through real implementation, not toy-only examples.
- Keep the codebase constrained and understandable while still supporting advanced workflows (graphics, input, tooling).

## Main Components

- `src/il.zig`: IL assembler and opcode/label resolution.
- `src/il_vm.zig`: IL virtual machine execution engine.
- `src/parser.zig`, `src/lexer.zig`, `src/ast.zig`, `src/semantic.zig`: BASIC front-end pipeline.
- `src/win32_gdi.zig`: Win32/GDI graphics integration.
- `src/main.zig`: CLI entry points and runtime orchestration.

## Build

```powershell
cd D:\programiranje\Zig\tinybasic
..\zig-x86_64-windows-0.15.1\zig.exe build
.\zig-out\bin\tinybasic.exe
```

## Notes

- Public BASIC examples are intentionally minimal in this repository.
- Advanced/private game BAS sources are kept out of version control by `.gitignore` policy.
