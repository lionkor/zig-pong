const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const game_exe = b.addExecutable("zig-pong", "src/GameMain.zig");
    game_exe.setTarget(target);
    game_exe.setBuildMode(mode);
    game_exe.linkLibC();
    game_exe.linkSystemLibrary("sdl2");
    game_exe.install();

    const run_game_cmd = game_exe.run();
    run_game_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_game_cmd.addArgs(args);
    }

    const server_exe = b.addExecutable("zig-pong-server", "src/ServerMain.zig");
    server_exe.setTarget(target);
    server_exe.setBuildMode(mode);
    server_exe.install();

    const run_server_cmd = server_exe.run();
    run_server_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_server_cmd.addArgs(args);
    }

    const run_game_step = b.step("run", "Run the game");
    run_game_step.dependOn(&run_game_cmd.step);

    const run_server_step = b.step("run-server", "Run the server");
    run_server_step.dependOn(&run_server_cmd.step);

    const test_step = b.step("test", "Run unit tests");

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    for ([_][]const u8{"src/Vec2.zig"}) |src| {
        const src_tests = b.addTest(src);
        src_tests.setTarget(target);
        src_tests.setBuildMode(mode);
        test_step.dependOn(&src_tests.step);
    }
}
