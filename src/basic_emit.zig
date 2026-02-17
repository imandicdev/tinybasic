// =============================================================================
// Project : tinybasic
// File    : tinybasic\src\basic_emit.zig
// Author  : Ilija Mandic
// Purpose : BASIC-to-IL emission and lowering helpers.
// =============================================================================
const std = @import("std");
const ast = @import("ast.zig");

pub const EmitError = error{OutOfMemory};

pub fn emitProgram(allocator: std.mem.Allocator, program: ast.Program) EmitError![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    for (program.lines) |line| {
        if (line.number) |number| {
            try appendNumber(&buf, allocator, number);
            if (line.stmt) |stmt| {
                try buf.append(allocator, ' ');
                try emitStmt(&buf, allocator, stmt);
            }
            try buf.append(allocator, '\n');
        }
    }

    return buf.toOwnedSlice(allocator);
}

pub fn emitLineText(allocator: std.mem.Allocator, stmt: *ast.Stmt) EmitError![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try emitStmt(&buf, allocator, stmt);
    return buf.toOwnedSlice(allocator);
}

fn emitStmt(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, stmt: *ast.Stmt) EmitError!void {
    switch (stmt.tag) {
        .let_stmt => {
            try appendLiteral(buf, allocator, "LET ");
            try appendVar(buf, allocator, stmt.data.let_stmt.var_index);
            try appendLiteral(buf, allocator, " = ");
            try emitExpr(buf, allocator, stmt.data.let_stmt.value);
        },
        .goto_stmt => {
            try appendLiteral(buf, allocator, "GOTO ");
            try emitExpr(buf, allocator, stmt.data.goto_stmt);
        },
        .gosub_stmt => {
            try appendLiteral(buf, allocator, "GOSUB ");
            try emitExpr(buf, allocator, stmt.data.gosub_stmt);
        },
        .return_stmt => try appendLiteral(buf, allocator, "RETURN"),
        .if_then => {
            const payload = stmt.data.if_then;
            try appendLiteral(buf, allocator, "IF ");
            try emitExpr(buf, allocator, payload.left);
            try buf.append(allocator, ' ');
            try appendRelop(buf, allocator, payload.op);
            try buf.append(allocator, ' ');
            try emitExpr(buf, allocator, payload.right);
            try appendLiteral(buf, allocator, " THEN ");
            try emitStmt(buf, allocator, payload.then_stmt);
        },
        .input_stmt => {
            const payload = stmt.data.input_stmt;
            try appendLiteral(buf, allocator, "INPUT ");
            for (payload.vars, 0..) |idx, i| {
                if (i != 0) try appendLiteral(buf, allocator, ", ");
                try appendVar(buf, allocator, idx);
            }
        },
        .print_stmt => {
            const payload = stmt.data.print_stmt;
            try appendLiteral(buf, allocator, "PRINT ");
            for (payload.items, 0..) |item, i| {
                if (i != 0) try appendLiteral(buf, allocator, ", ");
                switch (item) {
                    .string => |s| {
                        try buf.append(allocator, '"');
                        try buf.appendSlice(allocator, s);
                        try buf.append(allocator, '"');
                    },
                    .expr => |expr| try emitExpr(buf, allocator, expr),
                }
            }
        },
        .data_stmt => {
            try appendLiteral(buf, allocator, "DATA ");
            const values = stmt.data.data_stmt.values;
            for (values, 0..) |value, i| {
                if (i != 0) try appendLiteral(buf, allocator, ", ");
                try appendNumber(buf, allocator, value);
            }
        },
        .read_stmt => {
            try appendLiteral(buf, allocator, "READ ");
            const vars = stmt.data.read_stmt.vars;
            for (vars, 0..) |idx, i| {
                if (i != 0) try appendLiteral(buf, allocator, ", ");
                try appendVar(buf, allocator, idx);
            }
        },
        .restore_stmt => try appendLiteral(buf, allocator, "RESTORE"),
        .poke_stmt => {
            const payload = stmt.data.poke_stmt;
            try appendLiteral(buf, allocator, "POKE ");
            try emitExpr(buf, allocator, payload.addr);
            try appendLiteral(buf, allocator, ", ");
            try emitExpr(buf, allocator, payload.value);
        },
        .call_stmt => {
            try appendLiteral(buf, allocator, "CALL ");
            try emitExpr(buf, allocator, stmt.data.call_stmt.target);
        },
        .end_stmt => try appendLiteral(buf, allocator, "END"),
        .list_stmt => try appendLiteral(buf, allocator, "LIST"),
        .run_stmt => try appendLiteral(buf, allocator, "RUN"),
        .clear_stmt => try appendLiteral(buf, allocator, "CLEAR"),
        .cls_stmt => try appendLiteral(buf, allocator, "CLS"),
        .save_stmt => {
            try appendLiteral(buf, allocator, "SAVE ");
            try buf.append(allocator, '"');
            try buf.appendSlice(allocator, stmt.data.save_stmt.path);
            try buf.append(allocator, '"');
        },
        .load_stmt => {
            try appendLiteral(buf, allocator, "LOAD ");
            try buf.append(allocator, '"');
            try buf.appendSlice(allocator, stmt.data.load_stmt.path);
            try buf.append(allocator, '"');
        },
        .chain_stmt => {
            try appendLiteral(buf, allocator, "CHAIN ");
            try buf.append(allocator, '"');
            try buf.appendSlice(allocator, stmt.data.chain_stmt.path);
            try buf.append(allocator, '"');
        },
        .bye_stmt => try appendLiteral(buf, allocator, "BYE"),
    }
}

fn emitExpr(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, expr: ast.ExprRef) EmitError!void {
    switch (expr.tag) {
        .number => try appendNumber(buf, allocator, expr.data.number),
        .variable => try appendVar(buf, allocator, expr.data.variable),
        .unary => {
            const payload = expr.data.unary;
            try appendUnaryOp(buf, allocator, payload.op);
            try emitExpr(buf, allocator, payload.expr);
        },
        .binary => {
            const payload = expr.data.binary;
            try buf.append(allocator, '(');
            try emitExpr(buf, allocator, payload.left);
            try buf.append(allocator, ' ');
            try appendBinaryOp(buf, allocator, payload.op);
            try buf.append(allocator, ' ');
            try emitExpr(buf, allocator, payload.right);
            try buf.append(allocator, ')');
        },
        .peek => {
            try appendLiteral(buf, allocator, "PEEK(");
            try emitExpr(buf, allocator, expr.data.peek);
            try buf.append(allocator, ')');
        },
    }
}

fn appendNumber(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i32) EmitError!void {
    var temp: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&temp, "{}", .{value}) catch return error.OutOfMemory;
    try buf.appendSlice(allocator, s);
}

fn appendVar(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, idx: u8) EmitError!void {
    const c: u8 = @intCast('A' + idx);
    try buf.append(allocator, c);
}

fn appendRelop(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, op: ast.RelOp) EmitError!void {
    switch (op) {
        .equal => try appendLiteral(buf, allocator, "="),
        .less => try appendLiteral(buf, allocator, "<"),
        .less_equal => try appendLiteral(buf, allocator, "<="),
        .greater => try appendLiteral(buf, allocator, ">"),
        .greater_equal => try appendLiteral(buf, allocator, ">="),
        .not_equal => try appendLiteral(buf, allocator, "<>"),
    }
}

fn appendUnaryOp(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, op: ast.UnaryOp) EmitError!void {
    switch (op) {
        .plus => try appendLiteral(buf, allocator, "+"),
        .minus => try appendLiteral(buf, allocator, "-"),
    }
}

fn appendBinaryOp(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, op: ast.BinaryOp) EmitError!void {
    switch (op) {
        .add => try appendLiteral(buf, allocator, "+"),
        .sub => try appendLiteral(buf, allocator, "-"),
        .mul => try appendLiteral(buf, allocator, "*"),
        .div => try appendLiteral(buf, allocator, "/"),
    }
}

fn appendLiteral(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) EmitError!void {
    try buf.appendSlice(allocator, text);
}

test "emit simple program" {
    const parser = @import("parser.zig");
    const src =
        "10 LET A=1\n" ++
        "20 PRINT \"HI\",A\n" ++
        "30 END\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parser.parseProgram(arena.allocator(), src);
    const out = try emitProgram(arena.allocator(), program);
    try std.testing.expect(std.mem.eql(u8, out, "10 LET A = 1\n" ++
        "20 PRINT \"HI\", A\n" ++
        "30 END\n"));
}

test "emit data read poke call" {
    const parser = @import("parser.zig");
    const src =
        "10 DATA 1,2,3\n" ++
        "20 READ A,B\n" ++
        "30 POKE 10,20\n" ++
        "40 CALL 1\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parser.parseProgram(arena.allocator(), src);
    const out = try emitProgram(arena.allocator(), program);
    try std.testing.expect(std.mem.eql(u8, out, "10 DATA 1, 2, 3\n" ++
        "20 READ A, B\n" ++
        "30 POKE 10, 20\n" ++
        "40 CALL 1\n"));
}
