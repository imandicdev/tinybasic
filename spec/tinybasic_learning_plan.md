# Tiny BASIC Learning Plan (Zig 0.15.x)

## Scope and deliverables
- You will implement the Tiny BASIC front-end (lexer, parser, AST, semantic checks, IL emitter) in Zig.
- The VM/IL runtime is already being hardened; this plan ties your learning steps to front-end milestones.
- Outputs: unit tests for every stage, a working interpreter (IL + VM), and later a compiler that emits .exe (your task).

## Phase 0: Zig refresh (1-2 weeks)
1. Zig project layout and build system
2. Types and memory model (value types, slices, pointers)
3. Error unions and optional types
4. Structs, enums, tagged unions
5. Allocators and ownership (arena vs general purpose)
6. Testing patterns in Zig

Deliverables
- Create a small toy parser with tests to practice allocators and error handling.
- Use official Zig style and naming rules throughout.

## Phase 1: Tiny BASIC language surface (spec alignment)
1. Statements
2. Expression grammar
3. Line numbering rules
4. Runtime behavior

Proposed surface (matches the PCC IL listing)
- LET, GOTO, GOSUB, RETURN, IF THEN, INPUT, PRINT, END, LIST, RUN, CLEAR
- Variables: A-Z
- Numbers: signed integers
- Expressions: unary +/-, binary + - * /, parentheses

Deliverables
- A single spec markdown file that enumerates grammar and runtime rules.
- A list of test programs (happy path + error cases).

## Phase 2: Lexer
1. Token types: identifiers, numbers, keywords, operators, punctuation, line numbers
2. Whitespace and line endings
3. Error reporting with line/column

Deliverables
- Tokenizer with tests that cover every statement form.
- Negative tests: invalid tokens, overflowing integers, unexpected characters.

## Phase 3: Parser + AST
1. AST node definitions (statements, expressions, program, line nodes)
2. Pratt or recursive descent parser
3. AST arena allocation
4. Parser error recovery strategy (stop at line end)

Deliverables
- Parser that produces a typed AST with location spans.
- Tests for each grammar rule and precedence.

## Phase 4: Semantic validation
1. Validate line numbers are unique and within range
2. Validate IF THEN target is either a statement or a line number (choose one and document)
3. Validate variables are A-Z only
4. Validate numeric ranges (choose limits and document)

Deliverables
- Semantic validator with unit tests for every error case.

## Phase 5: IL code generation
1. Map AST nodes to IL instruction sequences
2. Map expression nodes to the IL expression stack machine
3. Encode control flow (GOTO, GOSUB, RETURN, IF THEN)
4. Emit IL labels for line numbers

Deliverables
- IL emitter that produces the normalized IL format
- Golden-file tests comparing emitted IL for sample programs

## Phase 6: Integration and CLI
1. Read .bas source from file
2. Run through lexer -> parser -> semantic -> IL emitter
3. Assemble IL -> run VM
4. Provide a simple REPL and file runner

Deliverables
- `tinybasic.exe` that runs a .bas file
- Command line flags: run, list, dump-il

## Phase 7: Compiler (your task)
1. IL to machine code or IL to Zig/C stub
2. 32-bit and 64-bit Windows outputs
3. Runtime packaging and distribution

Deliverables
- .exe output for both 32-bit and 64-bit
- Formal build steps and reproducible toolchain

## Work order and TODO list (current)
1. Finalize IL spec notes
2. Finish VM hardening and tests
3. Write grammar spec from the IL listing
4. Implement lexer with tests
5. Implement parser + AST with tests
6. Implement semantic validation
7. Implement IL emitter
8. Integration CLI

## Notes on style
- Follow the official Zig style guide for naming and formatting.
- Prefer `std.StaticStringMap` for keyword/mnemonic lookup.
- Keep data structures explicit and flat; avoid unnecessary indirection.
