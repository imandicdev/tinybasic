const std = @import("std");
const il = @import("il.zig");
const gdi_mod = @import("win32_gdi.zig");

pub const ErrorCode = enum(u8) {
    syntax = 1,
    missing_line = 2,
    line_too_large = 3,
    too_many_gosubs = 4,
    return_without_gosub = 5,
    expr_too_complex = 6,
    too_many_lines = 7,
    division_by_zero = 8,
    data_out_of_range = 9,
    bad_address = 10,
    invalid_call = 11,
};

pub const VmError = error{
    StackUnderflow,
    InvalidOperand,
    UnknownLabel,
    InputError,
    Unimplemented,
};

pub const Io = struct {
    ctx: *anyopaque,
    read_line: *const fn (*anyopaque, std.mem.Allocator, *std.ArrayList(u8)) anyerror!void,
    read_number: *const fn (*anyopaque, std.mem.Allocator) anyerror!i32,
    write: *const fn (*anyopaque, []const u8) anyerror!void,

    pub fn readLine(self: *Io, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        try self.read_line(self.ctx, allocator, out);
    }

    pub fn readNumber(self: *Io, allocator: std.mem.Allocator) !i32 {
        return try self.read_number(self.ctx, allocator);
    }

    pub fn writeAll(self: *Io, data: []const u8) !void {
        try self.write(self.ctx, data);
    }
};

pub const ConsoleIo = struct {
    in_file: std.fs.File,
    out_file: std.fs.File,
    line_reader: LineReader,

    pub fn init() ConsoleIo {
        const in_file = std.fs.File.stdin();
        const out_file = std.fs.File.stdout();
        return ConsoleIo{
            .in_file = in_file,
            .out_file = out_file,
            .line_reader = LineReader.init(in_file),
        };
    }

    pub fn toIo(self: *ConsoleIo) Io {
        return Io{
            .ctx = self,
            .read_line = consoleReadLine,
            .read_number = consoleReadNumber,
            .write = consoleWrite,
        };
    }

    fn consoleReadLine(ctx: *anyopaque, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) anyerror!void {
        const self: *ConsoleIo = @ptrCast(@alignCast(ctx));
        try self.line_reader.readLine(allocator, out);
    }

    fn consoleReadNumber(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!i32 {
        const self: *ConsoleIo = @ptrCast(@alignCast(ctx));
        var temp: std.ArrayList(u8) = .empty;
        defer temp.deinit(allocator);
        try self.line_reader.readLine(allocator, &temp);
        return std.fmt.parseInt(i32, temp.items, 10);
    }

    fn consoleWrite(ctx: *anyopaque, data: []const u8) anyerror!void {
        const self: *ConsoleIo = @ptrCast(@alignCast(ctx));
        _ = try self.out_file.writeAll(data);
    }
};

pub const BufferIo = struct {
    allocator: std.mem.Allocator,
    input_lines: std.ArrayList([]u8),
    input_numbers: std.ArrayList(i32),
    output: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) BufferIo {
        return BufferIo{
            .allocator = allocator,
            .input_lines = .empty,
            .input_numbers = .empty,
            .output = .empty,
        };
    }

    pub fn deinit(self: *BufferIo) void {
        for (self.input_lines.items) |line| {
            self.allocator.free(line);
        }
        self.input_lines.deinit(self.allocator);
        self.input_numbers.deinit(self.allocator);
        self.output.deinit(self.allocator);
    }

    pub fn toIo(self: *BufferIo) Io {
        return Io{
            .ctx = self,
            .read_line = bufferReadLine,
            .read_number = bufferReadNumber,
            .write = bufferWrite,
        };
    }

    pub fn pushLine(self: *BufferIo, line: []const u8) !void {
        const buf = try self.allocator.alloc(u8, line.len);
        @memcpy(buf, line);
        try self.input_lines.append(self.allocator, buf);
    }

    pub fn pushNumber(self: *BufferIo, value: i32) !void {
        try self.input_numbers.append(self.allocator, value);
    }

    fn bufferReadLine(ctx: *anyopaque, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) anyerror!void {
        const self: *BufferIo = @ptrCast(@alignCast(ctx));
        if (self.input_lines.items.len == 0) return error.EndOfStream;
        const line = self.input_lines.orderedRemove(0);
        defer self.allocator.free(line);
        out.clearRetainingCapacity();
        try out.appendSlice(allocator, line);
    }

    fn bufferReadNumber(ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!i32 {
        const self: *BufferIo = @ptrCast(@alignCast(ctx));
        _ = allocator;
        if (self.input_numbers.items.len == 0) return error.EndOfStream;
        return self.input_numbers.orderedRemove(0);
    }

    fn bufferWrite(ctx: *anyopaque, data: []const u8) anyerror!void {
        const self: *BufferIo = @ptrCast(@alignCast(ctx));
        try self.output.appendSlice(self.allocator, data);
    }
};

const LineReader = struct {
    file: std.fs.File,
    buffer: [256]u8,
    start: usize,
    end: usize,

    pub fn init(file: std.fs.File) LineReader {
        return LineReader{
            .file = file,
            .buffer = undefined,
            .start = 0,
            .end = 0,
        };
    }

    pub fn readLine(self: *LineReader, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        out.clearRetainingCapacity();
        while (true) {
            if (self.start == self.end) {
                const n = self.file.read(&self.buffer) catch return VmError.InputError;
                if (n == 0) return VmError.InputError;
                self.start = 0;
                self.end = n;
            }

            const slice = self.buffer[self.start..self.end];
            if (std.mem.indexOfScalar(u8, slice, '\n')) |idx| {
                try out.appendSlice(allocator, slice[0..idx]);
                self.start += idx + 1;
                break;
            }

            try out.appendSlice(allocator, slice);
            self.start = self.end;
        }
        trimRightInPlace(out, "\r\n");
    }
};

const ExecMode = enum {
    direct,
    program,
};

const Line = struct {
    number: u8,
    text: []u8,
};

const ProgramStore = struct {
    allocator: std.mem.Allocator,
    lines: std.ArrayList(Line),

    pub fn init(allocator: std.mem.Allocator) ProgramStore {
        return ProgramStore{
            .allocator = allocator,
            .lines = .empty,
        };
    }

    pub fn deinit(self: *ProgramStore) void {
        for (self.lines.items) |line| {
            self.allocator.free(line.text);
        }
        self.lines.deinit(self.allocator);
    }

    pub fn clear(self: *ProgramStore) void {
        for (self.lines.items) |line| {
            self.allocator.free(line.text);
        }
        self.lines.clearRetainingCapacity();
    }

    pub fn count(self: *const ProgramStore) usize {
        return self.lines.items.len;
    }

    pub fn getByIndex(self: *const ProgramStore, index: usize) ?Line {
        if (index >= self.lines.items.len) return null;
        return self.lines.items[index];
    }

    pub fn findIndex(self: *const ProgramStore, number: u8) usize {
        var lo: usize = 0;
        var hi: usize = self.lines.items.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const mid_num = self.lines.items[mid].number;
            if (mid_num < number) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return lo;
    }

    pub fn findExisting(self: *const ProgramStore, number: u8) ?usize {
        const idx = self.findIndex(number);
        if (idx < self.lines.items.len and self.lines.items[idx].number == number) return idx;
        return null;
    }

    pub fn insertOrDelete(self: *ProgramStore, number: u8, text: []const u8) !bool {
        const idx = self.findIndex(number);
        const exists = idx < self.lines.items.len and self.lines.items[idx].number == number;

        if (text.len == 0) {
            if (exists) {
                self.allocator.free(self.lines.items[idx].text);
                _ = self.lines.orderedRemove(idx);
            }
            return !exists;
        }

        const buf = try self.allocator.alloc(u8, text.len);
        @memcpy(buf, text);

        if (exists) {
            self.allocator.free(self.lines.items[idx].text);
            self.lines.items[idx] = Line{ .number = number, .text = buf };
            return false;
        }

        try self.lines.insert(self.allocator, idx, Line{ .number = number, .text = buf });
        return true;
    }
};

const ErrorState = struct {
    code: ErrorCode,
    line: ?u8,
};

const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
};

const Limits = struct {
    max_line_len: usize = 256,
    max_lines: usize = 255,
    max_expr_stack: usize = 64,
    max_gosub: usize = 16,
};

const MatchRule = struct {
    allow_follow_alpha: bool = true,
    allow_follow_digit: bool = true,
};

const keyword_rules = std.StaticStringMap(MatchRule).initComptime(.{
    .{ "LET", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = false } },
    .{ "GO", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "TO", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "SUB", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "PRINT", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "IF", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "THEN", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "INPUT", MatchRule{ .allow_follow_alpha = true, .allow_follow_digit = true } },
    .{ "RETURN", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "END", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "LIST", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "RUN", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "CLEAR", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "CLS", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "DATA", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "READ", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "RESTORE", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "POKE", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "CALL", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "PEEK", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "SAVE", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "LOAD", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "CHAIN", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
    .{ "BYE", MatchRule{ .allow_follow_alpha = false, .allow_follow_digit = false } },
});

pub const Vm = struct {
    allocator: std.mem.Allocator,
    io: *Io,
    limits: Limits,

    program: []const il.AssembledInstruction,
    labels: *const std.StringHashMap(usize),
    pc: usize,
    stack: std.ArrayList(i32),
    call_stack: std.ArrayList(usize),
    gosub_stack: std.ArrayList(u8),
    vars: [26]i32,
    mem: [65536]u8,
    draw_x: i32,
    data_values: std.ArrayList(i32),
    data_index: usize,
    screen: [800]u8,
    bytecode_regs: [4]u8,
    bytecode_z: bool,
    gdi: ?gdi_mod.Gdi,
    gdi_frame_active: bool,
    gdi_dirty: bool,
    halted: bool,
    error_state: ?ErrorState,
    last_il_line: usize,
    last_pc: usize,
    debug_logging: bool,

    exec_mode: ExecMode,
    current_line_index: ?usize,
    pending_line_num: ?u8,
    pending_text_start: usize,
    pending_text_len: usize,
    last_keyword: ?[]const u8,

    line_buf: std.ArrayList(u8),
    cursor: usize,
    program_store: ProgramStore,
    out_col: usize,

    label_co: usize,
    label_stmt: usize,
    label_xec: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        program: []const il.AssembledInstruction,
        labels: *const std.StringHashMap(usize),
        io: *Io,
    ) !Vm {
        return Vm{
            .allocator = allocator,
            .io = io,
            .limits = Limits{},
            .program = program,
            .labels = labels,
            .pc = 0,
            .stack = .empty,
            .call_stack = .empty,
            .gosub_stack = .empty,
            .vars = [_]i32{0} ** 26,
            .mem = [_]u8{0} ** 65536,
            .draw_x = 0,
            .data_values = .empty,
            .data_index = 0,
            .screen = [_]u8{' '} ** 800,
            .bytecode_regs = [_]u8{0} ** 4,
            .bytecode_z = false,
            .gdi = null,
            .gdi_frame_active = false,
            .gdi_dirty = false,
            .halted = false,
            .error_state = null,
            .last_il_line = 0,
            .last_pc = 0,
            .debug_logging = false,
            .exec_mode = .direct,
            .current_line_index = null,
            .pending_line_num = null,
            .pending_text_start = 0,
            .pending_text_len = 0,
            .last_keyword = null,
            .line_buf = .empty,
            .cursor = 0,
            .program_store = ProgramStore.init(allocator),
            .out_col = 0,
            .label_co = try lookupLabel(labels, "CO"),
            .label_stmt = try lookupLabel(labels, "STMT"),
            .label_xec = try lookupLabel(labels, "XEC"),
        };
    }

    pub fn deinit(self: *Vm) void {
        self.stack.deinit(self.allocator);
        self.call_stack.deinit(self.allocator);
        self.gosub_stack.deinit(self.allocator);
        self.data_values.deinit(self.allocator);
        self.line_buf.deinit(self.allocator);
        self.program_store.deinit();
        if (self.gdi) |*g| g.deinit();
    }

    pub fn clearProgram(self: *Vm) void {
        self.program_store.clear();
    }

    pub fn insertProgramLine(self: *Vm, number: u8, text: []const u8) !void {
        _ = try self.program_store.insertOrDelete(number, text);
    }

    pub fn startProgram(self: *Vm) void {
        self.stack.clearRetainingCapacity();
        self.call_stack.clearRetainingCapacity();
        self.gosub_stack.clearRetainingCapacity();
        self.vars = [_]i32{0} ** 26;
        self.error_state = null;
        self.exec_mode = .program;
        self.current_line_index = null;
        self.pending_line_num = null;
        self.pending_text_start = 0;
        self.pending_text_len = 0;
        self.last_keyword = null;
        self.line_buf.clearRetainingCapacity();
        self.cursor = 0;
        self.out_col = 0;
        self.data_index = 0;
        self.bytecode_regs = [_]u8{0} ** 4;
        self.bytecode_z = false;
        self.gdi_frame_active = false;
        self.gdi_dirty = false;
        self.halted = false;
        self.pc = self.label_xec;
    }

    pub fn programLineCount(self: *const Vm) usize {
        return self.program_store.count();
    }

    pub fn programBytesUsed(self: *const Vm) usize {
        var total: usize = 0;
        for (self.program_store.lines.items) |line| {
            total += line.text.len;
        }
        return total;
    }

    pub fn run(self: *Vm) !void {
        if (self.debug_logging) {
            try self.writeLog("run start\n");
        }
        while (!self.halted) {
            self.step() catch |err| {
                try self.logVmError(err);
                return err;
            };
        }
        if (self.debug_logging) {
            try self.writeLog("run end\n");
        }
    }

    pub fn step(self: *Vm) !void {
        if (self.pc >= self.program.len) {
            self.halted = true;
            return;
        }

        const inst = self.program[self.pc];
        self.last_pc = self.pc;
        self.last_il_line = inst.line_no;
        self.pc += 1;

        switch (inst.opcode) {
            .INIT => self.resetState(),
            .XINIT => try self.initExecution(),
            .GETLINE => try self.getLine(),
            .TST => try self.execTst(inst.operand),
            .TSTV => try self.execTstv(inst.operand),
            .TSTN => try self.execTstn(inst.operand),
            .TSTL => try self.execTstl(inst.operand),
            .DONE => try self.execDone(),
            .INSRT => try self.execInsrt(),
            .LST => try self.listProgram(),
            .NXT => try self.execNxt(),
            .XFER => try self.execXfer(),
            .SAV => try self.execSav(),
            .RSTR => try self.execRstr(),
            .SAVE => try self.execSaveProgram(),
            .LOAD => try self.execLoadProgram(),
            .CHAIN => try self.execChainProgram(),
            .BYE => self.halted = true,
            .CLS => try self.execCls(),
            .DATA => try self.execData(),
            .RDAT => try self.execReadData(),
            .REST => try self.execRestore(),
            .POKE => try self.execPoke(),
            .PEEK => try self.execPeek(),
            .BCALL => try self.execBcall(),
            .ERR => try self.raiseError(.syntax),
            .NLINE => try self.writeOut("\n"),
            .PRS => try self.execPrs(),
            .PRN => try self.execPrn(),
            .SPC => try self.execSpc(),
            .INNUM => try self.execInnum(),
            .LIT => try self.execLit(inst.operand),
            .ADD => try self.execBinaryOp(.add),
            .SUB => try self.execBinaryOp(.sub),
            .NEG => try self.execNeg(),
            .MUL => try self.execBinaryOp(.mul),
            .DIV => try self.execBinaryOp(.div),
            .CMPR => try self.execCmpr(),
            .JMP => try self.execJmp(inst.operand),
            .CALL => try self.execCall(inst.operand),
            .RTN => try self.execRtn(),
            .STORE => try self.execStore(),
            .IND => try self.execInd(),
            .FIN => self.halted = true,
        }
    }

    fn resetState(self: *Vm) void {
        self.stack.clearRetainingCapacity();
        self.call_stack.clearRetainingCapacity();
        self.gosub_stack.clearRetainingCapacity();
        self.vars = [_]i32{0} ** 26;
        @memset(self.mem[0..], 0);
        self.draw_x = 0;
        self.data_values.clearRetainingCapacity();
        self.data_index = 0;
        @memset(self.screen[0..], ' ');
        self.bytecode_regs = [_]u8{0} ** 4;
        self.bytecode_z = false;
        self.gdi_frame_active = false;
        self.gdi_dirty = false;
        self.cursor = 0;
        self.error_state = null;
        self.exec_mode = .direct;
        self.current_line_index = null;
        self.pending_line_num = null;
        self.pending_text_start = 0;
        self.pending_text_len = 0;
        self.last_keyword = null;
        self.program_store.clear();
        self.line_buf.clearRetainingCapacity();
        self.out_col = 0;
    }

    fn initExecution(self: *Vm) !void {
        self.stack.clearRetainingCapacity();
        self.cursor = 0;
        try self.buildDataTable();
        if (self.exec_mode == .program and self.current_line_index == null) {
            if (self.program_store.count() == 0) {
                self.exec_mode = .direct;
                return;
            }
            try self.loadLineByIndex(0);
        }
    }

    fn getLine(self: *Vm) !void {
        self.line_buf.clearRetainingCapacity();
        self.cursor = 0;
        self.pending_line_num = null;
        self.pending_text_start = 0;
        self.pending_text_len = 0;
        self.last_keyword = null;
        self.exec_mode = .direct;

        self.io.readLine(self.allocator, &self.line_buf) catch return VmError.InputError;
        if (self.line_buf.items.len > self.limits.max_line_len) {
            try self.raiseError(.syntax);
        }
    }

    fn execTst(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .addr_string => |as| {
                self.skipBlanks();
                if (self.matchToken(as.text)) {
                    self.cursor += as.text.len;
                    self.last_keyword = as.text;
                } else {
                    if (as.addr == self.last_pc) {
                        try self.raiseError(.syntax);
                        return;
                    }
                    self.pc = as.addr;
                }
            },
            else => return VmError.InvalidOperand,
        }
    }

    fn execTstv(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .addr => |addr| {
                self.skipBlanks();
                const c = self.peekChar() orelse {
                    if (addr == self.last_pc) {
                        try self.raiseError(.syntax);
                        return;
                    }
                    self.pc = addr;
                    return;
                };
                if (!isAlpha(c)) {
                    if (addr == self.last_pc) {
                        try self.raiseError(.syntax);
                        return;
                    }
                    self.pc = addr;
                    return;
                }
                if (self.peekCharAt(self.cursor + 1)) |next| {
                    if (isAlpha(next) or std.ascii.isDigit(next)) {
                        if (addr == self.last_pc) {
                            try self.raiseError(.syntax);
                            return;
                        }
                        self.pc = addr;
                        return;
                    }
                }
                const idx = @as(i32, @intCast(std.ascii.toUpper(c) - 'A'));
                try self.push(idx);
                self.cursor += 1;
            },
            else => return VmError.InvalidOperand,
        }
    }

    fn execTstn(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .addr => |addr| {
                self.skipBlanks();
                const start = self.cursor;
                if (self.readNumber()) |v| {
                    try self.push(v);
                } else {
                    if (addr == self.last_pc) {
                        try self.raiseError(.syntax);
                        return;
                    }
                    self.pc = addr;
                }
                if (self.cursor == start) {
                    if (addr == self.last_pc) {
                        try self.raiseError(.syntax);
                        return;
                    }
                    self.pc = addr;
                }
            },
            else => return VmError.InvalidOperand,
        }
    }

    fn execTstl(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .addr => |addr| {
                self.skipBlanks();
                const c = self.peekChar() orelse {
                    self.pc = addr;
                    return;
                };
                if (!std.ascii.isDigit(c)) {
                    self.pc = addr;
                    return;
                }
                const line_num = self.readNumber() orelse {
                    self.pc = addr;
                    return;
                };
                if (line_num < 1 or line_num > 255) {
                    try self.raiseError(.line_too_large);
                    return;
                }
                self.pending_line_num = @as(u8, @intCast(line_num));
                self.skipBlanks();
                self.pending_text_start = self.cursor;
                self.pending_text_len = trimRightSliceLen(self.line_buf.items[self.cursor..], " \t");
            },
            else => return VmError.InvalidOperand,
        }
    }

    fn execDone(self: *Vm) !void {
        self.skipBlanks();
        if (self.cursor != self.line_buf.items.len) {
            try self.raiseError(.syntax);
        }
    }

    fn execInsrt(self: *Vm) !void {
        const line_num = self.pending_line_num orelse return VmError.InvalidOperand;
        const start = self.pending_text_start;
        const len = self.pending_text_len;
        if (len > self.limits.max_line_len) {
            try self.raiseError(.syntax);
            return;
        }
        const text = self.line_buf.items[start .. start + len];
        const inserting = try self.program_store.insertOrDelete(line_num, text);
        if (inserting and self.program_store.count() > self.limits.max_lines) {
            _ = self.program_store.findExisting(line_num) orelse return;
            _ = try self.program_store.insertOrDelete(line_num, "");
            try self.raiseError(.too_many_lines);
        }
        self.pending_line_num = null;
        self.pending_text_start = 0;
        self.pending_text_len = 0;
    }

    fn listProgram(self: *Vm) !void {
        for (self.program_store.lines.items) |line| {
            try self.appendNumber(@as(i32, line.number));
            try self.writeOut(" ");
            try self.writeOut(line.text);
            try self.writeOut("\n");
        }
    }

    fn execNxt(self: *Vm) !void {
        switch (self.exec_mode) {
            .direct => self.pc = self.label_co,
            .program => try self.execNxtProgram(),
        }
    }

    fn execNxtProgram(self: *Vm) !void {
        if (self.program_store.count() == 0) {
            self.exec_mode = .direct;
            self.current_line_index = null;
            self.pc = self.label_co;
            return;
        }

        const next_index = if (self.current_line_index) |idx| idx + 1 else 0;
        if (next_index >= self.program_store.count()) {
            self.exec_mode = .direct;
            self.current_line_index = null;
            self.pc = self.label_co;
            return;
        }

        try self.loadLineByIndex(next_index);
        self.pc = self.label_stmt;
    }

    fn execXfer(self: *Vm) !void {
        const line_num = try self.pop();
        if (line_num < 1 or line_num > 255) {
            try self.raiseError(.missing_line);
            return;
        }
        const idx = self.program_store.findExisting(@as(u8, @intCast(line_num))) orelse {
            try self.raiseError(.missing_line);
            return;
        };
        self.exec_mode = .program;
        try self.loadLineByIndex(idx);
        self.pc = self.label_stmt;
    }

    fn execSav(self: *Vm) !void {
        if (self.gosub_stack.items.len >= self.limits.max_gosub) {
            try self.raiseError(.too_many_gosubs);
            return;
        }
        const line_num = self.nextLineNumber() orelse {
            try self.raiseError(.missing_line);
            return;
        };
        try self.gosub_stack.append(self.allocator, line_num);
    }

    fn execRstr(self: *Vm) !void {
        if (self.gosub_stack.items.len == 0) {
            try self.raiseError(.return_without_gosub);
            return;
        }
        const idx = self.gosub_stack.items.len - 1;
        const line_num = self.gosub_stack.items[idx];
        self.gosub_stack.items.len = idx;

        const line_index = self.program_store.findExisting(line_num) orelse {
            try self.raiseError(.missing_line);
            return;
        };
        self.exec_mode = .program;
        if (line_index == 0) {
            self.current_line_index = null;
        } else {
            self.current_line_index = line_index - 1;
        }
        self.line_buf.clearRetainingCapacity();
        self.cursor = 0;
    }

    fn execPrs(self: *Vm) !void {
        const start = self.cursor;
        while (self.cursor < self.line_buf.items.len and self.line_buf.items[self.cursor] != '"') : (self.cursor += 1) {}
        if (self.cursor >= self.line_buf.items.len) {
            try self.raiseError(.syntax);
            return;
        }
        const text = self.line_buf.items[start..self.cursor];
        try self.writeOut(text);
        self.cursor += 1;
    }

    fn execSaveProgram(self: *Vm) !void {
        const path = (try self.readQuotedPath()) orelse return;
        if (path.len == 0) {
            try self.raiseError(.syntax);
            return;
        }
        const resolved = try self.ensureBasExtension(path);
        defer if (resolved.owned) |buf| self.allocator.free(buf);

        var file = std.fs.cwd().createFile(resolved.path, .{ .truncate = true }) catch {
            try self.raiseError(.syntax);
            return;
        };
        defer file.close();

        var buf: [32]u8 = undefined;
        for (self.program_store.lines.items) |line| {
            const num = std.fmt.bufPrint(&buf, "{}", .{line.number}) catch {
                try self.raiseError(.syntax);
                return;
            };
            try file.writeAll(num);
            try file.writeAll(" ");
            try file.writeAll(line.text);
            try file.writeAll("\n");
        }
        try self.execDone();
    }

    fn execLoadProgram(self: *Vm) !void {
        const path = (try self.readQuotedPath()) orelse return;
        if (path.len == 0) {
            try self.raiseError(.syntax);
            return;
        }
        try self.loadProgramFromDisk(path);
        try self.execDone();
    }

    fn execChainProgram(self: *Vm) !void {
        const path = (try self.readQuotedPath()) orelse return;
        if (path.len == 0) {
            try self.raiseError(.syntax);
            return;
        }
        try self.loadProgramFromDisk(path);
        try self.execDone();
        self.startProgram();
    }

    fn execCls(self: *Vm) !void {
        try self.writeOut("\x1b[2J\x1b[H");
        self.out_col = 0;
        @memset(self.screen[0..], ' ');
        if (self.gdi) |*g| {
            g.clear(0xFF000000);
            g.present();
        }
    }

    fn execData(self: *Vm) !void {
        try self.skipDataList();
    }

    fn execReadData(self: *Vm) !void {
        if (self.data_index >= self.data_values.items.len) {
            try self.raiseError(.data_out_of_range);
            return;
        }
        const value = self.data_values.items[self.data_index];
        self.data_index += 1;
        try self.push(value);
    }

    fn execRestore(self: *Vm) !void {
        self.data_index = 0;
    }

    fn execPoke(self: *Vm) !void {
        const value = try self.pop();
        const addr = try self.pop();
        if (addr < 0 or addr >= @as(i32, @intCast(self.mem.len))) {
            try self.raiseError(.bad_address);
            return;
        }
        if (addr == 0) {
            self.draw_x = value;
            const clipped = std.math.clamp(value, 0, 255);
            self.mem[0] = @as(u8, @intCast(clipped));
            return;
        }
        if (value < 0 or value > 255) {
            try self.raiseError(.bad_address);
            return;
        }
        self.mem[@as(usize, @intCast(addr))] = @as(u8, @intCast(value));
    }

    fn execPeek(self: *Vm) !void {
        const addr = try self.pop();
        if (addr < 0 or addr >= @as(i32, @intCast(self.mem.len))) {
            try self.raiseError(.bad_address);
            return;
        }
        const value = self.mem[@as(usize, @intCast(addr))];
        try self.push(@as(i32, value));
    }

    fn execBcall(self: *Vm) !void {
        const target = try self.pop();
        if (target < 0) {
            try self.raiseError(.invalid_call);
            return;
        }
        if (target > 255) {
            try self.raiseError(.invalid_call);
            return;
        }
        const id: u8 = @intCast(target);
        if (self.debug_logging) {
            var buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "BCALL {d}\n", .{id}) catch null;
            if (msg) |m| try self.writeLog(m);
        }
        switch (id) {
            1 => try self.execBytecodeVm(),
            2 => try self.execSpriteDraw(),
            3 => self.closeGdi(),
            4 => self.execKeyState(),
            5 => self.execSleep(),
            6 => self.execGdiClear(),
            7 => try self.execTextDraw(),
            else => try self.raiseError(.invalid_call),
        }
    }

    fn execBytecodeVm(self: *Vm) !void {
        const len = @as(usize, self.mem[0]) | (@as(usize, self.mem[1]) << 8);
        const end = 2 + len;
        if (end > self.mem.len) {
            try self.raiseError(.bad_address);
            return;
        }
        var pc: usize = 2;
        var steps: usize = 0;
        while (pc < end) : (steps += 1) {
            if (steps > 100000) {
                try self.raiseError(.invalid_call);
                return;
            }
            const op = self.mem[pc];
            pc += 1;
            switch (op) {
                0x00 => break,
                0x01 => {
                    if (pc >= end) return try self.raiseError(.invalid_call);
                    const ch = self.mem[pc];
                    pc += 1;
                    var buf: [1]u8 = .{ch};
                    try self.writeOut(buf[0..]);
                },
                0x02 => {
                    if (pc >= end) return try self.raiseError(.invalid_call);
                    const v = self.mem[pc];
                    pc += 1;
                    try self.appendNumber(@as(i32, v));
                },
                0x03 => try self.writeOut("\n"),
                0x10 => {
                    if (pc + 2 >= end) return try self.raiseError(.invalid_call);
                    const addr = @as(usize, self.mem[pc]) | (@as(usize, self.mem[pc + 1]) << 8);
                    const val = self.mem[pc + 2];
                    pc += 3;
                    if (addr >= self.mem.len) return try self.raiseError(.bad_address);
                    self.mem[addr] = val;
                },
                0x11 => {
                    if (pc + 1 >= end) return try self.raiseError(.invalid_call);
                    const addr = @as(usize, self.mem[pc]) | (@as(usize, self.mem[pc + 1]) << 8);
                    pc += 2;
                    if (addr >= self.mem.len) return try self.raiseError(.bad_address);
                    self.bytecode_regs[0] = self.mem[addr];
                    self.bytecode_z = self.bytecode_regs[0] == 0;
                },
                0x12 => try self.appendNumber(@as(i32, self.bytecode_regs[0])),
                0x20 => {
                    const reg = try self.readBcReg(end, &pc);
                    const imm = try self.readBcByte(end, &pc);
                    self.bytecode_regs[reg] = imm;
                    self.bytecode_z = imm == 0;
                },
                0x21 => {
                    const reg = try self.readBcReg(end, &pc);
                    const addr = try self.readBcU16(end, &pc);
                    if (addr >= self.mem.len) return try self.raiseError(.bad_address);
                    self.bytecode_regs[reg] = self.mem[addr];
                    self.bytecode_z = self.bytecode_regs[reg] == 0;
                },
                0x22 => {
                    const addr = try self.readBcU16(end, &pc);
                    const reg = try self.readBcReg(end, &pc);
                    if (addr >= self.mem.len) return try self.raiseError(.bad_address);
                    self.mem[addr] = self.bytecode_regs[reg];
                },
                0x23 => {
                    const a = try self.readBcReg(end, &pc);
                    const b = try self.readBcReg(end, &pc);
                    self.bytecode_regs[a] +%= self.bytecode_regs[b];
                    self.bytecode_z = self.bytecode_regs[a] == 0;
                },
                0x24 => {
                    const a = try self.readBcReg(end, &pc);
                    const b = try self.readBcReg(end, &pc);
                    self.bytecode_regs[a] -%= self.bytecode_regs[b];
                    self.bytecode_z = self.bytecode_regs[a] == 0;
                },
                0x25 => {
                    const reg = try self.readBcReg(end, &pc);
                    self.bytecode_regs[reg] +%= 1;
                    self.bytecode_z = self.bytecode_regs[reg] == 0;
                },
                0x26 => {
                    const reg = try self.readBcReg(end, &pc);
                    self.bytecode_regs[reg] -%= 1;
                    self.bytecode_z = self.bytecode_regs[reg] == 0;
                },
                0x27 => {
                    const a = try self.readBcReg(end, &pc);
                    const b = try self.readBcReg(end, &pc);
                    self.bytecode_z = self.bytecode_regs[a] == self.bytecode_regs[b];
                },
                0x28 => {
                    const addr = try self.readBcU16(end, &pc);
                    if (addr < 2 or addr >= end) return try self.raiseError(.invalid_call);
                    pc = addr;
                },
                0x29 => {
                    const addr = try self.readBcU16(end, &pc);
                    if (self.bytecode_z) {
                        if (addr < 2 or addr >= end) return try self.raiseError(.invalid_call);
                        pc = addr;
                    }
                },
                0x2A => {
                    const addr = try self.readBcU16(end, &pc);
                    if (!self.bytecode_z) {
                        if (addr < 2 or addr >= end) return try self.raiseError(.invalid_call);
                        pc = addr;
                    }
                },
                0x2B => {
                    const reg = try self.readBcReg(end, &pc);
                    try self.appendNumber(@as(i32, self.bytecode_regs[reg]));
                },
                0x2C => {
                    const reg = try self.readBcReg(end, &pc);
                    var buf: [1]u8 = .{self.bytecode_regs[reg]};
                    try self.writeOut(buf[0..]);
                },
                0x2D => {
                    const a = try self.readBcReg(end, &pc);
                    const b = try self.readBcReg(end, &pc);
                    self.bytecode_regs[a] &= self.bytecode_regs[b];
                    self.bytecode_z = self.bytecode_regs[a] == 0;
                },
                0x2E => {
                    const a = try self.readBcReg(end, &pc);
                    const b = try self.readBcReg(end, &pc);
                    self.bytecode_regs[a] |= self.bytecode_regs[b];
                    self.bytecode_z = self.bytecode_regs[a] == 0;
                },
                0x2F => {
                    const a = try self.readBcReg(end, &pc);
                    const b = try self.readBcReg(end, &pc);
                    self.bytecode_regs[a] ^= self.bytecode_regs[b];
                    self.bytecode_z = self.bytecode_regs[a] == 0;
                },
                else => return try self.raiseError(.invalid_call),
            }
        }
    }

    fn readBcByte(self: *Vm, end: usize, pc: *usize) !u8 {
        if (pc.* >= end) {
            try self.raiseError(.invalid_call);
            return VmError.InvalidOperand;
        }
        const v = self.mem[pc.*];
        pc.* += 1;
        return v;
    }

    fn readBcU16(self: *Vm, end: usize, pc: *usize) !usize {
        if (pc.* + 1 >= end) {
            try self.raiseError(.invalid_call);
            return VmError.InvalidOperand;
        }
        const lo = self.mem[pc.*];
        const hi = self.mem[pc.* + 1];
        pc.* += 2;
        return @as(usize, lo) | (@as(usize, hi) << 8);
    }

    fn readBcReg(self: *Vm, end: usize, pc: *usize) !usize {
        const v = try self.readBcByte(end, pc);
        if (v >= self.bytecode_regs.len) {
            try self.raiseError(.invalid_call);
            return VmError.InvalidOperand;
        }
        return @intCast(v);
    }

    fn execSpriteDraw(self: *Vm) !void {
        if (self.gdi == null) {
            self.gdi = gdi_mod.Gdi.init(320, 200, 2) catch {
                try self.raiseError(.invalid_call);
                return;
            };
            const g_init = &self.gdi.?;
            g_init.clear(0xFF000000);
            g_init.present();
        }
        const x = self.draw_x;
        const y = @as(i32, self.mem[1]);
        const w = @as(i32, self.mem[2]);
        const h = @as(i32, self.mem[3]);
        if (self.debug_logging) {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "DRAW x={d} y={d} w={d} h={d}\n", .{ x, y, w, h }) catch null;
            if (msg) |m| try self.writeLog(m);
        }
        const data_start: usize = 4;
        if (w <= 0 or h <= 0) return;
        const needed = data_start + @as(usize, @intCast(w * h));
        if (needed > self.mem.len) {
            try self.raiseError(.bad_address);
            return;
        }
        const g = &self.gdi.?;
        g.pump();
        g.drawSprite(x, y, w, h, self.mem[data_start..needed]);
        if (self.gdi_frame_active) {
            self.gdi_dirty = true;
        } else {
            g.present();
        }
    }

    fn execTextDraw(self: *Vm) !void {
        if (self.gdi == null) {
            self.gdi = gdi_mod.Gdi.init(320, 200, 2) catch {
                try self.raiseError(.invalid_call);
                return;
            };
            const g_init = &self.gdi.?;
            g_init.clear(0xFF000000);
            g_init.present();
        }
        const x = self.draw_x;
        const y = @as(i32, self.mem[1]);
        const addr = @as(usize, self.mem[2]) | (@as(usize, self.mem[3]) << 8);
        const len = @as(usize, self.mem[4]);
        const shade = self.mem[5];
        const scale = @as(i32, self.mem[6]);
        if (len == 254) {
            const score = @as(u16, self.mem[8]) | (@as(u16, self.mem[9]) << 8);
            const lives = self.mem[10];
            const level = self.mem[11];
            var buf: [64]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "SCORE {d}  LIVES {d}  LEVEL {d}", .{
                score,
                lives,
                level,
            }) catch {
                try self.raiseError(.invalid_call);
                return;
            };
            const g = &self.gdi.?;
            g.pump();
            g.drawText(x, y, text, shade, scale);
            if (self.gdi_frame_active) {
                self.gdi_dirty = true;
            } else {
                g.present();
            }
            return;
        }
        if (len == 0) {
            var level_text: [7]u8 = .{ 'L', 'E', 'V', 'E', 'L', ' ', self.mem[7] };
            const g = &self.gdi.?;
            g.pump();
            g.drawText(120, 90, level_text[0..], 255, 3);
            g.present();
            var remaining: u32 = 3000;
            while (remaining > 0) {
                const sleep_step: u32 = if (remaining > 16) 16 else remaining;
                gdi_mod.sleepMs(sleep_step);
                remaining -= sleep_step;
                g.pump();
            }
            g.clear(0xFF000000);
            g.present();
            self.gdi_frame_active = false;
            self.gdi_dirty = false;
            return;
        }
        if (addr + len > self.mem.len) {
            try self.raiseError(.bad_address);
            return;
        }
        if (self.debug_logging) {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "TEXT x={d} y={d} addr={d} len={d}\n", .{ x, y, addr, len }) catch null;
            if (msg) |m| try self.writeLog(m);
        }
        const g = &self.gdi.?;
        g.pump();
        g.drawText(x, y, self.mem[addr .. addr + len], shade, scale);
        if (self.gdi_frame_active) {
            self.gdi_dirty = true;
        } else {
            g.present();
        }
    }

    fn closeGdi(self: *Vm) void {
        if (self.gdi) |*g| {
            g.deinit();
        }
        self.gdi = null;
    }

    fn execKeyState(self: *Vm) void {
        const vkey: i32 = @as(i32, self.mem[0]);
        if (self.debug_logging) {
            var buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "KEY vkey={d}\n", .{vkey}) catch null;
            if (msg) |m| self.writeLog(m) catch {};
        }
        self.mem[1] = if (gdi_mod.keyDown(vkey)) 1 else 0;
    }

    fn execSleep(self: *Vm) void {
        const ms: u32 = @as(u32, self.mem[0]) | (@as(u32, self.mem[1]) << 8);
        if (self.debug_logging) {
            var buf: [96]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "SLEEP {d}ms\n", .{ms}) catch null;
            if (msg) |m| self.writeLog(m) catch {};
        }
        if (self.gdi) |*g| {
            // Present current frame before waiting so pause screens are visible immediately.
            if (self.gdi_frame_active and self.gdi_dirty) {
                g.pump();
                g.present();
                self.gdi_dirty = false;
            }
        }
        var remaining = ms;
        while (remaining > 0) {
            const sleep_step: u32 = if (remaining > 16) 16 else remaining;
            gdi_mod.sleepMs(sleep_step);
            remaining -= sleep_step;
            if (self.gdi) |*g| g.pump();
        }
        if (self.gdi) |*g| {
            if (self.gdi_frame_active and self.gdi_dirty) {
                g.pump();
                g.present();
                self.gdi_dirty = false;
            }
        }
        self.gdi_frame_active = false;
    }

    fn execGdiClear(self: *Vm) void {
        if (self.gdi == null) {
            self.gdi = gdi_mod.Gdi.init(320, 200, 2) catch {
                self.raiseError(.invalid_call) catch {};
                return;
            };
        }
        if (self.gdi) |*g| {
            if (self.gdi_frame_active and self.gdi_dirty) {
                g.pump();
                g.present();
            }
            g.clear(0xFF000000);
            self.gdi_frame_active = true;
            self.gdi_dirty = false;
        }
    }

    fn renderScreen(self: *Vm, width: usize, height: usize) !void {
        var row: usize = 0;
        while (row < height) : (row += 1) {
            const start = row * width;
            const slice = self.screen[start .. start + width];
            try self.writeOut(slice);
            try self.writeOut("\n");
        }
    }

    fn execPrn(self: *Vm) !void {
        const value = try self.pop();
        try self.appendNumber(value);
    }

    fn execSpc(self: *Vm) !void {
        const next_zone = ((self.out_col / 8) + 1) * 8;
        const count = next_zone - self.out_col;
        if (count == 0) return;
        var buf: [16]u8 = undefined;
        const n = if (count > buf.len) buf.len else count;
        @memset(buf[0..n], ' ');
        try self.writeOut(buf[0..n]);
    }

    fn execInnum(self: *Vm) !void {
        const value = self.io.readNumber(self.allocator) catch {
            try self.raiseError(.syntax);
            return;
        };
        try self.push(value);
    }

    fn execLit(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .number => |n| try self.push(n),
            else => return VmError.InvalidOperand,
        }
    }

    fn execBinaryOp(self: *Vm, op: BinaryOp) !void {
        const b = try self.pop();
        const a = try self.pop();
        const result = switch (op) {
            .add => a +% b,
            .sub => a -% b,
            .mul => a *% b,
            .div => blk: {
                if (b == 0) {
                    try self.raiseError(.division_by_zero);
                    return;
                }
                break :blk @divTrunc(a, b);
            },
        };
        try self.push(result);
    }

    fn execNeg(self: *Vm) !void {
        const a = try self.pop();
        try self.push(0 -% a);
    }

    fn execCmpr(self: *Vm) !void {
        const b = try self.pop();
        const rel = try self.pop();
        const a = try self.pop();
        const ok = switch (rel) {
            0 => a == b,
            1 => a < b,
            2 => a <= b,
            3 => a != b,
            4 => a > b,
            5 => a >= b,
            else => return VmError.InvalidOperand,
        };
        if (!ok) try self.execNxt();
    }

    fn execJmp(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .addr => |addr| {
                if (addr == self.label_xec and self.last_keyword != null and std.ascii.eqlIgnoreCase(self.last_keyword.?, "RUN")) {
                    self.exec_mode = .program;
                    self.current_line_index = null;
                    self.last_keyword = null;
                }
                self.pc = addr;
            },
            else => return VmError.InvalidOperand,
        }
    }

    fn execCall(self: *Vm, operand: il.AsmOperand) !void {
        switch (operand) {
            .addr => |addr| {
                if (self.call_stack.items.len >= self.limits.max_gosub) {
                    try self.raiseError(.too_many_gosubs);
                    return;
                }
                try self.call_stack.append(self.allocator, self.pc);
                self.pc = addr;
            },
            else => return VmError.InvalidOperand,
        }
    }

    fn execRtn(self: *Vm) !void {
        if (self.call_stack.items.len == 0) {
            try self.raiseError(.return_without_gosub);
            return;
        }
        const ret = self.call_stack.items[self.call_stack.items.len - 1];
        self.call_stack.items.len -= 1;
        self.pc = ret;
    }

    fn execStore(self: *Vm) !void {
        const value = try self.pop();
        const idx = try self.pop();
        if (idx < 0 or idx >= 26) {
            try self.raiseError(.syntax);
            return;
        }
        self.vars[@as(usize, @intCast(idx))] = value;
    }

    fn execInd(self: *Vm) !void {
        const idx = try self.pop();
        if (idx < 0 or idx >= 26) {
            try self.raiseError(.syntax);
            return;
        }
        try self.push(self.vars[@as(usize, @intCast(idx))]);
    }

    fn loadLineByIndex(self: *Vm, index: usize) !void {
        const line = self.program_store.getByIndex(index) orelse return VmError.InvalidOperand;
        self.current_line_index = index;
        self.line_buf.clearRetainingCapacity();
        try self.line_buf.appendSlice(self.allocator, line.text);
        self.cursor = 0;
        if (self.debug_logging) {
            var buf: [600]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "LINE {d:0>3}: {s}\n", .{ line.number, line.text }) catch return;
            try self.writeLog(msg);
        }
    }

    fn push(self: *Vm, value: i32) !void {
        if (self.stack.items.len >= self.limits.max_expr_stack) {
            try self.raiseError(.expr_too_complex);
            return;
        }
        try self.stack.append(self.allocator, value);
    }

    fn pop(self: *Vm) !i32 {
        if (self.stack.items.len == 0) return VmError.StackUnderflow;
        const idx = self.stack.items.len - 1;
        const value = self.stack.items[idx];
        self.stack.items.len -= 1;
        return value;
    }

    fn skipBlanks(self: *Vm) void {
        while (self.cursor < self.line_buf.items.len) : (self.cursor += 1) {
            const c = self.line_buf.items[self.cursor];
            if (c != ' ' and c != '\t') break;
        }
    }

    fn matchString(self: *Vm, text: []const u8) bool {
        if (self.cursor + text.len > self.line_buf.items.len) return false;
        return std.ascii.eqlIgnoreCase(self.line_buf.items[self.cursor .. self.cursor + text.len], text);
    }

    fn matchToken(self: *Vm, text: []const u8) bool {
        if (!self.matchString(text)) return false;
        if (!isAlphaToken(text)) return true;
        const rule = lookupMatchRule(text) orelse MatchRule{};
        if (self.peekCharAt(self.cursor + text.len)) |c| {
            if (isAlpha(c) and !rule.allow_follow_alpha) return false;
            if (std.ascii.isDigit(c) and !rule.allow_follow_digit) return false;
        }
        return true;
    }

    fn readNumber(self: *Vm) ?i32 {
        const start = self.cursor;
        if (self.peekHexPrefix()) {
            const value = self.readHexDigits() orelse {
                self.cursor = start;
                return null;
            };
            return value;
        }
        var value: i32 = 0;
        var any = false;
        while (self.cursor < self.line_buf.items.len) : (self.cursor += 1) {
            const c = self.line_buf.items[self.cursor];
            if (!std.ascii.isDigit(c)) break;
            any = true;
            value = value * 10 + @as(i32, c - '0');
        }
        if (!any) {
            self.cursor = start;
            return null;
        }
        return value;
    }

    fn peekHexPrefix(self: *Vm) bool {
        if (self.cursor >= self.line_buf.items.len) return false;
        const c = self.line_buf.items[self.cursor];
        if (c == '&') {
            if (self.cursor + 1 >= self.line_buf.items.len) return false;
            const h = self.line_buf.items[self.cursor + 1];
            if (h == 'H' or h == 'h') {
                self.cursor += 2;
                return true;
            }
            return false;
        }
        if (c == '0' and self.cursor + 1 < self.line_buf.items.len) {
            const x = self.line_buf.items[self.cursor + 1];
            if (x == 'x' or x == 'X') {
                self.cursor += 2;
                return true;
            }
        }
        return false;
    }

    fn readHexDigits(self: *Vm) ?i32 {
        var value: i32 = 0;
        var any = false;
        while (self.cursor < self.line_buf.items.len) : (self.cursor += 1) {
            const c = self.line_buf.items[self.cursor];
            const digit = hexValue(c) orelse break;
            any = true;
            value = value * 16 + digit;
        }
        if (!any) return null;
        return value;
    }

    fn readQuotedPath(self: *Vm) !?[]const u8 {
        self.skipBlanks();
        const c = self.peekChar() orelse {
            try self.raiseError(.syntax);
            return null;
        };
        if (c != '"') {
            try self.raiseError(.syntax);
            return null;
        }
        self.cursor += 1;
        const start = self.cursor;
        while (self.cursor < self.line_buf.items.len and self.line_buf.items[self.cursor] != '"') : (self.cursor += 1) {}
        if (self.cursor >= self.line_buf.items.len) {
            try self.raiseError(.syntax);
            return null;
        }
        const slice = self.line_buf.items[start..self.cursor];
        self.cursor += 1;
        return slice;
    }

    fn buildDataTable(self: *Vm) !void {
        self.data_values.clearRetainingCapacity();
        self.data_index = 0;
        for (self.program_store.lines.items) |line| {
            var idx: usize = 0;
            skipBlanksAt(line.text, &idx);
            if (!matchTokenAt(line.text, idx, "DATA")) continue;
            idx += 4;
            skipBlanksAt(line.text, &idx);
            if (idx >= line.text.len) {
                try self.raiseError(.syntax);
                return;
            }
            parseDataListFromSlice(line.text, &idx, &self.data_values, self.allocator) catch {
                try self.raiseError(.syntax);
                return;
            };
            skipBlanksAt(line.text, &idx);
            if (idx != line.text.len) {
                try self.raiseError(.syntax);
                return;
            }
        }
    }

    fn skipDataList(self: *Vm) !void {
        var idx = self.cursor;
        parseDataListFromSlice(self.line_buf.items, &idx, null, self.allocator) catch {
            try self.raiseError(.syntax);
            return;
        };
        skipBlanksAt(self.line_buf.items, &idx);
        if (idx != self.line_buf.items.len) {
            try self.raiseError(.syntax);
            return;
        }
        self.cursor = idx;
    }

    const ResolvedPath = struct {
        path: []const u8,
        owned: ?[]u8,
    };

    fn loadProgramFromDisk(self: *Vm, raw_path: []const u8) !void {
        const resolved = try self.ensureBasExtension(raw_path);
        defer if (resolved.owned) |buf| self.allocator.free(buf);

        const data = std.fs.cwd().readFileAlloc(self.allocator, resolved.path, 1024 * 1024) catch {
            try self.raiseError(.syntax);
            return;
        };
        defer self.allocator.free(data);

        self.program_store.clear();

        var it = std.mem.splitScalar(u8, data, '\n');
        while (it.next()) |raw_line| {
            var line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0) continue;

            var idx: usize = 0;
            while (idx < line.len and std.ascii.isDigit(line[idx])) : (idx += 1) {}
            if (idx == 0) {
                try self.raiseError(.syntax);
                return;
            }
            const num_slice = line[0..idx];
            const number = std.fmt.parseInt(i32, num_slice, 10) catch {
                try self.raiseError(.syntax);
                return;
            };
            if (number < 1 or number > 255) {
                try self.raiseError(.line_too_large);
                return;
            }
            var text = std.mem.trimLeft(u8, line[idx..], " \t");
            text = text[0..trimRightSliceLen(text, " \t")];
            const inserted = try self.program_store.insertOrDelete(@as(u8, @intCast(number)), text);
            if (inserted and self.program_store.count() > self.limits.max_lines) {
                _ = try self.program_store.insertOrDelete(@as(u8, @intCast(number)), "");
                try self.raiseError(.too_many_lines);
                return;
            }
        }
    }

    fn ensureBasExtension(self: *Vm, path: []const u8) !ResolvedPath {
        if (!needsBasExtension(path)) return .{ .path = path, .owned = null };
        const buf = try self.allocator.alloc(u8, path.len + 4);
        @memcpy(buf[0..path.len], path);
        @memcpy(buf[path.len..], ".bas");
        return .{ .path = buf, .owned = buf };
    }

    fn writeOut(self: *Vm, text: []const u8) !void {
        self.io.writeAll(text) catch return VmError.InputError;
        for (text) |c| {
            if (c == '\n') {
                self.out_col = 0;
            } else {
                self.out_col += 1;
            }
        }
    }

    fn appendNumber(self: *Vm, value: i32) !void {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{}", .{value}) catch return;
        try self.writeOut(s);
    }

    fn peekChar(self: *Vm) ?u8 {
        if (self.cursor >= self.line_buf.items.len) return null;
        return self.line_buf.items[self.cursor];
    }

    fn peekCharAt(self: *Vm, index: usize) ?u8 {
        if (index >= self.line_buf.items.len) return null;
        return self.line_buf.items[index];
    }

    fn currentLineNumber(self: *Vm) ?u8 {
        if (self.exec_mode != .program) return null;
        const idx = self.current_line_index orelse return null;
        return self.program_store.lines.items[idx].number;
    }

    fn nextLineNumber(self: *Vm) ?u8 {
        if (self.exec_mode != .program) return null;
        const idx = self.current_line_index orelse return null;
        const next_idx = idx + 1;
        if (next_idx >= self.program_store.count()) return null;
        return self.program_store.lines.items[next_idx].number;
    }

    fn raiseError(self: *Vm, code: ErrorCode) !void {
        self.error_state = ErrorState{ .code = code, .line = self.currentLineNumber() };
        var buf: [64]u8 = undefined;
        const code_num: u8 = @intFromEnum(code);
        if (self.error_state.?.line) |ln| {
            const msg = std.fmt.bufPrint(&buf, "I {d:0>3} AT {d:0>3}\n", .{ code_num, ln }) catch return;
            try self.writeOut(msg);
            if (self.debug_logging) try self.writeLog(msg);
        } else {
            const msg = std.fmt.bufPrint(&buf, "I {d:0>3}\n", .{code_num}) catch return;
            try self.writeOut(msg);
            if (self.debug_logging) try self.writeLog(msg);
        }
        self.exec_mode = .direct;
        self.current_line_index = null;
        self.stack.clearRetainingCapacity();
        self.call_stack.clearRetainingCapacity();
        self.gosub_stack.clearRetainingCapacity();
        self.cursor = 0;
        self.pending_line_num = null;
        self.pending_text_start = 0;
        self.pending_text_len = 0;
        self.last_keyword = null;
        self.pc = self.label_co;
    }

    fn logVmError(self: *Vm, err: anyerror) !void {
        if (!self.debug_logging) return;
        var buf: [128]u8 = undefined;
        const line = self.currentLineNumber() orelse 0;
        const msg = std.fmt.bufPrint(
            &buf,
            "VM error: {s} at line {d:0>3} (IL {d})\n",
            .{ @errorName(err), line, self.last_il_line },
        ) catch return;
        try self.writeOut(msg);

        try self.writeLog(msg);
    }

    fn writeLog(self: *Vm, msg: []const u8) !void {
        _ = self;
        var file = std.fs.cwd().createFile("tinybasic.log", .{ .truncate = false }) catch return;
        defer file.close();
        _ = file.seekFromEnd(0) catch {};
        _ = file.writeAll(msg) catch {};
    }
};

fn lookupLabel(labels: *const std.StringHashMap(usize), name: []const u8) !usize {
    if (labels.get(name)) |addr| return addr;
    return VmError.UnknownLabel;
}

fn trimRightInPlace(buf: *std.ArrayList(u8), chars: []const u8) void {
    const len = trimRightSliceLen(buf.items, chars);
    buf.items.len = len;
}

fn trimRightSliceLen(slice: []const u8, chars: []const u8) usize {
    var end = slice.len;
    while (end != 0) {
        const c = slice[end - 1];
        if (std.mem.indexOfScalar(u8, chars, c) == null) break;
        end -= 1;
    }
    return end;
}

fn isAlpha(c: u8) bool {
    return (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z');
}

fn hexValue(c: u8) ?i32 {
    if (c >= '0' and c <= '9') return @intCast(c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(c - 'A' + 10);
    return null;
}

fn isAlphaToken(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| {
        if (!isAlpha(c)) return false;
    }
    return true;
}

fn lookupMatchRule(text: []const u8) ?MatchRule {
    var buf: [16]u8 = undefined;
    if (text.len == 0 or text.len > buf.len) return null;
    for (text, 0..) |c, i| {
        buf[i] = std.ascii.toUpper(c);
    }
    return keyword_rules.get(buf[0..text.len]);
}

fn needsBasExtension(path: []const u8) bool {
    var last_sep: ?usize = null;
    var last_dot: ?usize = null;
    for (path, 0..) |c, i| {
        if (c == '/' or c == '\\') last_sep = i;
        if (c == '.') last_dot = i;
    }
    if (last_dot == null) return true;
    if (last_sep != null and last_dot.? < last_sep.?) return true;
    if (last_dot.? == path.len - 1) return true;
    return false;
}

fn parseDataListFromSlice(line: []const u8, idx: *usize, out: ?*std.ArrayList(i32), allocator: std.mem.Allocator) !void {
    skipBlanksAt(line, idx);
    const first = parseNumberAt(line, idx) orelse return VmError.InvalidOperand;
    if (out) |list| try list.append(allocator, first);
    skipBlanksAt(line, idx);
    while (idx.* < line.len and line[idx.*] == ',') {
        idx.* += 1;
        skipBlanksAt(line, idx);
        const v = parseNumberAt(line, idx) orelse return VmError.InvalidOperand;
        if (out) |list| try list.append(allocator, v);
        skipBlanksAt(line, idx);
    }
}

fn parseNumberAt(line: []const u8, idx: *usize) ?i32 {
    var sign: i32 = 1;
    if (idx.* < line.len and (line[idx.*] == '-' or line[idx.*] == '+')) {
        if (line[idx.*] == '-') sign = -1;
        idx.* += 1;
    }
    if (idx.* >= line.len) return null;
    if (line[idx.*] == '&' and idx.* + 1 < line.len and (line[idx.* + 1] == 'H' or line[idx.* + 1] == 'h')) {
        idx.* += 2;
        const value = parseHexAt(line, idx) orelse return null;
        return value * sign;
    }
    if (line[idx.*] == '0' and idx.* + 1 < line.len and (line[idx.* + 1] == 'x' or line[idx.* + 1] == 'X')) {
        idx.* += 2;
        const value = parseHexAt(line, idx) orelse return null;
        return value * sign;
    }
    var value: i32 = 0;
    var any = false;
    while (idx.* < line.len and std.ascii.isDigit(line[idx.*])) {
        any = true;
        value = value * 10 + @as(i32, line[idx.*] - '0');
        idx.* += 1;
    }
    if (!any) return null;
    return value * sign;
}

fn parseHexAt(line: []const u8, idx: *usize) ?i32 {
    var value: i32 = 0;
    var any = false;
    while (idx.* < line.len) {
        const digit = hexValue(line[idx.*]) orelse break;
        any = true;
        value = value * 16 + digit;
        idx.* += 1;
    }
    if (!any) return null;
    return value;
}

fn skipBlanksAt(line: []const u8, idx: *usize) void {
    while (idx.* < line.len) : (idx.* += 1) {
        const c = line[idx.*];
        if (c != ' ' and c != '\t') break;
    }
}

fn matchTokenAt(line: []const u8, idx: usize, text: []const u8) bool {
    if (idx + text.len > line.len) return false;
    if (!std.ascii.eqlIgnoreCase(line[idx .. idx + text.len], text)) return false;
    if (!isAlphaToken(text)) return true;
    const rule = lookupMatchRule(text) orelse MatchRule{};
    if (idx + text.len < line.len) {
        const c = line[idx + text.len];
        if (isAlpha(c) and !rule.allow_follow_alpha) return false;
        if (std.ascii.isDigit(c) and !rule.allow_follow_digit) return false;
    }
    return true;
}

test "program store insert/replace/delete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var store = ProgramStore.init(arena.allocator());
    defer store.deinit();

    _ = try store.insertOrDelete(10, "PRINT 1");
    _ = try store.insertOrDelete(5, "LET A=1");
    _ = try store.insertOrDelete(20, "END");

    try std.testing.expectEqual(@as(usize, 3), store.count());
    try std.testing.expectEqual(@as(u8, 5), store.lines.items[0].number);
    try std.testing.expectEqual(@as(u8, 10), store.lines.items[1].number);

    _ = try store.insertOrDelete(10, "PRINT 2");
    try std.testing.expect(std.mem.eql(u8, store.lines.items[1].text, "PRINT 2"));

    _ = try store.insertOrDelete(5, "");
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

test "vm arithmetic" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .LIT, .operand = .{ .number = 2 }, .line_no = 1 },
        .{ .opcode = .LIT, .operand = .{ .number = 3 }, .line_no = 1 },
        .{ .opcode = .ADD, .operand = .none, .line_no = 1 },
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    try vm.run();
    try std.testing.expectEqual(@as(usize, 1), vm.stack.items.len);
    try std.testing.expectEqual(@as(i32, 5), vm.stack.items[0]);
}

test "tst keyword boundary rules" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    try vm.line_buf.appendSlice(arena.allocator(), "RUNX");
    vm.cursor = 0;
    vm.pc = 10;
    try vm.execTst(.{ .addr_string = .{ .addr = 99, .text = "RUN" } });
    try std.testing.expectEqual(@as(usize, 99), vm.pc);

    vm.line_buf.clearRetainingCapacity();
    try vm.line_buf.appendSlice(arena.allocator(), "LETA=1");
    vm.cursor = 0;
    vm.pc = 10;
    try vm.execTst(.{ .addr_string = .{ .addr = 99, .text = "LET" } });
    try std.testing.expectEqual(@as(usize, 10), vm.pc);
    try std.testing.expectEqual(@as(usize, 3), vm.cursor);

    vm.line_buf.clearRetainingCapacity();
    try vm.line_buf.appendSlice(arena.allocator(), "TO10");
    vm.cursor = 0;
    vm.pc = 10;
    try vm.execTst(.{ .addr_string = .{ .addr = 99, .text = "TO" } });
    try std.testing.expectEqual(@as(usize, 10), vm.pc);
    try std.testing.expectEqual(@as(usize, 2), vm.cursor);
}

test "execDone raises syntax and resets" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    _ = try vm.program_store.insertOrDelete(10, "RUNX");
    vm.exec_mode = .program;
    vm.current_line_index = 0;
    try vm.line_buf.appendSlice(arena.allocator(), "RUNX");
    vm.cursor = 0;

    try vm.execDone();
    try std.testing.expect(vm.error_state != null);
    try std.testing.expectEqual(ErrorCode.syntax, vm.error_state.?.code);
    try std.testing.expectEqual(ExecMode.direct, vm.exec_mode);
    try std.testing.expectEqual(vm.label_co, vm.pc);
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "I 001 AT 010\n"));
}

test "listProgram formatting" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    _ = try vm.program_store.insertOrDelete(10, "PRINT 1");
    _ = try vm.program_store.insertOrDelete(5, "LET A=1");

    try vm.listProgram();
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "5 LET A=1\n10 PRINT 1\n"));
}

test "execSpc advances zones" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    vm.out_col = 1;
    try vm.execSpc();
    try std.testing.expectEqual(@as(usize, 8), vm.out_col);
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "       "));

    io_state.output.clearRetainingCapacity();
    vm.out_col = 8;
    try vm.execSpc();
    try std.testing.expectEqual(@as(usize, 16), vm.out_col);
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "        "));
}

test "execXfer loads target line" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 42);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    _ = try vm.program_store.insertOrDelete(10, "PRINT 1");
    _ = try vm.program_store.insertOrDelete(20, "END");

    try vm.push(20);
    try vm.execXfer();
    try std.testing.expectEqual(ExecMode.program, vm.exec_mode);
    try std.testing.expectEqual(@as(?usize, 1), vm.current_line_index);
    try std.testing.expect(std.mem.eql(u8, vm.line_buf.items, "END"));
    try std.testing.expectEqual(@as(usize, 0), vm.cursor);
    try std.testing.expectEqual(@as(usize, 42), vm.pc);
}

test "gosub save and restore flows to next line" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 77);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    _ = try vm.program_store.insertOrDelete(10, "GOSUB 30");
    _ = try vm.program_store.insertOrDelete(20, "PRINT 1");
    _ = try vm.program_store.insertOrDelete(30, "RETURN");

    vm.exec_mode = .program;
    vm.current_line_index = 0;

    try vm.execSav();
    try std.testing.expectEqual(@as(usize, 1), vm.gosub_stack.items.len);
    try std.testing.expectEqual(@as(u8, 20), vm.gosub_stack.items[0]);

    try vm.execRstr();
    try std.testing.expectEqual(ExecMode.program, vm.exec_mode);
    try std.testing.expectEqual(@as(?usize, 0), vm.current_line_index);

    try vm.execNxtProgram();
    try std.testing.expect(std.mem.eql(u8, vm.line_buf.items, "PRINT 1"));
    try std.testing.expectEqual(@as(usize, 77), vm.pc);
}

test "execXfer missing line triggers error" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    _ = try vm.program_store.insertOrDelete(10, "PRINT 1");

    try vm.push(99);
    try vm.execXfer();
    try std.testing.expect(vm.error_state != null);
    try std.testing.expectEqual(ErrorCode.missing_line, vm.error_state.?.code);
    try std.testing.expectEqual(ExecMode.direct, vm.exec_mode);
    try std.testing.expectEqual(vm.label_co, vm.pc);
}

test "tstl inserts and deletes program lines" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    try io_state.pushLine("10 PRINT 1");
    try vm.getLine();
    vm.pc = 55;
    try vm.execTstl(.{ .addr = 123 });
    try std.testing.expectEqual(@as(usize, 55), vm.pc);
    try std.testing.expectEqual(@as(?u8, 10), vm.pending_line_num);
    try vm.execInsrt();

    try std.testing.expectEqual(@as(usize, 1), vm.program_store.count());
    try std.testing.expect(std.mem.eql(u8, vm.program_store.lines.items[0].text, "PRINT 1"));

    try io_state.pushLine("10");
    try vm.getLine();
    try vm.execTstl(.{ .addr = 123 });
    try vm.execInsrt();
    try std.testing.expectEqual(@as(usize, 0), vm.program_store.count());
}

test "getline over max length raises syntax" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 7);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    const too_long = try arena.allocator().alloc(u8, vm.limits.max_line_len + 1);
    @memset(too_long, 'A');
    try io_state.pushLine(too_long);
    try vm.getLine();
    try std.testing.expect(vm.error_state != null);
    try std.testing.expectEqual(ErrorCode.syntax, vm.error_state.?.code);
    try std.testing.expectEqual(@as(usize, 7), vm.pc);
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "I 001\n"));
}

test "readNumber does not consume unary sign" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    try vm.line_buf.appendSlice(arena.allocator(), "-1");
    vm.cursor = 0;
    try std.testing.expectEqual(@as(?i32, null), vm.readNumber());
    try std.testing.expectEqual(@as(usize, 0), vm.cursor);

    vm.line_buf.clearRetainingCapacity();
    try vm.line_buf.appendSlice(arena.allocator(), "123");
    vm.cursor = 0;
    try std.testing.expectEqual(@as(?i32, 123), vm.readNumber());
    try std.testing.expectEqual(@as(usize, 3), vm.cursor);
}

test "division by zero reports error" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    try vm.push(10);
    try vm.push(0);
    try vm.execBinaryOp(.div);
    try std.testing.expect(vm.error_state != null);
    try std.testing.expectEqual(ErrorCode.division_by_zero, vm.error_state.?.code);
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "I 008\n"));
}

test "input error triggers syntax" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .INNUM, .operand = .none, .line_no = 1 },
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    try vm.step();
    try std.testing.expect(vm.error_state != null);
    try std.testing.expectEqual(ErrorCode.syntax, vm.error_state.?.code);
    try std.testing.expect(std.mem.eql(u8, io_state.output.items, "I 001\n"));
}

test "gosub stack overflow reports error" {
    const prog = [_]il.AssembledInstruction{
        .{ .opcode = .FIN, .operand = .none, .line_no = 1 },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var labels = std.StringHashMap(usize).init(arena.allocator());
    defer labels.deinit();
    try labels.put("CO", 0);
    try labels.put("STMT", 0);
    try labels.put("XEC", 0);

    var io_state = BufferIo.init(arena.allocator());
    defer io_state.deinit();
    var io = io_state.toIo();

    var vm = try Vm.init(arena.allocator(), &prog, &labels, &io);
    defer vm.deinit();

    _ = try vm.program_store.insertOrDelete(10, "GOSUB 20");
    _ = try vm.program_store.insertOrDelete(20, "RETURN");
    vm.exec_mode = .program;
    vm.current_line_index = 0;

    var i: usize = 0;
    while (i < vm.limits.max_gosub) : (i += 1) {
        try vm.execSav();
    }
    try vm.execSav();
    try std.testing.expect(vm.error_state != null);
    try std.testing.expectEqual(ErrorCode.too_many_gosubs, vm.error_state.?.code);
}
