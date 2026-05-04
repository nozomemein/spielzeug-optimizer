const std = @import("std");
const ir = @import("ir.zig");
const opt = @import("optimizer/optimizer.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    // Preparing for stdout
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;

    var function = ir.Function.init(arena);
    defer function.deinit();
    const entry = try function.createBlock();
    function.entry = entry;
    const val1 = try function.pushInsn(entry, .{
        .const_ = .{ .value = 10 },
    });
    const val2 = try function.pushInsn(entry, .{
        .const_ = .{ .value = 5 },
    });
    _ = try function.pushInsn(entry, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    _ = try function.pushInsn(entry, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });

    const jump_target = try function.createBlock();
    try function.setTerminator(entry, .{
        .jump = .{ .target = jump_target },
    });

    const val3 = try function.pushInsn(jump_target, .{
        .const_ = .{ .value = 15 },
    });
    try function.setTerminator(jump_target, .{
        .ret = .{ .value = val3 },
    });

    try function.dumpIr(stdout);
    const optimizer = opt.Optimizer.init(&function);
    try optimizer.run();
    try function.dumpIr(stdout);
    try stdout.flush();
}
