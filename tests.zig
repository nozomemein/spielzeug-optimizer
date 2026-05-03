const std = @import("std");
const ir = @import("ir.zig");
const lvn = @import("lvn.zig");
const Function = ir.Function;
const LocalValueNumbering = lvn.LocalValueNumbering;

test "local value numbering" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var function = Function.init(arena_state.allocator());
    const bb = try function.createBlock();
    const val1 = try function.pushInsn(bb, .{
        .const_ = .{ .value = 10 },
    });
    const val2 = try function.pushInsn(bb, .{
        .const_ = .{ .value = 5 },
    });
    _ = try function.pushInsn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    const add2 = try function.pushInsn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    try function.setTerminator(bb, .{
        .ret = .{ .value = add2 },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dumpIr(&out.writer);
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
    const local_value_numbering = LocalValueNumbering.init(&function);
    try local_value_numbering.run();
    try function.dumpIr(&out.writer);

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
    const entry = try function.createBlock();
    const bb1 = try function.createBlock();
    const bb2 = try function.createBlock();
    const bb3 = try function.createBlock();
    const cond = try function.pushInsn(entry, .{
        .const_ = .{ .value = 1 },
    });
    try function.setTerminator(entry, .{
        .branch = .{ .cond = cond, .then_block = bb1, .else_block = bb2 },
    });
    try function.setTerminator(bb1, .{
        .jump = .{ .target = bb3 },
    });
    try function.setTerminator(bb2, .{
        .jump = .{ .target = bb3 },
    });
    const bb3val = try function.pushInsn(bb3, .{
        .const_ = .{ .value = 5 },
    });
    try function.setTerminator(bb3, .{
        .ret = .{ .value = bb3val },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dumpIr(&out.writer);
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
