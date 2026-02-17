const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "tinybasic",
        .root_module = main_mod,
    });
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");

    b.installArtifact(exe);

    const exe_gui = b.addExecutable(.{
        .name = "tinybasicw",
        .root_module = main_mod,
    });
    exe_gui.subsystem = .Windows;
    exe_gui.linkSystemLibrary("user32");
    exe_gui.linkSystemLibrary("gdi32");
    b.installArtifact(exe_gui);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run tinybasic");
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const il_test_mod = b.createModule(.{
        .root_source_file = b.path("src/il.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vm_test_mod = b.createModule(.{
        .root_source_file = b.path("src/il_vm.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lexer_test_mod = b.createModule(.{
        .root_source_file = b.path("src/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser_test_mod = b.createModule(.{
        .root_source_file = b.path("src/parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const semantic_test_mod = b.createModule(.{
        .root_source_file = b.path("src/semantic.zig"),
        .target = target,
        .optimize = optimize,
    });

    const emit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/basic_emit.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = test_mod });
    tests.linkSystemLibrary("user32");
    tests.linkSystemLibrary("gdi32");
    const run_tests = b.addRunArtifact(tests);
    const il_tests = b.addTest(.{ .root_module = il_test_mod });
    const run_il_tests = b.addRunArtifact(il_tests);
    const vm_tests = b.addTest(.{ .root_module = vm_test_mod });
    vm_tests.linkSystemLibrary("user32");
    vm_tests.linkSystemLibrary("gdi32");
    const run_vm_tests = b.addRunArtifact(vm_tests);
    const lexer_tests = b.addTest(.{ .root_module = lexer_test_mod });
    const run_lexer_tests = b.addRunArtifact(lexer_tests);
    const parser_tests = b.addTest(.{ .root_module = parser_test_mod });
    const run_parser_tests = b.addRunArtifact(parser_tests);
    const semantic_tests = b.addTest(.{ .root_module = semantic_test_mod });
    const run_semantic_tests = b.addRunArtifact(semantic_tests);
    const emit_tests = b.addTest(.{ .root_module = emit_test_mod });
    const run_emit_tests = b.addRunArtifact(emit_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_il_tests.step);
    test_step.dependOn(&run_vm_tests.step);
    test_step.dependOn(&run_lexer_tests.step);
    test_step.dependOn(&run_parser_tests.step);
    test_step.dependOn(&run_semantic_tests.step);
    test_step.dependOn(&run_emit_tests.step);
}
