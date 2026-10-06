const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pg = b.dependency("pg", .{ .target = target, .optimize = optimize });

    // The ORM itself, importable as `@import("pg_orm")`.
    const mod = b.addModule("pg_orm", .{
        .root_source_file = b.path("src/orm.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("pg", pg.module("pg"));

    // Tests. Zig only collects `test` blocks from the root file of a test
    // binary, so src/tests.zig names every file that carries them.
    const tests = b.addTest(.{
        .name = "pg_orm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "pg", .module = pg.module("pg") }},
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;

    const test_step = b.step("test", "Run the ORM tests");
    test_step.dependOn(&run_tests.step);

    // Example: end-to-end ORM walk-through.
    const example = b.addExecutable(.{
        .name = "orm_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/orm_example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pg", .module = pg.module("pg") },
                .{ .name = "pg_orm", .module = mod },
            },
        }),
    });
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    if (b.args) |args| run_example.addArgs(args);
    const example_step = b.step("example", "Run the ORM example");
    example_step.dependOn(&run_example.step);
}
