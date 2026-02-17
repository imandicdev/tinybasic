// =============================================================================
// Project : tinybasic
// File    : tinybasic\src\il.zig
// Author  : Ilija Mandic
// Purpose : IL assembler, opcode mapping, and label resolution logic.
// =============================================================================
const std = @import("std");

pub const Operand = union(enum) {
    none,
    label: []const u8,
    label_string: struct {
        label: []const u8,
        text: []const u8,
    },
    number: i32,
    string: []const u8,
};

pub const Instruction = struct {
    mnemonic: []const u8,
    operand: Operand,
    line_no: usize,
};

pub const Opcode = enum {
    TST,
    CALL,
    RTN,
    DONE,
    JMP,
    PRS,
    PRN,
    SPC,
    NLINE,
    NXT,
    XFER,
    SAV,
    RSTR,
    CMPR,
    INNUM,
    FIN,
    ERR,
    ADD,
    SUB,
    NEG,
    MUL,
    DIV,
    STORE,
    TSTV,
    TSTN,
    IND,
    LST,
    INIT,
    GETLINE,
    TSTL,
    INSRT,
    XINIT,
    LIT,
    SAVE,
    LOAD,
    CHAIN,
    BYE,
    CLS,
    DATA,
    RDAT,
    REST,
    POKE,
    PEEK,
    BCALL,
};

pub const AsmOperand = union(enum) {
    none,
    addr: usize,
    addr_string: struct {
        addr: usize,
        text: []const u8,
    },
    number: i32,
    string: []const u8,
};

pub const AssembledInstruction = struct {
    opcode: Opcode,
    operand: AsmOperand,
    line_no: usize,
};

pub const AssembledProgram = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    source_buf: ?[]u8,
    instructions: std.ArrayList(AssembledInstruction),
    labels: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) AssembledProgram {
        return AssembledProgram{
            .allocator = allocator,
            .source = source,
            .source_buf = null,
            .instructions = .empty,
            .labels = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn initOwned(allocator: std.mem.Allocator, source_buf: []u8) AssembledProgram {
        return AssembledProgram{
            .allocator = allocator,
            .source = source_buf,
            .source_buf = source_buf,
            .instructions = .empty,
            .labels = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *AssembledProgram) void {
        self.instructions.deinit(self.allocator);
        self.labels.deinit();
        if (self.source_buf) |buf| self.allocator.free(buf);
    }
};

pub const Program = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    instructions: std.ArrayList(Instruction),
    labels: std.StringHashMap(usize),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Program {
        return Program{
            .allocator = allocator,
            .source = source,
            .instructions = .empty,
            .labels = std.StringHashMap(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Program) void {
        self.instructions.deinit(self.allocator);
        self.labels.deinit();
    }
};

pub fn parseProgram(allocator: std.mem.Allocator, source: []const u8) !Program {
    var program = Program.init(allocator, source);
    var it = std.mem.splitScalar(u8, source, '\n');
    var line_no: usize = 0;

    while (it.next()) |raw_line| {
        line_no += 1;
        var line = std.mem.trim(u8, raw_line, " \t\r");
        if (line_no == 1) {
            line = stripBom(line);
        }
        if (line.len == 0) continue;

        if (std.mem.indexOfScalar(u8, line, ';')) |comment_idx| {
            line = std.mem.trimRight(u8, line[0..comment_idx], " \t");
            if (line.len == 0) continue;
        }

        if (std.mem.indexOfScalar(u8, line, ':')) |colon_idx| {
            const left = std.mem.trim(u8, line[0..colon_idx], " \t");
            const right = std.mem.trim(u8, line[colon_idx + 1 ..], " \t");
            if (left.len != 0) {
                // Label points to next instruction index.
                try program.labels.put(left, program.instructions.items.len);
            }
            line = right;
        }

        if (line.len == 0) {
            // Label-only line; allowed.
            continue;
        }

        const mnemonic = readToken(line, 0) orelse return error.InvalidMnemonic;
        const rest = std.mem.trimLeft(u8, line[mnemonic.end..], " \t");
        const canonical = normalizeMnemonic(mnemonic.token);
        const operand = try parseOperand(canonical, rest);

        try program.instructions.append(program.allocator, Instruction{
            .mnemonic = canonical,
            .operand = operand,
            .line_no = line_no,
        });
    }

    return program;
}

fn stripBom(line: []const u8) []const u8 {
    if (line.len >= 3 and line[0] == 0xEF and line[1] == 0xBB and line[2] == 0xBF) {
        return line[3..];
    }
    return line;
}

pub fn assemble(allocator: std.mem.Allocator, source: []const u8) !AssembledProgram {
    return assembleInternal(allocator, source, null);
}

pub fn assembleFromFile(allocator: std.mem.Allocator, path: []const u8) !AssembledProgram {
    const max_bytes = 1024 * 1024;
    const buf = try std.fs.cwd().readFileAlloc(allocator, path, max_bytes);
    return assembleInternal(allocator, buf, buf);
}

fn assembleInternal(allocator: std.mem.Allocator, source: []const u8, source_buf: ?[]u8) !AssembledProgram {
    var parsed = try parseProgram(allocator, source);
    defer parsed.deinit();

    var assembled = if (source_buf) |buf| AssembledProgram.initOwned(allocator, buf) else AssembledProgram.init(allocator, source);
    try assembled.instructions.ensureTotalCapacity(allocator, parsed.instructions.items.len);

    for (parsed.instructions.items) |inst| {
        const opcode = try opcodeFromMnemonic(inst.mnemonic);
        const operand = try resolveOperand(opcode, inst.operand, &parsed);
        try assembled.instructions.append(allocator, .{
            .opcode = opcode,
            .operand = operand,
            .line_no = inst.line_no,
        });
    }

    assembled.labels = parsed.labels;
    parsed.labels = std.StringHashMap(usize).init(allocator);

    return assembled;
}

fn opcodeFromMnemonic(mnemonic: []const u8) !Opcode {
    var buf: [16]u8 = undefined;
    if (mnemonic.len == 0 or mnemonic.len > buf.len) return error.InvalidMnemonic;
    for (mnemonic, 0..) |c, i| {
        buf[i] = std.ascii.toUpper(c);
    }
    const key = buf[0..mnemonic.len];
    return opcode_map.get(key) orelse error.InvalidMnemonic;
}

const opcode_map = std.StaticStringMap(Opcode).initComptime(.{
    .{ "TST", .TST },
    .{ "CALL", .CALL },
    .{ "RTN", .RTN },
    .{ "DONE", .DONE },
    .{ "JMP", .JMP },
    .{ "PRS", .PRS },
    .{ "PRN", .PRN },
    .{ "SPC", .SPC },
    .{ "NLINE", .NLINE },
    .{ "NXT", .NXT },
    .{ "XFER", .XFER },
    .{ "SAV", .SAV },
    .{ "RSTR", .RSTR },
    .{ "CMPR", .CMPR },
    .{ "INNUM", .INNUM },
    .{ "FIN", .FIN },
    .{ "ERR", .ERR },
    .{ "ADD", .ADD },
    .{ "SUB", .SUB },
    .{ "NEG", .NEG },
    .{ "MUL", .MUL },
    .{ "DIV", .DIV },
    .{ "STORE", .STORE },
    .{ "TSTV", .TSTV },
    .{ "TSTN", .TSTN },
    .{ "IND", .IND },
    .{ "LST", .LST },
    .{ "INIT", .INIT },
    .{ "GETLINE", .GETLINE },
    .{ "TSTL", .TSTL },
    .{ "INSRT", .INSRT },
    .{ "XINIT", .XINIT },
    .{ "LIT", .LIT },
    .{ "SAVE", .SAVE },
    .{ "LOAD", .LOAD },
    .{ "CHAIN", .CHAIN },
    .{ "BYE", .BYE },
    .{ "CLS", .CLS },
    .{ "DATA", .DATA },
    .{ "RDAT", .RDAT },
    .{ "REST", .REST },
    .{ "POKE", .POKE },
    .{ "PEEK", .PEEK },
    .{ "BCALL", .BCALL },
});

fn resolveOperand(opcode: Opcode, operand: Operand, parsed: *const Program) !AsmOperand {
    return switch (opcode) {
        .CALL, .JMP, .TSTV, .TSTN, .TSTL => resolveLabelOperand(operand, parsed),
        .TST => resolveLabelStringOperand(operand, parsed),
        .LIT => resolveNumberOperand(operand),
        else => .none,
    };
}

fn resolveLabelOperand(operand: Operand, parsed: *const Program) !AsmOperand {
    return switch (operand) {
        .label => |lbl| .{ .addr = try lookupLabel(parsed, lbl) },
        else => error.InvalidOperand,
    };
}

fn resolveLabelStringOperand(operand: Operand, parsed: *const Program) !AsmOperand {
    return switch (operand) {
        .label_string => |ls| .{ .addr_string = .{ .addr = try lookupLabel(parsed, ls.label), .text = ls.text } },
        else => error.InvalidOperand,
    };
}

fn resolveNumberOperand(operand: Operand) !AsmOperand {
    return switch (operand) {
        .number => |n| .{ .number = n },
        else => error.InvalidOperand,
    };
}

fn lookupLabel(parsed: *const Program, label: []const u8) !usize {
    if (parsed.labels.get(label)) |addr| return addr;
    return error.UnknownLabel;
}

const TokenSlice = struct {
    token: []const u8,
    end: usize,
};

fn readToken(line: []const u8, start: usize) ?TokenSlice {
    var i = start;
    while (i < line.len and isSpace(line[i])) : (i += 1) {}
    if (i >= line.len) return null;

    const begin = i;
    while (i < line.len and isTokenChar(line[i])) : (i += 1) {}
    if (i == begin) return null;
    return TokenSlice{ .token = line[begin..i], .end = i };
}

fn parseOperand(mnemonic: []const u8, rest: []const u8) !Operand {
    if (rest.len == 0) return .none;

    if (std.ascii.eqlIgnoreCase(mnemonic, "TST")) {
        // TST lbl, 'string'
        const comma_idx = std.mem.indexOfScalar(u8, rest, ',') orelse return error.InvalidOperand;
        const lbl = std.mem.trim(u8, rest[0..comma_idx], " \t");
        const tail = std.mem.trimLeft(u8, rest[comma_idx + 1 ..], " \t");
        const str = try parseQuotedString(tail);
        return Operand{ .label_string = .{ .label = lbl, .text = str } };
    }

    if (isQuotedStart(rest[0])) {
        const str = try parseQuotedString(rest);
        return Operand{ .string = str };
    }

    if (isNumberStart(rest[0])) {
        const num = try parseNumber(rest);
        return Operand{ .number = num };
    }

    // Default: label or symbol.
    const tok = readToken(rest, 0) orelse return error.InvalidOperand;
    return Operand{ .label = tok.token };
}

fn normalizeMnemonic(mnemonic: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(mnemonic, "ICALL")) return "CALL";
    if (std.ascii.eqlIgnoreCase(mnemonic, "IJMP")) return "JMP";
    if (std.ascii.eqlIgnoreCase(mnemonic, "HOP")) return "JMP";
    if (std.ascii.eqlIgnoreCase(mnemonic, "GETLN")) return "GETLINE";
    if (std.ascii.eqlIgnoreCase(mnemonic, "MPY")) return "MUL";
    if (std.ascii.eqlIgnoreCase(mnemonic, "XPER")) return "XFER";
    return mnemonic;
}

fn parseQuotedString(text: []const u8) ![]const u8 {
    if (text.len < 2) return error.InvalidOperand;
    const quote = text[0];
    if (!isQuotedStart(quote)) return error.InvalidOperand;

    var i: usize = 1;
    while (i < text.len and text[i] != quote) : (i += 1) {}
    if (i >= text.len) return error.InvalidOperand;

    return text[1..i];
}

fn parseNumber(text: []const u8) !i32 {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.fmt.parseInt(i32, trimmed, 10) catch return error.InvalidOperand;
}

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

fn isTokenChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.';
}

fn isQuotedStart(c: u8) bool {
    return c == '\'' or c == '"';
}

fn isNumberStart(c: u8) bool {
    return (c >= '0' and c <= '9') or c == '-';
}

test "parse IL program minimal" {
    const src =
        "START: INIT\n" ++
        "NLINE\n" ++
        "CO: GETLN\n" ++
        "TSTL XEC\n" ++
        "INSRT\n" ++
        "IJMP CO\n" ++
        "S1: TST S2, 'LET'\n" ++
        "ICALL EXPR\n" ++
        "DONE\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var prog = try parseProgram(arena.allocator(), src);
    defer prog.deinit();

    try std.testing.expectEqual(@as(usize, 9), prog.instructions.items.len);
    try std.testing.expect(prog.labels.contains("START"));
    try std.testing.expect(prog.labels.contains("CO"));
    try std.testing.expect(prog.labels.contains("S1"));
    try std.testing.expect(std.ascii.eqlIgnoreCase(prog.instructions.items[2].mnemonic, "GETLINE"));
    try std.testing.expect(std.ascii.eqlIgnoreCase(prog.instructions.items[5].mnemonic, "JMP"));
    try std.testing.expect(std.ascii.eqlIgnoreCase(prog.instructions.items[7].mnemonic, "CALL"));
}

test "assemble resolves labels" {
    const src =
        "START: INIT\n" ++
        "JMP END\n" ++
        "LIT 1\n" ++
        "END: FIN\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var assembled = try assemble(arena.allocator(), src);
    defer assembled.deinit();

    try std.testing.expectEqual(@as(usize, 4), assembled.instructions.items.len);
    try std.testing.expectEqual(Opcode.JMP, assembled.instructions.items[1].opcode);
    switch (assembled.instructions.items[1].operand) {
        .addr => |addr| try std.testing.expectEqual(@as(usize, 3), addr),
        else => return error.InvalidOperand,
    }
}
