const std = @import("std");
const ir = @import("ir.zig");
const Function = ir.Function;
const lvn = @import("lvn.zig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    // Preparing for stdout
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;

    var function = Function.init(arena);
    const entry = try function.create_block();
    function.entry = entry;
    const val1 = try function.push_insn(entry, .{
        .const_ = .{ .value = 10 },
    });
    const val2 = try function.push_insn(entry, .{
        .const_ = .{ .value = 5 },
    });
    _ = try function.push_insn(entry, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    _ = try function.push_insn(entry, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });

    const jump_target = try function.create_block();
    try function.set_terminator(entry, .{
        .jump = .{ .target = jump_target },
    });

    const val3 = try function.push_insn(jump_target, .{
        .const_ = .{ .value = 15 },
    });
    try function.set_terminator(jump_target, .{
        .ret = .{ .value = val3 },
    });

    try function.dump_ir(stdout);
    try stdout.flush();
}
