const std = @import("std");
const ir = @import("ir.zig");
const cf = @import("optimizer/constant_folding.zig");
const lvn = @import("optimizer/lvn.zig");
const Function = ir.Function;
const ConstantFolding = cf.ConstantFolding;
const LocalValueNumbering = lvn.LocalValueNumbering;

test {
    _ = @import("union_find.zig");
    _ = @import("ir.zig");
    _ = @import("optimizer/lvn.zig");
    _ = @import("optimizer/constant_folding.zig");
    _ = @import("optimizer/optimizer.zig");
}

test "local value numbering" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();

    const bb = try function.createBlock();
    const val1 = try function.pushInsn(bb, .{
        .constant = .{ .value = 10 },
    });
    const val2 = try function.pushInsn(bb, .{
        .constant = .{ .value = 5 },
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

test "constant folding snapshot" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();

    const bb = try function.createBlock();
    const val1 = try function.pushInsn(bb, .{
        .constant = .{ .value = 10 },
    });
    const val2 = try function.pushInsn(bb, .{
        .constant = .{ .value = 5 },
    });
    _ = try function.pushInsn(bb, .{
        .add = .{ .lhs = val1, .rhs = val2 },
    });
    _ = try function.pushInsn(bb, .{
        .sub = .{ .lhs = val1, .rhs = val2 },
    });
    _ = try function.pushInsn(bb, .{
        .mul = .{ .lhs = val1, .rhs = val2 },
    });
    const div = try function.pushInsn(bb, .{
        .div = .{ .lhs = val1, .rhs = val2 },
    });
    try function.setTerminator(bb, .{
        .ret = .{ .value = div },
    });

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try function.dumpIr(&out.writer);
    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(10)
        \\  v1 = Const Value(5)
        \\  v2 = Add v0, v1
        \\  v3 = Sub v0, v1
        \\  v4 = Mul v0, v1
        \\  v5 = Div v0, v1
        \\  Return v5
        \\
    ,
        out.writer.buffered(),
    );
    out.clearRetainingCapacity();

    const constant_folding = ConstantFolding.init(&function);
    try constant_folding.run();
    try function.dumpIr(&out.writer);

    try std.testing.expectEqualStrings(
        \\bb0()
        \\  v0 = Const Value(10)
        \\  v1 = Const Value(5)
        \\  v6 = Const Value(15)
        \\  v7 = Const Value(5)
        \\  v8 = Const Value(50)
        \\  v9 = Const Value(2)
        \\  Return v9
        \\
    ,
        out.writer.buffered(),
    );
}

test "RPO" {
    var function = Function.init(std.testing.allocator);
    defer function.deinit();

    const entry = try function.createBlock();
    const bb1 = try function.createBlock();
    const bb2 = try function.createBlock();
    const bb3 = try function.createBlock();
    const cond = try function.pushInsn(entry, .{
        .constant = .{ .value = 1 },
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
        .constant = .{ .value = 5 },
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
