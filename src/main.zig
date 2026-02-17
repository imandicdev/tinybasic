const std = @import("std");
const il = @import("il.zig");
const vm_mod = @import("il_vm.zig");
const parser = @import("parser.zig");
const semantic = @import("semantic.zig");
const basic_emit = @import("basic_emit.zig");
const ast = @import("ast.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        try runInteractive(allocator);
        return;
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "run")) {
        if (args.len < 3) return usage();
        try runFile(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, cmd, "list")) {
        if (args.len < 3) return usage();
        try listFile(allocator, args[2]);
        return;
    }
    if (std.mem.eql(u8, cmd, "dump-il")) {
        try dumpIl();
        return;
    }
    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try usage();
        return;
    }

    try usage();
}

fn runInteractive(allocator: std.mem.Allocator) !void {
    var assembled = try il.assemble(allocator, @embedFile("il_program.il"));
    defer assembled.deinit();

    var console = vm_mod.ConsoleIo.init();
    var io = console.toIo();

    var vm = try vm_mod.Vm.init(allocator, assembled.instructions.items, &assembled.labels, &io);
    defer vm.deinit();

    try printBanner(&vm);
    try vm.run();
}

fn runFile(allocator: std.mem.Allocator, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(source);

    const program = try parser.parseProgram(arena.allocator(), source);
    try semantic.validateProgram(arena.allocator(), program);

    var assembled = try il.assemble(allocator, @embedFile("il_program.il"));
    defer assembled.deinit();

    var console = vm_mod.ConsoleIo.init();
    var io = console.toIo();

    var vm = try vm_mod.Vm.init(allocator, assembled.instructions.items, &assembled.labels, &io);
    defer vm.deinit();

    try loadProgram(&vm, arena.allocator(), program);
    vm.startProgram();
    try vm.run();
}

fn listFile(allocator: std.mem.Allocator, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(source);

    const program = try parser.parseProgram(arena.allocator(), source);
    try semantic.validateProgram(arena.allocator(), program);

    const listing = try basic_emit.emitProgram(arena.allocator(), program);
    try std.fs.File.stdout().writeAll(listing);
}

fn dumpIl() !void {
    const il_source = @embedFile("il_program.il");
    try std.fs.File.stdout().writeAll(il_source);
}

fn loadProgram(vm: *vm_mod.Vm, allocator: std.mem.Allocator, program: ast.Program) !void {
    vm.clearProgram();
    for (program.lines) |line| {
        if (line.number == null) continue;
        if (line.stmt == null) continue;
        const num: u8 = @intCast(line.number.?);
        const text = try basic_emit.emitLineText(allocator, line.stmt.?);
        try vm.insertProgramLine(num, text);
    }
}

fn usage() !void {
    const msg =
        "tinybasic usage:\n" ++
        "  tinybasic                 (interactive)\n" ++
        "  tinybasic run <file.bas>\n" ++
        "  tinybasic list <file.bas>\n" ++
        "  tinybasic dump-il\n";
    try std.fs.File.stdout().writeAll(msg);
}

fn printBanner(vm: *const vm_mod.Vm) !void {
    var buf: [256]u8 = undefined;
    const used = vm.programBytesUsed();
    const max_bytes = vm.limits.max_lines * vm.limits.max_line_len;
    const msg = std.fmt.bufPrint(
        &buf,
        "TinyBASIC (Zig 0.15.x) - Copyright (c) Ilija Mandic, 2026\n" ++
            "Lines: {d}/{d}  LineLen: {d}  Vars: {d}  ExprStack: {d}  GOSUB: {d}\n" ++
            "Program bytes: {d}/{d}\n",
        .{
            vm.programLineCount(),
            vm.limits.max_lines,
            vm.limits.max_line_len,
            26,
            vm.limits.max_expr_stack,
            vm.limits.max_gosub,
            used,
            max_bytes,
        },
    ) catch return;
    try std.fs.File.stdout().writeAll(msg);
}
