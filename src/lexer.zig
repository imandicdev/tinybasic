const std = @import("std");

pub const TokenTag = enum {
    eof,
    newline,

    identifier,
    number,
    string,

    kw_let,
    kw_goto,
    kw_gosub,
    kw_return,
    kw_if,
    kw_then,
    kw_input,
    kw_print,
    kw_end,
    kw_list,
    kw_run,
    kw_clear,
    kw_cls,
    kw_data,
    kw_read,
    kw_restore,
    kw_poke,
    kw_peek,
    kw_call,
    kw_save,
    kw_load,
    kw_chain,
    kw_bye,

    plus,
    minus,
    star,
    slash,
    equal,
    less,
    greater,
    less_equal,
    greater_equal,
    not_equal,
    comma,
    lparen,
    rparen,
};

pub const Token = struct {
    tag: TokenTag,
    lexeme: []const u8,
    line: u32,
    column: u32,
    int_value: ?i32 = null,
};

pub const LexError = error{
    InvalidCharacter,
    UnterminatedString,
    NumberTooLarge,
};

pub const Lexer = struct {
    source: []const u8,
    index: usize,
    line: u32,
    column: u32,

    pub fn init(source: []const u8) Lexer {
        return Lexer{
            .source = source,
            .index = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn next(self: *Lexer) LexError!Token {
        self.skipWhitespace();

        const start_index = self.index;
        const start_line = self.line;
        const start_col = self.column;

        if (self.index >= self.source.len) {
            return Token{ .tag = .eof, .lexeme = "", .line = start_line, .column = start_col };
        }

        const c = self.source[self.index];
        if (c == '\n' or c == '\r') {
            self.consumeNewline();
            return Token{ .tag = .newline, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
        }

        if (isAlpha(c)) {
            _ = self.advance();
            while (self.peek()) |p| {
                if (!isIdentChar(p)) break;
                _ = self.advance();
            }
            const lexeme = self.source[start_index..self.index];
            const tag = keywordTag(lexeme) orelse .identifier;
            return Token{ .tag = tag, .lexeme = lexeme, .line = start_line, .column = start_col };
        }

        if (std.ascii.isDigit(c) or (c == '&' and self.peekNextIsHex())) {
            const value = try self.readNumber();
            const lexeme = self.source[start_index..self.index];
            return Token{ .tag = .number, .lexeme = lexeme, .line = start_line, .column = start_col, .int_value = value };
        }

        switch (c) {
            '"' => {
                const value = try self.readString();
                return Token{ .tag = .string, .lexeme = value, .line = start_line, .column = start_col };
            },
            '+' => {
                _ = self.advance();
                return Token{ .tag = .plus, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '-' => {
                _ = self.advance();
                return Token{ .tag = .minus, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '*' => {
                _ = self.advance();
                return Token{ .tag = .star, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '/' => {
                _ = self.advance();
                return Token{ .tag = .slash, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            ',' => {
                _ = self.advance();
                return Token{ .tag = .comma, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '(' => {
                _ = self.advance();
                return Token{ .tag = .lparen, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            ')' => {
                _ = self.advance();
                return Token{ .tag = .rparen, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '=' => {
                _ = self.advance();
                return Token{ .tag = .equal, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '<' => {
                _ = self.advance();
                if (self.match('=')) {
                    return Token{ .tag = .less_equal, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
                }
                if (self.match('>')) {
                    return Token{ .tag = .not_equal, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
                }
                return Token{ .tag = .less, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            '>' => {
                _ = self.advance();
                if (self.match('=')) {
                    return Token{ .tag = .greater_equal, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
                }
                if (self.match('<')) {
                    return Token{ .tag = .not_equal, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
                }
                return Token{ .tag = .greater, .lexeme = self.source[start_index..self.index], .line = start_line, .column = start_col };
            },
            else => return LexError.InvalidCharacter,
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.index < self.source.len) {
            const c = self.source[self.index];
            if (c == ' ' or c == '\t') {
                _ = self.advance();
                continue;
            }
            if (c == '\r' or c == '\n') break;
            break;
        }
    }

    fn consumeNewline(self: *Lexer) void {
        if (self.source[self.index] == '\r') {
            _ = self.advanceRaw();
            if (self.index < self.source.len and self.source[self.index] == '\n') {
                _ = self.advanceRaw();
            }
        } else if (self.source[self.index] == '\n') {
            _ = self.advanceRaw();
        }
        self.line += 1;
        self.column = 1;
    }

    fn readString(self: *Lexer) LexError![]const u8 {
        _ = self.advance();
        const start = self.index;
        while (self.index < self.source.len and self.source[self.index] != '"') {
            if (self.source[self.index] == '\n' or self.source[self.index] == '\r') {
                return LexError.UnterminatedString;
            }
            _ = self.advance();
        }
        if (self.index >= self.source.len) return LexError.UnterminatedString;
        const slice = self.source[start..self.index];
        _ = self.advance();
        return slice;
    }

    fn readNumber(self: *Lexer) LexError!i32 {
        if (self.peekHexPrefix()) {
            return self.readHexNumber();
        }
        var value: i32 = 0;
        while (self.index < self.source.len and std.ascii.isDigit(self.source[self.index])) {
            const digit: i32 = @intCast(self.source[self.index] - '0');
            if (value > @divTrunc((@as(i32, std.math.maxInt(i32)) - digit), 10)) {
                return LexError.NumberTooLarge;
            }
            value = value * 10 + digit;
            _ = self.advance();
        }
        return value;
    }

    fn readHexNumber(self: *Lexer) LexError!i32 {
        self.advanceHexPrefix();
        var value: i32 = 0;
        var any = false;
        while (self.index < self.source.len) {
            const c = self.source[self.index];
            const digit = hexValue(c) orelse break;
            any = true;
            if (value > @divTrunc((@as(i32, std.math.maxInt(i32)) - digit), 16)) {
                return LexError.NumberTooLarge;
            }
            value = value * 16 + digit;
            _ = self.advance();
        }
        if (!any) return LexError.InvalidCharacter;
        return value;
    }

    fn peekHexPrefix(self: *Lexer) bool {
        if (self.index >= self.source.len) return false;
        const c = self.source[self.index];
        if (c == '&') {
            if (self.index + 1 >= self.source.len) return false;
            const h = self.source[self.index + 1];
            return h == 'H' or h == 'h';
        }
        if (c == '0' and self.index + 1 < self.source.len) {
            const x = self.source[self.index + 1];
            return x == 'x' or x == 'X';
        }
        return false;
    }

    fn peekNextIsHex(self: *Lexer) bool {
        if (self.index + 1 >= self.source.len) return false;
        return self.source[self.index] == '&' and (self.source[self.index + 1] == 'H' or self.source[self.index + 1] == 'h');
    }

    fn advanceHexPrefix(self: *Lexer) void {
        if (self.source[self.index] == '&') {
            _ = self.advance();
            _ = self.advance();
            return;
        }
        if (self.source[self.index] == '0' and self.index + 1 < self.source.len) {
            _ = self.advance();
            _ = self.advance();
        }
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.index];
        self.index += 1;
        self.column += 1;
        return c;
    }

    fn advanceRaw(self: *Lexer) u8 {
        const c = self.source[self.index];
        self.index += 1;
        return c;
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.index >= self.source.len) return null;
        return self.source[self.index];
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.index >= self.source.len) return false;
        if (self.source[self.index] != expected) return false;
        _ = self.advance();
        return true;
    }
};

const keyword_map = std.StaticStringMap(TokenTag).initComptime(.{
    .{ "LET", .kw_let },
    .{ "GOTO", .kw_goto },
    .{ "GOSUB", .kw_gosub },
    .{ "RETURN", .kw_return },
    .{ "IF", .kw_if },
    .{ "THEN", .kw_then },
    .{ "INPUT", .kw_input },
    .{ "PRINT", .kw_print },
    .{ "END", .kw_end },
    .{ "LIST", .kw_list },
    .{ "RUN", .kw_run },
    .{ "CLEAR", .kw_clear },
    .{ "CLS", .kw_cls },
    .{ "DATA", .kw_data },
    .{ "READ", .kw_read },
    .{ "RESTORE", .kw_restore },
    .{ "POKE", .kw_poke },
    .{ "PEEK", .kw_peek },
    .{ "CALL", .kw_call },
    .{ "SAVE", .kw_save },
    .{ "LOAD", .kw_load },
    .{ "CHAIN", .kw_chain },
    .{ "BYE", .kw_bye },
});

fn keywordTag(lexeme: []const u8) ?TokenTag {
    var buf: [16]u8 = undefined;
    if (lexeme.len == 0 or lexeme.len > buf.len) return null;
    for (lexeme, 0..) |c, i| {
        buf[i] = std.ascii.toUpper(c);
    }
    return keyword_map.get(buf[0..lexeme.len]);
}

fn isAlpha(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

fn isIdentChar(c: u8) bool {
    return isAlpha(c) or std.ascii.isDigit(c);
}

fn hexValue(c: u8) ?i32 {
    if (c >= '0' and c <= '9') return @intCast(c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(c - 'A' + 10);
    return null;
}

fn collectTags(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList(TokenTag) {
    var lexer = Lexer.init(source);
    var tags: std.ArrayList(TokenTag) = .empty;
    while (true) {
        const tok = try lexer.next();
        try tags.append(allocator, tok.tag);
        if (tok.tag == .eof) break;
    }
    return tags;
}

fn expectTags(actual: []const TokenTag, expected: []const TokenTag) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    var i: usize = 0;
    while (i < expected.len) : (i += 1) {
        try std.testing.expectEqual(expected[i], actual[i]);
    }
}

test "lexes keywords and identifiers" {
    const src = "LET A=1\nGOTO 10\nPRINT A";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);

    const expected = [_]TokenTag{
        .kw_let,  .identifier, .equal,   .number,   .newline,
        .kw_goto, .number,     .newline, .kw_print, .identifier,
        .eof,
    };
    try expectTags(tags.items, &expected);
}

test "lexes cls alias" {
    const src = "CLS\nCLEAR\n";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);

    const expected = [_]TokenTag{ .kw_cls, .newline, .kw_clear, .newline, .eof };
    try expectTags(tags.items, &expected);
}

test "lexes data read poke peek call" {
    const src = "DATA 1\nREAD A\nPOKE 10,20\nPRINT PEEK(10)\nCALL 1\n";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);

    const expected = [_]TokenTag{
        .kw_data, .number,     .newline,
        .kw_read, .identifier, .newline,
        .kw_poke, .number,     .comma,
        .number,  .newline,    .kw_print,
        .kw_peek, .lparen,     .number,
        .rparen,  .newline,    .kw_call,
        .number,  .newline,    .eof,
    };
    try expectTags(tags.items, &expected);
}

test "lexes hex numbers" {
    const src = "&HFF 0x10";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);
    const expected = [_]TokenTag{ .number, .number, .eof };
    try expectTags(tags.items, &expected);
}

test "lexes strings and commas" {
    const src = "PRINT \"HI\",A";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);

    const expected = [_]TokenTag{ .kw_print, .string, .comma, .identifier, .eof };
    try expectTags(tags.items, &expected);
}

test "lexes relops" {
    const src = "A<1 A<=1 A<>1 A><1 A>1 A>=1 A=1";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);

    const expected = [_]TokenTag{
        .identifier, .less,          .number,
        .identifier, .less_equal,    .number,
        .identifier, .not_equal,     .number,
        .identifier, .not_equal,     .number,
        .identifier, .greater,       .number,
        .identifier, .greater_equal, .number,
        .identifier, .equal,         .number,
        .eof,
    };
    try expectTags(tags.items, &expected);
}

test "handles windows newlines" {
    const src = "10 PRINT 1\r\n20 END\r\n";
    var tags = try collectTags(std.testing.allocator, src);
    defer tags.deinit(std.testing.allocator);

    const expected = [_]TokenTag{
        .number, .kw_print, .number,  .newline,
        .number, .kw_end,   .newline, .eof,
    };
    try expectTags(tags.items, &expected);
}

test "rejects invalid character" {
    var lexer = Lexer.init("@");
    try std.testing.expectError(LexError.InvalidCharacter, lexer.next());
}

test "rejects unterminated string" {
    var lexer = Lexer.init("PRINT \"HI");
    _ = try lexer.next();
    try std.testing.expectError(LexError.UnterminatedString, lexer.next());
}

test "rejects integer overflow" {
    var lexer = Lexer.init("2147483648");
    try std.testing.expectError(LexError.NumberTooLarge, lexer.next());
}
