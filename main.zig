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

test "local value numbering" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var function = Function.init(arena_state.allocator());
    const bb = try function.create_block();
    const val1 = try function.push_insn(bb, .{
        .const_ = .{ .value = 10 },
    });
    const val2 = try function.push_insn(bb, .{
        .const_ = .{ .value = 5 },
    });
    _ = try function.push_insn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    const add2 = try function.push_insn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    try function.set_terminator(bb, .{
        .ret = .{ .value = add2 },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dump_ir(&out.writer);
    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(10)
        \\  v1 = Const Value(5)
        \\  v2 = Add v0, v1
        \\  v3 = Add v0, v1
        \\  Return v3
        \\
    ,
        out.writer.buffered(),
    );
    out.clearRetainingCapacity();
    try lvn.run(&function);
    try function.dump_ir(&out.writer);

    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(10)
        \\  v1 = Const Value(5)
        \\  v2 = Add v0, v1
        \\  Return v2
        \\
    ,
        out.writer.buffered(),
    );
}

test "RPO" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var function = Function.init(arena_state.allocator());
    const entry = try function.create_block();
    const bb1 = try function.create_block();
    const bb2 = try function.create_block();
    const bb3 = try function.create_block();
    const cond = try function.push_insn(entry, .{
        .const_ = .{ .value = 1 },
    });
    try function.set_terminator(entry, .{
        .branch = .{ .cond = cond, .then_block = bb1, .else_block = bb2 },
    });
    try function.set_terminator(bb1, .{
        .jump = .{ .target = bb3 },
    });
    try function.set_terminator(bb2, .{
        .jump = .{ .target = bb3 },
    });
    const bb3val = try function.push_insn(bb3, .{
        .const_ = .{ .value = 5 },
    });
    try function.set_terminator(bb3, .{
        .ret = .{ .value = bb3val },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dump_ir(&out.writer);
    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(1)
        \\  Branch v0, bb1, bb2
        \\bb1()
        \\  Jump bb3
        \\bb2()
        \\  Jump bb3
        \\bb3()
        \\  v1 = Const Value(5)
        \\  Return v1
        \\
    ,
        out.writer.buffered(),
    );
    out.clearRetainingCapacity();
}
