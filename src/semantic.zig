// =============================================================================
// Project : tinybasic
// File    : tinybasic\src\semantic.zig
// Author  : Ilija Mandic
// Purpose : Semantic validation rules for parsed TinyBASIC programs.
// =============================================================================
const std = @import("std");
const ast = @import("ast.zig");

pub const SemanticError = error{
    LineNumberMissing,
    LineNumberOutOfRange,
    DuplicateLineNumber,
    InvalidVariable,
    ReturnInDirectMode,
    IfThenMissingStatement,
    InputMissingVariable,
    PrintMissingItem,
    InvalidRelOp,
    SaveMissingPath,
    LoadMissingPath,
    ChainMissingPath,
    DataMissingValue,
    ReadMissingVariable,
} || std.mem.Allocator.Error;

pub fn validateProgram(allocator: std.mem.Allocator, program: ast.Program) SemanticError!void {
    var seen = std.AutoHashMap(i32, void).init(allocator);
    defer seen.deinit();

    for (program.lines) |line| {
        if (line.number == null) return SemanticError.LineNumberMissing;
        const number = line.number.?;
        if (number < 1 or number > 255) return SemanticError.LineNumberOutOfRange;
        if (seen.contains(number)) return SemanticError.DuplicateLineNumber;
        try seen.put(number, {});

        if (line.stmt) |stmt| {
            try validateStmt(stmt);
        }
    }
}

fn validateStmt(stmt: *ast.Stmt) SemanticError!void {
    switch (stmt.tag) {
        .let_stmt => {
            const payload = stmt.data.let_stmt;
            try validateVarIndex(payload.var_index);
            try validateExpr(payload.value);
        },
        .goto_stmt => {
            try validateExpr(stmt.data.goto_stmt);
        },
        .gosub_stmt => {
            try validateExpr(stmt.data.gosub_stmt);
        },
        .return_stmt => {},
        .if_then => {
            const payload = stmt.data.if_then;
            try validateExpr(payload.left);
            try validateRelop(payload.op);
            try validateExpr(payload.right);
            try validateStmt(payload.then_stmt);
        },
        .input_stmt => {
            const payload = stmt.data.input_stmt;
            if (payload.vars.len == 0) return SemanticError.InputMissingVariable;
            for (payload.vars) |idx| try validateVarIndex(idx);
        },
        .data_stmt => {
            if (stmt.data.data_stmt.values.len == 0) return SemanticError.DataMissingValue;
        },
        .read_stmt => {
            if (stmt.data.read_stmt.vars.len == 0) return SemanticError.ReadMissingVariable;
            for (stmt.data.read_stmt.vars) |idx| try validateVarIndex(idx);
        },
        .restore_stmt => {},
        .poke_stmt => {
            const payload = stmt.data.poke_stmt;
            try validateExpr(payload.addr);
            try validateExpr(payload.value);
        },
        .call_stmt => {
            try validateExpr(stmt.data.call_stmt.target);
        },
        .print_stmt => {
            const payload = stmt.data.print_stmt;
            if (payload.items.len == 0) return SemanticError.PrintMissingItem;
            for (payload.items) |item| {
                switch (item) {
                    .string => {},
                    .expr => |expr| try validateExpr(expr),
                }
            }
        },
        .save_stmt => {
            if (stmt.data.save_stmt.path.len == 0) return SemanticError.SaveMissingPath;
        },
        .load_stmt => {
            if (stmt.data.load_stmt.path.len == 0) return SemanticError.LoadMissingPath;
        },
        .chain_stmt => {
            if (stmt.data.chain_stmt.path.len == 0) return SemanticError.ChainMissingPath;
        },
        .bye_stmt => {},
        .cls_stmt => {},
        .end_stmt, .list_stmt, .run_stmt, .clear_stmt => {},
    }
}

fn validateExpr(expr: ast.ExprRef) SemanticError!void {
    switch (expr.tag) {
        .number => {},
        .variable => try validateVarIndex(expr.data.variable),
        .unary => {
            const payload = expr.data.unary;
            try validateExpr(payload.expr);
        },
        .binary => {
            const payload = expr.data.binary;
            try validateExpr(payload.left);
            try validateExpr(payload.right);
        },
        .peek => try validateExpr(expr.data.peek),
    }
}

fn validateVarIndex(idx: u8) SemanticError!void {
    if (idx >= 26) return SemanticError.InvalidVariable;
}

fn validateRelop(op: ast.RelOp) SemanticError!void {
    switch (op) {
        .equal, .less, .less_equal, .greater, .greater_equal, .not_equal => {},
    }
}

test "rejects duplicate line" {
    const src =
        "10 LET A=1\n" ++
        "10 PRINT A\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parser = @import("parser.zig");
    const program = try parser.parseProgram(arena.allocator(), src);
    try std.testing.expectError(SemanticError.DuplicateLineNumber, validateProgram(arena.allocator(), program));
}

test "rejects missing line number" {
    const src = "PRINT A\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parser = @import("parser.zig");
    const program = try parser.parseProgram(arena.allocator(), src);
    try std.testing.expectError(SemanticError.LineNumberMissing, validateProgram(arena.allocator(), program));
}

test "rejects out of range line" {
    const src = "300 PRINT A\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parser = @import("parser.zig");
    const program = try parser.parseProgram(arena.allocator(), src);
    try std.testing.expectError(SemanticError.LineNumberOutOfRange, validateProgram(arena.allocator(), program));
}

test "rejects input with no vars" {
    const src = "10 INPUT\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parser = @import("parser.zig");
    try std.testing.expectError(parser.ParseError.InvalidVariable, parser.parseProgram(arena.allocator(), src));
}
