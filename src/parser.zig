// =============================================================================
// Project : tinybasic
// File    : tinybasic\src\parser.zig
// Author  : Ilija Mandic
// Purpose : Parser that converts token streams into TinyBASIC AST nodes.
// =============================================================================
const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");

pub const ParseError = error{
    UnexpectedToken,
    ExpectedExpression,
    ExpectedStatement,
    UnexpectedEof,
    InvalidVariable,
    InvalidRelOp,
} || lexer.LexError || std.mem.Allocator.Error;

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lex: lexer.Lexer,
    current: lexer.Token,
    peeked: ?lexer.Token,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) ParseError!Parser {
        var lex = lexer.Lexer.init(source);
        const first = try lex.next();
        return Parser{
            .allocator = allocator,
            .lex = lex,
            .current = first,
            .peeked = null,
        };
    }

    pub fn parseProgram(self: *Parser) ParseError!ast.Program {
        var lines: std.ArrayList(ast.Line) = .empty;
        while (true) {
            while (self.current.tag == .newline) {
                try self.advance();
            }
            if (self.current.tag == .eof) break;

            const line_token = self.current;
            var line_number: ?i32 = null;
            if (self.current.tag == .number) {
                line_number = self.current.int_value;
                try self.advance();
            }

            var stmt: ?*ast.Stmt = null;
            if (self.current.tag != .newline and self.current.tag != .eof) {
                stmt = try self.parseStatement();
            }

            if (self.current.tag == .newline) {
                try self.advance();
            } else if (self.current.tag != .eof) {
                return ParseError.UnexpectedToken;
            }

            try lines.append(self.allocator, ast.Line{
                .number = line_number,
                .stmt = stmt,
                .line = line_token.line,
                .column = line_token.column,
            });
        }

        return ast.Program{ .lines = try lines.toOwnedSlice(self.allocator) };
    }

    fn parseStatement(self: *Parser) ParseError!*ast.Stmt {
        return switch (self.current.tag) {
            .kw_let => try self.parseLet(),
            .kw_goto => try self.parseGoto(),
            .kw_gosub => try self.parseGosub(),
            .kw_return => try self.parseReturn(),
            .kw_if => try self.parseIfThen(),
            .kw_input => try self.parseInput(),
            .kw_print => try self.parsePrint(),
            .kw_data => try self.parseData(),
            .kw_read => try self.parseRead(),
            .kw_restore => try self.parseRestore(),
            .kw_poke => try self.parsePoke(),
            .kw_call => try self.parseCall(),
            .kw_end => try self.parseSimple(.end_stmt),
            .kw_list => try self.parseSimple(.list_stmt),
            .kw_run => try self.parseSimple(.run_stmt),
            .kw_clear => try self.parseSimple(.clear_stmt),
            .kw_cls => try self.parseSimple(.cls_stmt),
            .kw_save => try self.parseSave(),
            .kw_load => try self.parseLoad(),
            .kw_chain => try self.parseChain(),
            .kw_bye => try self.parseSimple(.bye_stmt),
            else => return ParseError.ExpectedStatement,
        };
    }

    fn parseLet(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const var_idx = try self.parseVariable();
        try self.consume(.equal);
        const value = try self.parseExpression();
        return try self.allocStmt(.let_stmt, .{ .let_stmt = .{ .var_index = var_idx, .value = value } });
    }

    fn parseGoto(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const target = try self.parseExpression();
        return try self.allocStmt(.goto_stmt, .{ .goto_stmt = target });
    }

    fn parseGosub(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const target = try self.parseExpression();
        return try self.allocStmt(.gosub_stmt, .{ .gosub_stmt = target });
    }

    fn parseReturn(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        return try self.allocStmt(.return_stmt, .{ .return_stmt = {} });
    }

    fn parseIfThen(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const left = try self.parseExpression();
        const op = try self.parseRelop();
        const right = try self.parseExpression();
        try self.consume(.kw_then);
        const then_stmt = try self.parseStatement();
        return try self.allocStmt(.if_then, .{ .if_then = .{ .left = left, .op = op, .right = right, .then_stmt = then_stmt } });
    }

    fn parseInput(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        var vars: std.ArrayList(u8) = .empty;
        defer vars.deinit(self.allocator);

        const first = try self.parseVariable();
        try vars.append(self.allocator, first);
        while (self.current.tag == .comma) {
            try self.advance();
            const v = try self.parseVariable();
            try vars.append(self.allocator, v);
        }

        return try self.allocStmt(.input_stmt, .{ .input_stmt = .{ .vars = try vars.toOwnedSlice(self.allocator) } });
    }

    fn parsePrint(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        var items: std.ArrayList(ast.PrintItem) = .empty;
        defer items.deinit(self.allocator);

        if (self.current.tag == .newline or self.current.tag == .eof) {
            return ParseError.ExpectedExpression;
        }

        while (true) {
            if (self.current.tag == .string) {
                const lexeme = self.current.lexeme;
                try self.advance();
                try items.append(self.allocator, .{ .string = lexeme });
            } else {
                const expr = try self.parseExpression();
                try items.append(self.allocator, .{ .expr = expr });
            }

            if (self.current.tag == .comma) {
                try self.advance();
                if (self.current.tag == .newline or self.current.tag == .eof) return ParseError.ExpectedExpression;
                continue;
            }
            break;
        }

        return try self.allocStmt(.print_stmt, .{ .print_stmt = .{ .items = try items.toOwnedSlice(self.allocator) } });
    }

    fn parseData(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        var values: std.ArrayList(i32) = .empty;
        defer values.deinit(self.allocator);

        const first = try self.parseDataValue();
        try values.append(self.allocator, first);
        while (self.current.tag == .comma) {
            try self.advance();
            const v = try self.parseDataValue();
            try values.append(self.allocator, v);
        }

        return try self.allocStmt(.data_stmt, .{ .data_stmt = .{ .values = try values.toOwnedSlice(self.allocator) } });
    }

    fn parseRead(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        var vars: std.ArrayList(u8) = .empty;
        defer vars.deinit(self.allocator);

        const first = try self.parseVariable();
        try vars.append(self.allocator, first);
        while (self.current.tag == .comma) {
            try self.advance();
            const v = try self.parseVariable();
            try vars.append(self.allocator, v);
        }

        return try self.allocStmt(.read_stmt, .{ .read_stmt = .{ .vars = try vars.toOwnedSlice(self.allocator) } });
    }

    fn parseRestore(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        return try self.allocStmt(.restore_stmt, .{ .restore_stmt = {} });
    }

    fn parsePoke(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const addr = try self.parseExpression();
        try self.consume(.comma);
        const value = try self.parseExpression();
        return try self.allocStmt(.poke_stmt, .{ .poke_stmt = .{ .addr = addr, .value = value } });
    }

    fn parseCall(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const target = try self.parseExpression();
        return try self.allocStmt(.call_stmt, .{ .call_stmt = .{ .target = target } });
    }

    fn parseSimple(self: *Parser, tag: ast.StmtTag) ParseError!*ast.Stmt {
        try self.advance();
        return switch (tag) {
            .end_stmt => try self.allocStmt(tag, .{ .end_stmt = {} }),
            .list_stmt => try self.allocStmt(tag, .{ .list_stmt = {} }),
            .run_stmt => try self.allocStmt(tag, .{ .run_stmt = {} }),
            .clear_stmt => try self.allocStmt(tag, .{ .clear_stmt = {} }),
            .cls_stmt => try self.allocStmt(tag, .{ .cls_stmt = {} }),
            .bye_stmt => try self.allocStmt(tag, .{ .bye_stmt = {} }),
            else => return ParseError.ExpectedStatement,
        };
    }

    fn parseSave(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const path = try self.parseStringLiteral();
        return try self.allocStmt(.save_stmt, .{ .save_stmt = .{ .path = path } });
    }

    fn parseLoad(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const path = try self.parseStringLiteral();
        return try self.allocStmt(.load_stmt, .{ .load_stmt = .{ .path = path } });
    }

    fn parseChain(self: *Parser) ParseError!*ast.Stmt {
        try self.advance();
        const path = try self.parseStringLiteral();
        return try self.allocStmt(.chain_stmt, .{ .chain_stmt = .{ .path = path } });
    }

    fn parseExpression(self: *Parser) ParseError!ast.ExprRef {
        var expr = try self.parseTerm();
        while (self.current.tag == .plus or self.current.tag == .minus) {
            const op_tag = self.current.tag;
            try self.advance();
            const right = try self.parseTerm();
            const op: ast.BinaryOp = if (op_tag == .plus) .add else .sub;
            expr = try self.allocExpr(.binary, .{ .binary = .{ .op = op, .left = expr, .right = right } });
        }
        return expr;
    }

    fn parseTerm(self: *Parser) ParseError!ast.ExprRef {
        var expr = try self.parseUnary();
        while (self.current.tag == .star or self.current.tag == .slash) {
            const op_tag = self.current.tag;
            try self.advance();
            const right = try self.parseUnary();
            const op: ast.BinaryOp = if (op_tag == .star) .mul else .div;
            expr = try self.allocExpr(.binary, .{ .binary = .{ .op = op, .left = expr, .right = right } });
        }
        return expr;
    }

    fn parseUnary(self: *Parser) ParseError!ast.ExprRef {
        if (self.current.tag == .plus or self.current.tag == .minus) {
            const op_tag = self.current.tag;
            try self.advance();
            const inner = try self.parseUnary();
            const op: ast.UnaryOp = if (op_tag == .plus) .plus else .minus;
            return try self.allocExpr(.unary, .{ .unary = .{ .op = op, .expr = inner } });
        }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *Parser) ParseError!ast.ExprRef {
        switch (self.current.tag) {
            .number => {
                const value = self.current.int_value orelse return ParseError.ExpectedExpression;
                try self.advance();
                return try self.allocExpr(.number, .{ .number = value });
            },
            .identifier => {
                const idx = try self.parseVariable();
                return try self.allocExpr(.variable, .{ .variable = idx });
            },
            .kw_peek => {
                try self.advance();
                try self.consume(.lparen);
                const addr = try self.parseExpression();
                try self.consume(.rparen);
                return try self.allocExpr(.peek, .{ .peek = addr });
            },
            .lparen => {
                try self.advance();
                const expr = try self.parseExpression();
                try self.consume(.rparen);
                return expr;
            },
            else => return ParseError.ExpectedExpression,
        }
    }

    fn parseRelop(self: *Parser) ParseError!ast.RelOp {
        const op = switch (self.current.tag) {
            .equal => ast.RelOp.equal,
            .less => ast.RelOp.less,
            .less_equal => ast.RelOp.less_equal,
            .greater => ast.RelOp.greater,
            .greater_equal => ast.RelOp.greater_equal,
            .not_equal => ast.RelOp.not_equal,
            else => return ParseError.InvalidRelOp,
        };
        try self.advance();
        return op;
    }

    fn parseVariable(self: *Parser) ParseError!u8 {
        if (self.current.tag != .identifier) return ParseError.InvalidVariable;
        const name = self.current.lexeme;
        if (name.len != 1) return ParseError.InvalidVariable;
        const c = name[0];
        if (!isAlpha(c)) return ParseError.InvalidVariable;
        const idx: u8 = @intCast(std.ascii.toUpper(c) - 'A');
        try self.advance();
        return idx;
    }

    fn consume(self: *Parser, tag: lexer.TokenTag) ParseError!void {
        if (self.current.tag != tag) return ParseError.UnexpectedToken;
        try self.advance();
    }

    fn parseStringLiteral(self: *Parser) ParseError![]const u8 {
        if (self.current.tag != .string) return ParseError.UnexpectedToken;
        const value = self.current.lexeme;
        try self.advance();
        return value;
    }

    fn parseDataValue(self: *Parser) ParseError!i32 {
        var sign: i32 = 1;
        if (self.current.tag == .plus or self.current.tag == .minus) {
            if (self.current.tag == .minus) sign = -1;
            try self.advance();
        }
        if (self.current.tag != .number) return ParseError.ExpectedExpression;
        const value = self.current.int_value orelse return ParseError.ExpectedExpression;
        try self.advance();
        return value * sign;
    }

    fn advance(self: *Parser) ParseError!void {
        self.current = if (self.peeked) |tok| blk: {
            self.peeked = null;
            break :blk tok;
        } else try self.lex.next();
    }

    fn peek(self: *Parser) ParseError!lexer.Token {
        if (self.peeked) |tok| return tok;
        const tok = try self.lex.next();
        self.peeked = tok;
        return tok;
    }

    fn allocExpr(self: *Parser, tag: ast.ExprTag, data: ast.ExprData) ParseError!ast.ExprRef {
        const node = try self.allocator.create(ast.Expr);
        node.* = ast.Expr{ .tag = tag, .data = data };
        return node;
    }

    fn allocStmt(self: *Parser, tag: ast.StmtTag, data: ast.StmtData) ParseError!*ast.Stmt {
        const node = try self.allocator.create(ast.Stmt);
        node.* = ast.Stmt{ .tag = tag, .data = data };
        return node;
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

pub fn parseProgram(allocator: std.mem.Allocator, source: []const u8) ParseError!ast.Program {
    var parser = try Parser.init(allocator, source);
    return parser.parseProgram();
}

test "parse simple program" {
    const src =
        "10 LET A=1\n" ++
        "20 PRINT \"HI\",A\n" ++
        "30 END\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parseProgram(arena.allocator(), src);
    try std.testing.expectEqual(@as(usize, 3), program.lines.len);
    try std.testing.expectEqual(@as(?i32, 10), program.lines[0].number);
    try std.testing.expectEqual(ast.StmtTag.let_stmt, program.lines[0].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.print_stmt, program.lines[1].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.end_stmt, program.lines[2].stmt.?.tag);
}

test "parse if then" {
    const src = "10 IF A < 10 THEN PRINT A\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parseProgram(arena.allocator(), src);
    try std.testing.expectEqual(@as(usize, 1), program.lines.len);
    const stmt = program.lines[0].stmt.?;
    try std.testing.expectEqual(ast.StmtTag.if_then, stmt.tag);
    const payload = stmt.data.if_then;
    try std.testing.expectEqual(ast.RelOp.less, payload.op);
    try std.testing.expectEqual(ast.StmtTag.print_stmt, payload.then_stmt.tag);
}

test "parse input list" {
    const src = "10 INPUT A,B,C\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parseProgram(arena.allocator(), src);
    const stmt = program.lines[0].stmt.?;
    try std.testing.expectEqual(ast.StmtTag.input_stmt, stmt.tag);
    try std.testing.expectEqual(@as(usize, 3), stmt.data.input_stmt.vars.len);
}

test "rejects invalid variable" {
    const src = "10 LET ABC=1\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(ParseError.InvalidVariable, parseProgram(arena.allocator(), src));
}

test "parse save load bye" {
    const src =
        "10 SAVE \"a.bas\"\n" ++
        "20 LOAD \"b.bas\"\n" ++
        "30 CHAIN \"c.bas\"\n" ++
        "40 BYE\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parseProgram(arena.allocator(), src);
    try std.testing.expectEqual(@as(usize, 4), program.lines.len);
    try std.testing.expectEqual(ast.StmtTag.save_stmt, program.lines[0].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.load_stmt, program.lines[1].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.chain_stmt, program.lines[2].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.bye_stmt, program.lines[3].stmt.?.tag);
}

test "parse data read restore poke call peek" {
    const src =
        "10 DATA 1,2,&HFF\n" ++
        "20 READ A,B\n" ++
        "30 RESTORE\n" ++
        "40 POKE 10,20\n" ++
        "50 CALL 1\n" ++
        "60 LET A=PEEK(10)\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const program = try parseProgram(arena.allocator(), src);
    try std.testing.expectEqual(@as(usize, 6), program.lines.len);
    try std.testing.expectEqual(ast.StmtTag.data_stmt, program.lines[0].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.read_stmt, program.lines[1].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.restore_stmt, program.lines[2].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.poke_stmt, program.lines[3].stmt.?.tag);
    try std.testing.expectEqual(ast.StmtTag.call_stmt, program.lines[4].stmt.?.tag);
    const let_stmt = program.lines[5].stmt.?;
    try std.testing.expectEqual(ast.StmtTag.let_stmt, let_stmt.tag);
    const value = let_stmt.data.let_stmt.value;
    try std.testing.expectEqual(ast.ExprTag.peek, value.tag);
}
